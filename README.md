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
Matrix cascade wallpaper engine for Windows 10 and later.
Renders falling binary digits (0 and 1) in classic green-on-black Matrix style as your live desktop wallpaper.

## Installation

Open a **PowerShell** window and run one of the following commands:

### One-liner (download and run)

```powershell
irm https://raw.githubusercontent.com/Marlex49574/AnimatedDesktop/main/install.ps1 | iex
```

### Run locally after cloning

```powershell
git clone https://github.com/Marlex49574/AnimatedDesktop.git
cd AnimatedDesktop
.\install.ps1
```

### Uninstall

```powershell
.\install.ps1 -Uninstall
```

## How to run

After installation, launch AnimatedDesktop in one of two ways:

1. **Start Menu** — open the Start Menu and search for **AnimatedDesktop**.
2. **Command line** — run the following from any PowerShell prompt:

```powershell
powershell.exe -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\AnimatedDesktop\AnimatedDesktop.ps1"
```

The application opens a small control window with a live Matrix preview.  
Press **Start** to begin — falling binary digits cascade across the desktop wallpaper in green-on-black Matrix style.  
Press **Stop** to pause, or close the window to exit.

Optional parameters can be passed on the command line:

| Parameter | Values | Default | Effect |
|---|---|---|---|
| `-Speed` | `Slow` / `Normal` / `Fast` | `Normal` | Frame interval (300 / 150 / 80 ms) |
| `-FontSize` | `8`–`32` | `14` | Matrix character font size in points |
| `-Density` | `0.1`–`1.0` | `0.75` | Fraction of columns active at any moment |

Example — fast, large characters, maximum density:

```powershell
powershell.exe -ExecutionPolicy Bypass -File AnimatedDesktop.ps1 -Speed Fast -FontSize 18 -Density 1.0
```

## What the installer does

1. **Checks prerequisites** — Windows 10+, PowerShell 5.1+, .NET runtime.
2. **Downloads the latest release** from GitHub (HTTPS only) and verifies the
   SHA-256 checksum when one is published alongside the release asset.
3. **Falls back to a source install** if no release is available yet — downloads
   `AnimatedDesktop.ps1` directly from raw.githubusercontent.com (no `git` required).
4. **Installs** to `%LOCALAPPDATA%\AnimatedDesktop` (no admin rights required).
5. **Creates a Start-Menu shortcut** that launches PowerShell with the installed script.
6. **Idempotent** — re-running updates or repairs an existing installation.

## Smoke tests (manual verification)

After running the installer, verify the following:

| Check | How to verify |
|---|---|
| Install directory exists | `Test-Path "$env:LOCALAPPDATA\AnimatedDesktop\AnimatedDesktop.ps1"` returns `True` |
| Start-Menu shortcut exists | `Test-Path "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\AnimatedDesktop.lnk"` returns `True` |
| App launches | Double-click the Start-Menu shortcut — the AnimatedDesktop window should open |
| Preview visible | The control window contains a black preview panel |
| Animation works | Click **Start** — falling 0/1 digits in green cascade across the desktop wallpaper; the preview panel animates in sync |
| No crash after 60 s | Leave running for at least one minute — the app must remain stable |
| Stop works | Click **Stop** — the wallpaper cycling pauses |
| Uninstall cleans up | Run `.\install.ps1 -Uninstall`; confirm both the install directory and the shortcut are removed |

## Requirements

| Requirement | Minimum version |
|---|---|
| Windows | 10+ |
| PowerShell | 5.1 |
