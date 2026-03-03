#Requires -Version 5.1
<#
.SYNOPSIS
    AnimatedDesktop -- Matrix cascade wallpaper engine for Windows.

.DESCRIPTION
    Renders a Matrix-style cascade of falling binary digits (green on black)
    as the live desktop wallpaper, entirely with built-in .NET/WinForms APIs.
    No administrator rights or external dependencies are required.

.PARAMETER Speed
    Animation speed: 'Slow' (300 ms/frame), 'Normal' (150 ms/frame, default),
    or 'Fast' (80 ms/frame).

.PARAMETER FontSize
    Matrix character font size in points (default: 14).

.PARAMETER Density
    Fraction of columns active at any moment (0.1-1.0, default: 0.75).

.NOTES
    Run via the Start-Menu shortcut, or manually:
    powershell.exe -ExecutionPolicy Bypass -File "%LOCALAPPDATA%\AnimatedDesktop\AnimatedDesktop.ps1"
#>

[CmdletBinding()]
param(
    [ValidateSet('Slow', 'Normal', 'Fast')]
    [string]$Speed   = 'Normal',
    [ValidateRange(8, 32)]
    [int]$FontSize   = 14,
    [ValidateRange(0.1, 1.0)]
    [double]$Density = 0.75
)

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

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

$script:WallpaperBmp        = Join-Path $env:TEMP 'AnimatedDesktop_wallpaper.bmp'
$script:FontSize            = $FontSize
$script:ColWidth            = $FontSize + 2    # pixels per column
$script:RowHeight           = $FontSize + 6    # pixels per row
$script:Density             = $Density
$script:AnimationIntervalMs = switch ($Speed) {
    'Slow'  { 300 }
    'Fast'  {  80 }
    default { 150 }
}

$script:Rng                  = New-Object System.Random
$script:Drops                = @()
$script:MatrixFont           = $null  # created lazily; disposed on FormClosed
$script:MaxStatusMsgLength   = 55     # max chars shown in the status-bar error summary

# Pre-compute green brush palette (one brush per brightness level 0-255)
$script:GreenBrushes = [System.Drawing.SolidBrush[]]( 0..255 | ForEach-Object {
    New-Object System.Drawing.SolidBrush(
        [System.Drawing.Color]::FromArgb(255, 0, $_, 0))
})
$script:WhiteBrush   = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)

# ---------------------------------------------------------------------------
# Initialise Matrix column drops for the primary screen dimensions
# ---------------------------------------------------------------------------
function Initialize-MatrixDrops {
    $bounds  = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $numCols = [int]($bounds.Width  / $script:ColWidth)
    $numRows = [int]($bounds.Height / $script:RowHeight) + 2

    $script:Drops = for ($c = 0; $c -lt $numCols; $c++) {
        $len = 5 + $script:Rng.Next(20)
        @{
            X       = $c * $script:ColWidth
            Head    = if ($script:Rng.NextDouble() -le $script:Density) {
                          $script:Rng.Next($numRows)
                      } else {
                          -$script:Rng.Next(5, 40)
                      }
            Len     = $len
            Speed   = 1 + $script:Rng.Next(3)
            NumRows = $numRows
            Chars   = [string[]]( 0..($len + 5) | ForEach-Object {
                          if ($script:Rng.Next(2) -eq 0) { '0' } else { '1' }
                      })
        }
    }
}

# ---------------------------------------------------------------------------
# Advance all drops by one tick
# ---------------------------------------------------------------------------
function Step-MatrixDrops {
    foreach ($drop in $script:Drops) {
        $drop.Head += $drop.Speed
        if (($drop.Head - $drop.Len) -gt $drop.NumRows) {
            $drop.Head  = -$script:Rng.Next(5, 30)
            $drop.Len   = 5 + $script:Rng.Next(20)
            $drop.Speed = 1 + $script:Rng.Next(3)
            $newLen     = $drop.Len + 5
            $drop.Chars = [string[]]( 0..$newLen | ForEach-Object {
                              if ($script:Rng.Next(2) -eq 0) { '0' } else { '1' }
                          })
        }
    }
}

