using System;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using Microsoft.Web.WebView2.WinForms;

namespace AnimatedDesktop;

/// <summary>
/// Borderless, non-activating window that renders an HTML animation
/// behind the desktop icons using the Progman/WorkerW technique.
/// </summary>
public sealed class MainForm : Form
{
    // ── Win32 P/Invoke ────────────────────────────────────────────────────────

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr FindWindow(string lpClassName, string? lpWindowName);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr FindWindowEx(
        IntPtr hwndParent, IntPtr hwndChildAfter,
        string lpszClass, string? lpszWindow);

    [DllImport("user32.dll")]
    private static extern IntPtr SendMessageTimeout(
        IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam,
        uint fuFlags, uint uTimeout, out IntPtr lpdwResult);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetParent(IntPtr hWndChild, IntPtr hWndNewParent);

    [DllImport("user32.dll")]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll")]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    [DllImport("user32.dll")]
    private static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);

    [DllImport("user32.dll")]
    private static extern int GetWindowLong(IntPtr hWnd, int nIndex);

    // Extended window styles
    private const int GWL_EXSTYLE = -20;
    private const int WS_EX_TOOLWINDOW = 0x00000080;   // hidden from taskbar/alt-tab
    private const int WS_EX_NOACTIVATE = 0x08000000;   // does not activate on click

    // SendMessageTimeout flags
    private const uint SMTO_NORMAL = 0x0000;

    // WM_HOTKEY and modifier constants
    private const int WM_HOTKEY = 0x0312;
    private const uint MOD_CONTROL = 0x0002;
    private const uint MOD_ALT = 0x0001;
    private const uint VK_Q = 0x51;
    private const int HotkeyId = 1;

    // ── Fields ────────────────────────────────────────────────────────────────

    private readonly WebView2 _webView;
    private readonly NotifyIcon _trayIcon;

    // ── Construction ──────────────────────────────────────────────────────────

    public MainForm()
    {
        // --- Basic window configuration ---
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        TopMost = false;
        BackColor = Color.Black;

        // Cover the primary monitor exactly
        Rectangle screen = Screen.PrimaryScreen!.Bounds;
        Location = screen.Location;
        Size = screen.Size;

        // --- WebView2 ---
        _webView = new WebView2
        {
            Dock = DockStyle.Fill,
        };
        Controls.Add(_webView);

        // --- Tray icon ---
        _trayIcon = BuildTrayIcon();

        // --- Event wiring ---
        Load += OnLoad;
        FormClosed += OnFormClosed;
    }

    // ── Tray icon ─────────────────────────────────────────────────────────────

    private NotifyIcon BuildTrayIcon()
    {
        var menu = new ContextMenuStrip();
        menu.Items.Add("Exit AnimatedDesktop", null, (_, _) => ExitApp());

        var icon = new NotifyIcon
        {
            Text = "AnimatedDesktop",
            Icon = SystemIcons.Application,
            Visible = true,
            ContextMenuStrip = menu,
        };
        icon.DoubleClick += (_, _) => ExitApp();
        return icon;
    }

    private void ExitApp()
    {
        _trayIcon.Visible = false;
        Application.Exit();
    }

    // ── Form load ─────────────────────────────────────────────────────────────

    private async void OnLoad(object? sender, EventArgs e)
    {
        // Make the window non-activating and hidden from alt-tab / taskbar
        int exStyle = GetWindowLong(Handle, GWL_EXSTYLE);
        SetWindowLong(Handle, GWL_EXSTYLE, exStyle | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW);

        // Attach behind desktop icons
        AttachToWorkerW();

        // Register Ctrl+Alt+Q hotkey
        RegisterHotKey(Handle, HotkeyId, MOD_CONTROL | MOD_ALT, VK_Q);

        // Initialise WebView2 and load the animation
        await _webView.EnsureCoreWebView2Async();

        string htmlPath = Path.Combine(AppContext.BaseDirectory, "assets", "matrix.html");
        if (!File.Exists(htmlPath))
        {
            MessageBox.Show(
                $"Animation file not found:\n{htmlPath}",
                "AnimatedDesktop – Missing File",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
            ExitApp();
            return;
        }

        _webView.CoreWebView2.Navigate(new Uri(htmlPath).AbsoluteUri);
    }

    private void OnFormClosed(object? sender, FormClosedEventArgs e)
    {
        UnregisterHotKey(Handle, HotkeyId);
        _trayIcon.Dispose();
    }

    // ── WorkerW / Progman technique ───────────────────────────────────────────

    /// <summary>
    /// Uses the documented Progman trick to spawn a WorkerW window and then
    /// re-parents our window into it so we sit between the desktop wallpaper
    /// and the desktop icons.
    /// </summary>
    private void AttachToWorkerW()
    {
        IntPtr progman = FindWindow("Progman", null);
        if (progman == IntPtr.Zero)
            return;

        // Tell Progman to spawn a WorkerW sibling (message 0x052C).
        SendMessageTimeout(progman, 0x052C, IntPtr.Zero, IntPtr.Zero,
                           SMTO_NORMAL, 1000, out _);

        // Walk the window tree to find the WorkerW that has a SHELLDLL_DefView
        // child — that is the one sitting above the wallpaper.
        IntPtr workerW = IntPtr.Zero;
        EnumWindows((hwnd, _) =>
        {
            IntPtr defView = FindWindowEx(hwnd, IntPtr.Zero, "SHELLDLL_DefView", null);
            if (defView != IntPtr.Zero)
            {
                // The sibling WorkerW (the one we want) comes *after* this one.
                workerW = FindWindowEx(IntPtr.Zero, hwnd, "WorkerW", null);
                return false; // stop enumeration
            }
            return true;
        }, IntPtr.Zero);

        if (workerW == IntPtr.Zero)
            return;

        SetParent(Handle, workerW);
    }

    // Minimal EnumWindows wrapper (avoids a separate static class)
    private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    // ── Hotkey (WM_HOTKEY) ────────────────────────────────────────────────────

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WM_HOTKEY && m.WParam.ToInt32() == HotkeyId)
        {
            ExitApp();
            return;
        }
        base.WndProc(ref m);
    }

    // ── Prevent activation on click ───────────────────────────────────────────

    protected override bool ShowWithoutActivation => true;

    // CreateParams forces WS_EX_NOACTIVATE at creation time (belt-and-suspenders).
    protected override CreateParams CreateParams
    {
        get
        {
            CreateParams cp = base.CreateParams;
            cp.ExStyle |= WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW;
            return cp;
        }
    }
}
