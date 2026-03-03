#Requires -Version 5.1
<#
.SYNOPSIS
    AnimatedDesktop -- animated wallpaper engine for Windows.

.DESCRIPTION
    Cycles the desktop wallpaper through an animated colour-gradient, rendering
    a smooth hue rotation entirely with built-in .NET/WinForms APIs.
    No administrator rights or external dependencies are required.

.NOTES
    Run via the Start-Menu shortcut, or manually:
    powershell.exe -ExecutionPolicy Bypass -File "%LOCALAPPDATA%\AnimatedDesktop\AnimatedDesktop.ps1"
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# P/Invoke: SystemParametersInfo to set the desktop wallpaper
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class NativeMethods {
    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern bool SystemParametersInfo(
        uint uiAction, uint uiParam, string pvParam, uint fWinIni);

    public const uint SPI_SETDESKWALLPAPER = 0x0014;
    public const uint SPIF_UPDATEINIFILE   = 0x0001;
    public const uint SPIF_SENDCHANGE      = 0x0002;
}
'@

$script:WallpaperBmp     = Join-Path $env:TEMP 'AnimatedDesktop_wallpaper.bmp'
$script:Hue              = 0
$script:AnimationIntervalMs = 2000   # milliseconds between wallpaper updates
$script:HueStepDegrees   = 5         # hue degrees advanced per tick

# Convert a hue (0-359) to a fully-saturated, full-value RGB colour
function ConvertFrom-Hue {
    param([double]$H)
    $H      = $H % 360
    $sector = [int]($H / 60)
    $frac   = ($H / 60) - $sector
    $p      = 0
    $q      = [int]((1 - $frac) * 255)
    $t      = [int]($frac * 255)
    switch ($sector) {
        0 { return [System.Drawing.Color]::FromArgb(255, 255,   $t,   $p) }
        1 { return [System.Drawing.Color]::FromArgb(255,  $q, 255,   $p) }
        2 { return [System.Drawing.Color]::FromArgb(255,  $p, 255,   $t) }
        3 { return [System.Drawing.Color]::FromArgb(255,  $p,  $q, 255) }
        4 { return [System.Drawing.Color]::FromArgb(255,  $t,  $p, 255) }
        5 { return [System.Drawing.Color]::FromArgb(255, 255,  $p,  $q) }
        default { return [System.Drawing.Color]::White }
    }
}

# Render a gradient bitmap and set it as the desktop wallpaper
function Set-WallpaperColor {
    param([System.Drawing.Color]$Color)

    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp    = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
    $gfx    = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $dark  = [System.Drawing.Color]::FromArgb(
            255,
            [int]($Color.R * 0.25),
            [int]($Color.G * 0.25),
            [int]($Color.B * 0.25)
        )
        $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
            [System.Drawing.Point]::new(0, 0),
            [System.Drawing.Point]::new($bounds.Width, $bounds.Height),
            $Color,
            $dark
        )
        $gfx.FillRectangle($brush, 0, 0, $bounds.Width, $bounds.Height)
        $brush.Dispose()
        $bmp.Save($script:WallpaperBmp, [System.Drawing.Imaging.ImageFormat]::Bmp)
        [NativeMethods]::SystemParametersInfo(
            [NativeMethods]::SPI_SETDESKWALLPAPER, 0, $script:WallpaperBmp,
            ([NativeMethods]::SPIF_UPDATEINIFILE -bor [NativeMethods]::SPIF_SENDCHANGE)
        ) | Out-Null
    }
    finally {
        $gfx.Dispose()
        $bmp.Dispose()
    }
}

# ---------------------------------------------------------------------------
# Build the UI
# ---------------------------------------------------------------------------

$form                  = New-Object System.Windows.Forms.Form
$form.Text             = 'AnimatedDesktop'
$form.Size             = New-Object System.Drawing.Size(360, 220)
$form.StartPosition    = 'CenterScreen'
$form.FormBorderStyle  = 'FixedSingle'
$form.MaximizeBox      = $false
$form.BackColor        = [System.Drawing.Color]::FromArgb(28, 28, 28)
$form.ForeColor        = [System.Drawing.Color]::White

