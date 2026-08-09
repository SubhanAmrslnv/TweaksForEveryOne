<#
.SYNOPSIS
    Installs Stealth Panic Mode (Standalone).

.DESCRIPTION
    Copies the engine to %LOCALAPPDATA%\Stealth Panic Mode, creates a Startup shortcut,
    and starts it. Does not install Window Tweaks.
#>
[CmdletBinding()]
param(
    [switch]$Silent,
    [switch]$NoAutoStart
)

$ErrorActionPreference = 'Stop'

function Say ($m, $c = 'Gray') { Write-Host "  $m" -ForegroundColor $c }
function Step($n, $m) { Write-Host "`n[$n/4] $m" -ForegroundColor Cyan }

Write-Host ""
Write-Host "  ===========================================" -ForegroundColor Cyan
Write-Host "   Stealth Panic Mode - Setup" -ForegroundColor Cyan
Write-Host "  ===========================================" -ForegroundColor Cyan

$repo      = $PSScriptRoot
$dest      = Join-Path $env:LOCALAPPDATA 'Stealth Panic Mode'
$startup   = Join-Path ([Environment]::GetFolderPath('Startup'))  'Stealth Panic Mode.lnk'
$startMenu = Join-Path ([Environment]::GetFolderPath('Programs')) 'Stealth Panic Mode.lnk'

# --------------------------------------------------------- 1. AutoHotkey ----
Step 1 "Checking for AutoHotkey v2"
$candidates = @(
    "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe",
    "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe",
    "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey32.exe",
    "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey32.exe"
)
$ahk = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($ahk) {
    Say "Found $ahk" 'Green'
} else {
    Say "Not installed. Installing it with winget..." 'Yellow'
    winget install --id AutoHotkey.AutoHotkey --source winget `
                   --accept-package-agreements --accept-source-agreements --disable-interactivity
    $ahk = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $ahk) {
        Say "Still not found after installing. Stopping." 'Red'
        return
    }
    Say "Installed $ahk" 'Green'
}

# ------------------------------------------------- 2. Copy Files ----
Step 2 "Copying engine"
if (-not (Test-Path $dest)) {
    New-Item -Path $dest -ItemType Directory -Force | Out-Null
}

Copy-Item "$repo\src\StealthPanic.ahk" $dest -Force
Copy-Item "$repo\src\StealthPanicUI.ahk" $dest -Force
Copy-Item "$repo\src\StealthPanicConfig.ahk" $dest -Force
if (Test-Path "$repo\Uninstall Stealth Panic Mode.ps1") {
    Copy-Item "$repo\Uninstall Stealth Panic Mode.ps1" $dest -Force
}

# Create a runner script for standalone mode
$runnerPath = "$dest\Stealth Panic Mode.ahk"
@"
#Requires AutoHotkey v2.0
Persistent
#Include StealthPanic.ahk

A_TrayMenu.Delete()
A_TrayMenu.Add("Settings", ShowStealthSettings)
A_TrayMenu.Add("Exit", ExitStealthApp)

ExitStealthApp(ItemName, ItemPos, MyMenu) {
    ExitApp()
}

ShowStealthSettings(ItemName, ItemPos, MyMenu) {
    ; Launched through the interpreter explicitly. Running a .ahk directly goes
    ; via the file association, which drops the argument - and the argument is
    ; what tells the GUI which ini this engine is actually using.
    try Run('"' A_AhkPath '" "' A_ScriptDir '\StealthPanicUI.ahk" "' StealthPanicIniPath '"')
}

TraySetIcon("shell32.dll", 48)
"@ | Out-File $runnerPath -Encoding utf8

Say "Copied to $dest" 'Green'

# ------------------------------------------------- 3. Shortcuts ----
Step 3 "Creating shortcuts"
$WshShell = New-Object -ComObject WScript.Shell

if (-not $NoAutoStart) {
    $Shortcut = $WshShell.CreateShortcut($startup)
    $Shortcut.TargetPath = $ahk
    $Shortcut.Arguments = "`"$runnerPath`""
    $Shortcut.WorkingDirectory = $dest
    $Shortcut.Save()
    Say "Added to Startup" 'Green'
}

$Shortcut = $WshShell.CreateShortcut($startMenu)
$Shortcut.TargetPath = $ahk
$Shortcut.Arguments = "`"$runnerPath`""
$Shortcut.WorkingDirectory = $dest
$Shortcut.Save()

# Named "(Standalone)" so it cannot overwrite the shortcut Install.ps1 creates.
# Both used to be called 'Stealth Panic Mode Settings.lnk', so installing both
# products left exactly one shortcut pointing at whichever folder was installed
# last - and it then edited an ini the other install's engine never reads.
# The ini path is passed explicitly for the same reason.
$uiShortcut = $WshShell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Programs')) 'Stealth Panic Mode Settings (Standalone).lnk'))
$uiShortcut.TargetPath = $ahk
$uiShortcut.Arguments = "`"$dest\StealthPanicUI.ahk`" `"$dest\StealthPanic.ini`""
$uiShortcut.WorkingDirectory = $dest
$uiShortcut.Save()

$uninstallShortcut = $WshShell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Programs')) 'Uninstall Stealth Panic Mode.lnk'))
$uninstallShortcut.TargetPath = "powershell.exe"
$uninstallShortcut.Arguments = "-ExecutionPolicy Bypass -File `"$dest\Uninstall Stealth Panic Mode.ps1`""
$uninstallShortcut.WorkingDirectory = $dest
$uninstallShortcut.Save()
Say "Added to Start Menu" 'Green'

# ------------------------------------------------- 4. Start ----
Step 4 "Starting Stealth Panic Mode"

$existing = Get-Process AutoHotkey64, AutoHotkey32, AutoHotkey -ErrorAction SilentlyContinue | Where-Object {
    $_.MainWindowTitle -match 'Stealth Panic Mode.ahk'
}
if ($existing) {
    Say "Stopping existing instance..." 'Yellow'
    $existing | Stop-Process -Force
    Start-Sleep -Seconds 1
}

Start-Process -FilePath $ahk -ArgumentList "`"$runnerPath`"" -WorkingDirectory $dest
Say "Running!" 'Green'

Write-Host "`nSetup complete!" -ForegroundColor Cyan
