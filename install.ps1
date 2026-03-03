#Requires -Version 5.1
<#
.SYNOPSIS
    AnimatedDesktop installer.

.DESCRIPTION
    Downloads (or builds) AnimatedDesktop, installs it to the current user's
    local application-data folder, and creates a Start-Menu shortcut.
    Re-running this script is safe -- it will update or repair an existing
    installation without leaving orphaned files behind.

.PARAMETER InstallDir
    Override the default installation directory.
    Default: $env:LOCALAPPDATA\AnimatedDesktop

.PARAMETER Uninstall
    Remove AnimatedDesktop and its Start-Menu shortcut.

.EXAMPLE
    # One-liner from a PowerShell prompt:
    irm https://raw.githubusercontent.com/Marlex49574/AnimatedDesktop/main/install.ps1 | iex

.EXAMPLE
    # Local run:
    .\install.ps1

.EXAMPLE
    # Uninstall:
    .\install.ps1 -Uninstall
#>

# Write-Host is intentional for colored, interactive installer output (PS 5+)
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingWriteHost', '',
    Justification = 'Installer uses Write-Host for colored console output')]
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $InstallDir = "$env:LOCALAPPDATA\AnimatedDesktop",
    [switch] $Uninstall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Write-Header {
    param([string]$Text)
    Write-Host ''
    Write-Host "==> $Text" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Text)
    Write-Host "  [OK]  $Text" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Text)
    Write-Host "  [!!]  $Text" -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$Text)
    Write-Host "  [XX]  $Text" -ForegroundColor Red
}

# ---------------------------------------------------------------------------
# Prerequisites
# ---------------------------------------------------------------------------

function Test-Prerequisite {
    Write-Header 'Checking prerequisites'

    # Operating system
    if ([System.Environment]::OSVersion.Platform -ne 'Win32NT') {
        Write-Fail 'AnimatedDesktop requires Windows.'
        exit 1
    }

    $winVer = [System.Environment]::OSVersion.Version
    if ($winVer.Major -lt 10) {
        Write-Fail "Windows 10 or later is required (detected $winVer)."
        Write-Host '       Please upgrade Windows and re-run this script.' -ForegroundColor Yellow
        exit 1
    }
    Write-Ok "Windows $winVer"

    # PowerShell version (already enforced by #Requires, but give a friendly message)
    $psVer = $PSVersionTable.PSVersion
    if ($psVer.Major -lt 5 -or ($psVer.Major -eq 5 -and $psVer.Minor -lt 1)) {
        Write-Fail "PowerShell 5.1 or later is required (detected $psVer)."
        Write-Host '       Download: https://aka.ms/wmf51' -ForegroundColor Yellow
        exit 1
    }
    Write-Ok "PowerShell $psVer"

    # .NET runtime
    $dotnetVer = $null
    try {
        $dotnetVer = [System.Runtime.InteropServices.RuntimeEnvironment]::GetSystemVersion()
    }
    catch {
        $dotnetVer = 'unknown'
    }
    Write-Ok ".NET runtime $dotnetVer"

    Write-Ok 'All prerequisites satisfied'
}

# ---------------------------------------------------------------------------
# Uninstall
# ---------------------------------------------------------------------------

function Invoke-Uninstall {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    Write-Header 'Uninstalling AnimatedDesktop'

    $shortcut = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\AnimatedDesktop.lnk"

    if (Test-Path $InstallDir) {
        if ($PSCmdlet.ShouldProcess($InstallDir, 'Remove installation directory')) {
            Remove-Item -Recurse -Force $InstallDir
        }
        Write-Ok "Removed $InstallDir"
    }
    else {
        Write-Warn "$InstallDir not found -- nothing to remove"
    }

    if (Test-Path $shortcut) {
        if ($PSCmdlet.ShouldProcess($shortcut, 'Remove Start-Menu shortcut')) {
            Remove-Item -Force $shortcut
        }
        Write-Ok 'Removed Start-Menu shortcut'
    }

    Write-Host ''
    Write-Host '  AnimatedDesktop has been uninstalled.' -ForegroundColor Cyan
}

