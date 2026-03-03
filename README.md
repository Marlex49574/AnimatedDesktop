# AnimatedDesktop

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