# ---------------------------------------------------------------------------
# Render the current Matrix frame onto a Graphics object
# ---------------------------------------------------------------------------
function Render-MatrixFrame {
    param(
        [System.Drawing.Graphics]$Gfx,
        [int]$Width,
        [int]$Height
    )

    if ($null -eq $script:MatrixFont -or $script:MatrixFont.IsDisposed) {
        $script:MatrixFont = New-Object System.Drawing.Font(
            'Courier New', $script:FontSize, [System.Drawing.FontStyle]::Bold)
    }

    $Gfx.FillRectangle([System.Drawing.Brushes]::Black, 0, 0, $Width, $Height)

    foreach ($drop in $script:Drops) {
        $trailLen  = $drop.Len
        $charCount = $drop.Chars.Length
        for ($i = 0; $i -le $trailLen; $i++) {
            $row = $drop.Head - $i
            if ($row -lt 0 -or $row -ge $drop.NumRows) { continue }
            $y = $row * $script:RowHeight
            if ($y -ge $Height) { continue }

            $ch = $drop.Chars[$i % $charCount]

            if ($i -eq 0) {
                # Leading character: white
                $brush = $script:WhiteBrush
            } else {
                # Trail fades from bright green to near-black
                $brightness = [int](255 * (1.0 - [double]$i / ($trailLen + 1)))
                if ($brightness -lt 20) { $brightness = 20 }
                $brush = $script:GreenBrushes[$brightness]
            }

            $Gfx.DrawString($ch, $script:MatrixFont, $brush, [float]$drop.X, [float]$y)
        }
    }
}

# ---------------------------------------------------------------------------
# Render a frame, set it as the desktop wallpaper, and return the bitmap
# (caller owns the returned bitmap and must dispose it)
# ---------------------------------------------------------------------------
function New-MatrixWallpaper {
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp    = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
    $gfx    = [System.Drawing.Graphics]::FromImage($bmp)
    $gfx.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::SingleBitPerPixelGridFit
    try {
        Render-MatrixFrame -Gfx $gfx -Width $bounds.Width -Height $bounds.Height
        $bmp.Save($script:WallpaperBmp, [System.Drawing.Imaging.ImageFormat]::Bmp)
        [NativeMethods]::SystemParametersInfo(
            [NativeMethods]::SPI_SETDESKWALLPAPER, 0, $script:WallpaperBmp,
            ([NativeMethods]::SPIF_UPDATEINIFILE -bor [NativeMethods]::SPIF_SENDCHANGE)
        ) | Out-Null
    } finally {
        $gfx.Dispose()
    }
    return $bmp
}

# ---------------------------------------------------------------------------
# Initialise drop state before the UI is built
# ---------------------------------------------------------------------------
Initialize-MatrixDrops

# ---------------------------------------------------------------------------
# Build the UI
# ---------------------------------------------------------------------------

$form                  = New-Object System.Windows.Forms.Form
$form.Text             = 'AnimatedDesktop'
$form.Size             = New-Object System.Drawing.Size(400, 330)
$form.StartPosition    = 'CenterScreen'
$form.FormBorderStyle  = 'FixedSingle'
$form.MaximizeBox      = $false
$form.BackColor        = [System.Drawing.Color]::FromArgb(28, 28, 28)
$form.ForeColor        = [System.Drawing.Color]::White

$lblTitle              = New-Object System.Windows.Forms.Label
$lblTitle.Text         = 'AnimatedDesktop'
$lblTitle.Font         = New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)
$lblTitle.Location     = New-Object System.Drawing.Point(20, 12)
$lblTitle.Size         = New-Object System.Drawing.Size(360, 36)
$lblTitle.ForeColor    = [System.Drawing.Color]::FromArgb(0, 255, 65)
$form.Controls.Add($lblTitle)

$lblStatus             = New-Object System.Windows.Forms.Label
$lblStatus.Text        = 'Status: Stopped'
$lblStatus.Font        = New-Object System.Drawing.Font('Segoe UI', 10)
$lblStatus.Location    = New-Object System.Drawing.Point(20, 56)
$lblStatus.Size        = New-Object System.Drawing.Size(360, 24)
$form.Controls.Add($lblStatus)

