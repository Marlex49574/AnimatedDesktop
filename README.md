# AnimatedDesktop

Animated wallpaper engine for Windows 10 and later.

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

## What the installer does

1. **Checks prerequisites** — Windows 10+, PowerShell 5.1+, .NET runtime.
2. **Downloads the latest release** from GitHub (HTTPS only) and verifies the
   SHA-256 checksum when one is published alongside the release asset.
3. **Falls back to a source build** if no release is available yet.
4. **Installs** to `%LOCALAPPDATA%\AnimatedDesktop` (no admin rights required).
5. **Creates a Start-Menu shortcut** for easy access.
6. **Idempotent** — re-running updates or repairs an existing installation.

## Requirements

| Requirement | Minimum version |
|---|---|
| Windows | 10+ |
| PowerShell | 5.1 |