$lblTitle              = New-Object System.Windows.Forms.Label
$lblTitle.Text         = 'AnimatedDesktop'
$lblTitle.Font         = New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)
$lblTitle.Location     = New-Object System.Drawing.Point(20, 18)
$lblTitle.Size         = New-Object System.Drawing.Size(320, 36)
$lblTitle.ForeColor    = [System.Drawing.Color]::FromArgb(0, 200, 255)
$form.Controls.Add($lblTitle)

$lblStatus             = New-Object System.Windows.Forms.Label
$lblStatus.Text        = 'Status: Stopped'
$lblStatus.Font        = New-Object System.Drawing.Font('Segoe UI', 10)
$lblStatus.Location    = New-Object System.Drawing.Point(20, 62)
$lblStatus.Size        = New-Object System.Drawing.Size(320, 24)
$form.Controls.Add($lblStatus)

$colorBox              = New-Object System.Windows.Forms.Panel
$colorBox.Location     = New-Object System.Drawing.Point(20, 100)
$colorBox.Size         = New-Object System.Drawing.Size(40, 40)
$colorBox.BackColor    = [System.Drawing.Color]::DimGray
$colorBox.BorderStyle  = 'FixedSingle'
$form.Controls.Add($colorBox)

$btnStart              = New-Object System.Windows.Forms.Button
$btnStart.Text         = 'Start'
$btnStart.Location     = New-Object System.Drawing.Point(80, 107)
$btnStart.Size         = New-Object System.Drawing.Size(80, 28)
$btnStart.FlatStyle    = 'Flat'
$btnStart.BackColor    = [System.Drawing.Color]::FromArgb(0, 120, 215)
$btnStart.ForeColor    = [System.Drawing.Color]::White
$form.Controls.Add($btnStart)

$btnStop               = New-Object System.Windows.Forms.Button
$btnStop.Text          = 'Stop'
$btnStop.Location      = New-Object System.Drawing.Point(170, 107)
$btnStop.Size          = New-Object System.Drawing.Size(80, 28)
$btnStop.FlatStyle     = 'Flat'
$btnStop.BackColor     = [System.Drawing.Color]::FromArgb(50, 50, 50)
$btnStop.ForeColor     = [System.Drawing.Color]::White
$btnStop.Enabled       = $false
$form.Controls.Add($btnStop)

$lblVer                = New-Object System.Windows.Forms.Label
$lblVer.Text           = 'v0.1.0  --  Animated wallpaper engine for Windows'
$lblVer.Font           = New-Object System.Drawing.Font('Segoe UI', 8)
$lblVer.Location       = New-Object System.Drawing.Point(20, 155)
$lblVer.Size           = New-Object System.Drawing.Size(320, 20)
$lblVer.ForeColor      = [System.Drawing.Color]::DimGray
$form.Controls.Add($lblVer)

# ---------------------------------------------------------------------------
# Timer: advance hue and refresh wallpaper every 2 seconds
# ---------------------------------------------------------------------------

$timer          = New-Object System.Windows.Forms.Timer
$timer.Interval = $script:AnimationIntervalMs
$timer.Add_Tick({
    $script:Hue     = ($script:Hue + $script:HueStepDegrees) % 360
    $color          = ConvertFrom-Hue $script:Hue
    $colorBox.BackColor = $color
    Set-WallpaperColor $color
})

# ---------------------------------------------------------------------------
# Button handlers
# ---------------------------------------------------------------------------

$btnStart.Add_Click({
    $timer.Start()
    $lblStatus.Text      = 'Status: Running'
    $btnStart.Enabled    = $false
    $btnStop.Enabled     = $true
    $btnStop.BackColor   = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $btnStart.BackColor  = [System.Drawing.Color]::FromArgb(50, 50, 50)
})

$btnStop.Add_Click({
    $timer.Stop()
    $lblStatus.Text      = 'Status: Stopped'
    $btnStop.Enabled     = $false
    $btnStart.Enabled    = $true
    $btnStart.BackColor  = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $btnStop.BackColor   = [System.Drawing.Color]::FromArgb(50, 50, 50)
})

$form.Add_FormClosed({
    $timer.Stop()
    $timer.Dispose()
    if (Test-Path $script:WallpaperBmp) {
        Remove-Item $script:WallpaperBmp -ErrorAction SilentlyContinue
    }
})

[System.Windows.Forms.Application]::Run($form)
