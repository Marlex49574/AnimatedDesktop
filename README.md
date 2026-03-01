# AnimatedDesktop

A Windows desktop application that renders an **HTML/CSS/JS animated background** (Matrix binary-cascade rain) directly behind your desktop icons using the [WorkerW/Progman technique](https://www.codeproject.com/Articles/856020/Draw-Behind-Desktop-Icons-in-Windows-Plus).

The animation is displayed inside a borderless [Microsoft WebView2](https://developer.microsoft.com/en-us/microsoft-edge/webview2/) window that is attached as a child of the `WorkerW` shell window, placing it between the wallpaper layer and the icon layer.

---

## Features

| Feature | Detail |
|---------|--------|
| Animation | Matrix binary-cascade rain (Katakana + ASCII) |
| Renderer | WebView2 (Chromium) loading a local `assets/matrix.html` file |
| Desktop integration | Progman → WorkerW re-parent trick (Windows 10/11) |
| Focus behaviour | `WS_EX_NOACTIVATE` + `ShowWithoutActivation` – never steals focus |
| Taskbar / Alt-Tab | Hidden via `WS_EX_TOOLWINDOW` |
| Exit | System-tray icon **right-click → Exit** *or* **Ctrl+Alt+Q** hotkey |
| DPI | Per-Monitor V2 DPI aware (declared in `app.manifest`) |
| Multi-monitor | Covers the primary monitor; extend by duplicating `Screen.AllScreens` logic |

---

## Prerequisites

| Requirement | Version |
|-------------|---------|
| Windows | 10 (1903+) or 11 |
| .NET SDK | 8.0 or later |
| WebView2 Runtime | Ships with Windows 11; for Windows 10 install the [Evergreen Bootstrapper](https://developer.microsoft.com/en-us/microsoft-edge/webview2/#download-section) |

---

## Build

```powershell
# Clone the repository
git clone https://github.com/Marlex49574/AnimatedDesktop.git
cd AnimatedDesktop

# Restore NuGet packages and build (Release)
dotnet build -c Release
```

The output is placed in `bin\Release\net8.0-windows\`.

---

## Run

```powershell
dotnet run
```

Or run the compiled executable directly:

```powershell
.\bin\Release\net8.0-windows\AnimatedDesktop.exe
```

> **Note:** The first launch may take a few seconds while WebView2 initialises its user-data directory.

---

## Exit

* **System tray** – right-click the tray icon → **Exit AnimatedDesktop**
* **Keyboard** – press **Ctrl+Alt+Q** anywhere

---

## Customising the animation

Edit `assets/matrix.html`. The file is a self-contained HTML/JS/CSS page that is loaded by WebView2 from the local file-system. Key constants at the top of the `<script>` block:

| Constant | Default | Purpose |
|----------|---------|---------|
| `FONT_SIZE` | `16` px | Column width / character cell size |
| `BASE_SPEED` | `1.5` | Average fall speed (columns per frame) |
| `TARGET_FPS` | `30` | Render frame rate |
| `FG_COLOR` | `#0f0` | Primary trail colour |
| `FADE_FILL` | `rgba(0,0,0,0.05)` | Trail decay rate (lower = longer trails) |

---

## Project structure

```
AnimatedDesktop/
├── AnimatedDesktop.csproj   # .NET 8 Windows Forms project
├── app.manifest             # PerMonitorV2 DPI awareness declaration
├── Program.cs               # Entry point
├── MainForm.cs              # Main window + Win32 interop + tray icon
└── assets/
    └── matrix.html          # Matrix rain animation (HTML/JS/CSS)
```

---

## How it works

1. **Progman message** – Sending message `0x052C` to the `Progman` window causes the shell to spawn a `WorkerW` sibling window that sits between the wallpaper renderer and the desktop-icon layer.
2. **`SetParent`** – Our borderless `MainForm` is re-parented into that `WorkerW` window via `SetParent(Handle, workerW)`.
3. **WebView2** – A full-size `WebView2` control fills the form and navigates to `assets/matrix.html` using a `file://` URI.
4. **Non-activating** – `WS_EX_NOACTIVATE` and `ShowWithoutActivation = true` ensure the window never steals keyboard focus.

---

## License

MIT