# ---------------------------------------------------------------------------
# Download & verify
# ---------------------------------------------------------------------------

function Get-LatestRelease {
    <#
    .SYNOPSIS
    Returns release metadata from the GitHub API.
    Returns $null when no release is found.
    #>
    $apiUrl = 'https://api.github.com/repos/Marlex49574/AnimatedDesktop/releases/latest'
    try {
        $headers = @{ 'User-Agent' = 'AnimatedDesktop-Installer/1.0' }
        $release = Invoke-RestMethod -Uri $apiUrl -Headers $headers -UseBasicParsing
    }
    catch {
        return $null
    }

    # Prefer a .zip asset; fall back to the first asset available
    $asset = $release.assets | Where-Object { $_.name -like '*.zip' } | Select-Object -First 1
    if (-not $asset) {
        $asset = $release.assets | Select-Object -First 1
    }
    if (-not $asset) {
        return $null
    }

    # Look for a companion SHA-256 checksum file (e.g. AnimatedDesktop.zip.sha256)
    $checksumAsset = $release.assets |
        Where-Object { $_.name -like "$($asset.name).sha256" } |
        Select-Object -First 1

    $checksum = ''
    if ($checksumAsset) {
        try {
            $checksum = (Invoke-RestMethod -Uri $checksumAsset.browser_download_url `
                -Headers $headers -UseBasicParsing).Trim()
        }
        catch {
            $checksum = ''
        }
    }

    return [PSCustomObject]@{
        DownloadUrl = $asset.browser_download_url
        Version     = $release.tag_name
        Checksum    = $checksum
    }
}

function Invoke-Download {
    param(
        [string] $Url,
        [string] $Destination
    )
    Write-Host "     -> $Url" -ForegroundColor DarkGray
    try {
        Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
    }
    catch {
        Write-Fail "Download failed: $_"
        exit 1
    }
}

function Test-Checksum {
    param(
        [string] $FilePath,
        [string] $ExpectedHash
    )
    if ([string]::IsNullOrWhiteSpace($ExpectedHash)) {
        Write-Warn 'No checksum published -- skipping verification'
        return
    }
    $actual   = (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash.ToUpper()
    $expected = $ExpectedHash.ToUpper()
    if ($actual -ne $expected) {
        Write-Fail 'SHA-256 mismatch!'
        Write-Host "     expected : $expected" -ForegroundColor Yellow
        Write-Host "     actual   : $actual"   -ForegroundColor Yellow
        Remove-Item -Force $FilePath -ErrorAction SilentlyContinue
        exit 1
    }
    Write-Ok 'SHA-256 checksum verified'
}

# ---------------------------------------------------------------------------
# Install from release
# ---------------------------------------------------------------------------

function Install-FromRelease {
    param($Release)

    Write-Header "Installing AnimatedDesktop $($Release.Version)"

    $tmpDir  = Join-Path ([System.IO.Path]::GetTempPath()) "AnimatedDesktop-install-$PID"
    $tmpFile = Join-Path $tmpDir (Split-Path $Release.DownloadUrl -Leaf)

    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null

    try {
        Write-Host '  Downloading release asset...' -NoNewline
        Invoke-Download -Url $Release.DownloadUrl -Destination $tmpFile
        Write-Host ' done.' -ForegroundColor Green

        Test-Checksum -FilePath $tmpFile -ExpectedHash $Release.Checksum

        # Prepare install directory (idempotent: wipe old files, keep config)
        if (Test-Path $InstallDir) {
            Write-Warn "Existing installation found at $InstallDir -- updating..."
            Get-ChildItem $InstallDir -Exclude 'config' |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }
        else {
            New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
        }

        if ($tmpFile -like '*.zip') {
            Write-Host '  Extracting...' -NoNewline
            Expand-Archive -Path $tmpFile -DestinationPath $InstallDir -Force
            Write-Host ' done.' -ForegroundColor Green
        }
        else {
            Copy-Item -Path $tmpFile -Destination $InstallDir -Force
            Write-Ok "Copied to $InstallDir"
        }
    }
    finally {
        Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
# Install from source
# ---------------------------------------------------------------------------

function Install-FromSource {
    Write-Header 'No release found -- installing from source'

    if (-not (Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }

    # When run from a local clone, $PSScriptRoot points to the repo directory
    $localScript = if ($PSScriptRoot) { Join-Path $PSScriptRoot 'AnimatedDesktop.ps1' } else { $null }

    if ($localScript -and (Test-Path $localScript)) {
        Copy-Item -Path $localScript -Destination $InstallDir -Force
        Write-Ok 'AnimatedDesktop.ps1 copied from local source'
    }
    else {
        # Running via one-liner (irm | iex) -- download directly from raw GitHub
        $rawUrl  = 'https://raw.githubusercontent.com/Marlex49574/AnimatedDesktop/main/AnimatedDesktop.ps1'
        $destPs1 = Join-Path $InstallDir 'AnimatedDesktop.ps1'
        Write-Host '  Downloading AnimatedDesktop.ps1...' -NoNewline
        Invoke-Download -Url $rawUrl -Destination $destPs1
        Write-Host ' done.' -ForegroundColor Green
        Write-Ok "AnimatedDesktop.ps1 downloaded to $InstallDir"
    }
}

# ---------------------------------------------------------------------------
# Start-Menu shortcut
# ---------------------------------------------------------------------------

function New-StartMenuShortcut {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $ScriptPath)

    if (-not (Test-Path $ScriptPath)) {
        Write-Warn "Script not found at $ScriptPath -- shortcut skipped"
        return
    }

    $shortcutDir  = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs"
    $shortcutPath = Join-Path $shortcutDir 'AnimatedDesktop.lnk'
    $psExe        = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

    if ($PSCmdlet.ShouldProcess($shortcutPath, 'Create Start-Menu shortcut')) {
        $wsh  = New-Object -ComObject WScript.Shell
        $link = $wsh.CreateShortcut($shortcutPath)
        $link.TargetPath       = $psExe
        # -WindowStyle Hidden suppresses the console; the WinForms window provides the UI
        $link.Arguments        = "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`""
        $link.WorkingDirectory = $InstallDir
        $link.Description      = 'AnimatedDesktop -- animated wallpaper engine'
        $link.Save()
    }

    Write-Ok 'Start-Menu shortcut created'
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

Write-Host ''
Write-Host '  +---------------------------------------+' -ForegroundColor Cyan
Write-Host '  |     AnimatedDesktop  Installer        |' -ForegroundColor Cyan
Write-Host '  +---------------------------------------+' -ForegroundColor Cyan

if ($Uninstall) {
    Invoke-Uninstall
    exit 0
}

Test-Prerequisite

$scriptPath = Join-Path $InstallDir 'AnimatedDesktop.ps1'

# Try GitHub releases first; fall back to source install
$release = Get-LatestRelease
if ($release) {
    Install-FromRelease -Release $release
}
else {
    Write-Warn 'No published release found -- falling back to source install'
    Install-FromSource
}

New-StartMenuShortcut -ScriptPath $scriptPath

# Record the installed version
$versionFile = Join-Path $InstallDir 'VERSION.txt'
if ($release) {
    Set-Content -Path $versionFile -Value $release.Version
}
else {
    Set-Content -Path $versionFile -Value 'source'
}

Write-Host ''
Write-Host '  [OK]  AnimatedDesktop installed successfully!' -ForegroundColor Green
Write-Host "        Location : $InstallDir" -ForegroundColor Gray
Write-Host "        Launch   : Start Menu -> AnimatedDesktop" -ForegroundColor Gray
Write-Host "                   or: powershell.exe -ExecutionPolicy Bypass -File `"$scriptPath`"" -ForegroundColor Gray
Write-Host ''