# Preview panel: shows the Matrix animation scaled to fit
$preview               = New-Object System.Windows.Forms.PictureBox
$preview.Location      = New-Object System.Drawing.Point(20, 88)
$preview.Size          = New-Object System.Drawing.Size(360, 160)
$preview.BackColor     = [System.Drawing.Color]::Black
$preview.BorderStyle   = 'FixedSingle'
$preview.SizeMode      = 'StretchImage'
$form.Controls.Add($preview)

$btnStart              = New-Object System.Windows.Forms.Button
$btnStart.Text         = 'Start'
$btnStart.Location     = New-Object System.Drawing.Point(20, 264)
$btnStart.Size         = New-Object System.Drawing.Size(80, 28)
$btnStart.FlatStyle    = 'Flat'
$btnStart.BackColor    = [System.Drawing.Color]::FromArgb(0, 120, 215)
$btnStart.ForeColor    = [System.Drawing.Color]::White
$form.Controls.Add($btnStart)

$btnStop               = New-Object System.Windows.Forms.Button
$btnStop.Text          = 'Stop'
$btnStop.Location      = New-Object System.Drawing.Point(110, 264)
$btnStop.Size          = New-Object System.Drawing.Size(80, 28)
$btnStop.FlatStyle     = 'Flat'
$btnStop.BackColor     = [System.Drawing.Color]::FromArgb(50, 50, 50)
$btnStop.ForeColor     = [System.Drawing.Color]::White
$btnStop.Enabled       = $false
$form.Controls.Add($btnStop)

$lblVer                = New-Object System.Windows.Forms.Label
$lblVer.Text           = "v0.2.0  --  Matrix cascade  |  Speed: $Speed  |  Font: ${FontSize}pt  |  Density: $Density"
$lblVer.Font           = New-Object System.Drawing.Font('Segoe UI', 8)
$lblVer.Location       = New-Object System.Drawing.Point(20, 300)
$lblVer.Size           = New-Object System.Drawing.Size(360, 18)
$lblVer.ForeColor      = [System.Drawing.Color]::DimGray
$form.Controls.Add($lblVer)

# ---------------------------------------------------------------------------
# Timer: advance drops, render wallpaper, update preview
# ---------------------------------------------------------------------------

$timer          = New-Object System.Windows.Forms.Timer
$timer.Interval = $script:AnimationIntervalMs
$timer.Add_Tick({
    try {
        Step-MatrixDrops

        # Render frame; same bitmap is used for both wallpaper and preview
        $bmp = $null
        try {
            $bmp = New-MatrixWallpaper

            # Hand off bitmap to PictureBox (StretchImage scales it for preview)
            $old = $preview.Image
            $preview.Image = $bmp
            $bmp = $null          # ownership transferred; do not dispose below
            if ($null -ne $old) { $old.Dispose() }
        } finally {
            if ($null -ne $bmp) { $bmp.Dispose() }
        }
    } catch {
        # Log the error to the status label but keep running -- prevents crashes
        $msg = [string]$_.Exception.Message
        if ($msg.Length -gt $script:MaxStatusMsgLength) { $msg = $msg.Substring(0, $script:MaxStatusMsgLength) + '...' }
        $lblStatus.Text = "Status: Running  [!] $msg"
    }
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
    # Dispose cached GDI resources
    if ($null -ne $script:MatrixFont -and -not $script:MatrixFont.IsDisposed) {
        $script:MatrixFont.Dispose()
    }
    $script:WhiteBrush.Dispose()
    foreach ($b in $script:GreenBrushes) { $b.Dispose() }
    # Dispose preview image
    if ($null -ne $preview.Image) { $preview.Image.Dispose() }
    # Clean up temp wallpaper file
    if (Test-Path $script:WallpaperBmp) {
        Remove-Item $script:WallpaperBmp -ErrorAction SilentlyContinue
    }
})

[System.Windows.Forms.Application]::Run($form)
