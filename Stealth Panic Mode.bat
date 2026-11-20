@echo off
setlocal DisableDelayedExpansion
rem Run the embedded script through -File so PowerShell binds native arguments.
set "WINDOW_TWEAKS_BATCH=%~f0"
set "WINDOW_TWEAKS_RUN=%TEMP%\WindowTweaks-%RANDOM%-%RANDOM%"
set "WINDOW_TWEAKS_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
md "%WINDOW_TWEAKS_RUN%" 2>nul
if errorlevel 1 (
    >&2 echo Could not create a temporary script directory.
    exit /b 1
)

"%WINDOW_TWEAKS_PS%" -NoProfile -Command "$ErrorActionPreference = 'Stop'; $text = [IO.File]::ReadAllText($env:WINDOW_TWEAKS_BATCH); $marker = [regex]::Match($text, '(?m)^# POWERSHELL SCRIPT\r?\n'); if (-not $marker.Success) { throw 'Missing embedded script.' }; $code = $text.Substring($marker.Index + $marker.Length); [IO.File]::WriteAllText((Join-Path $env:WINDOW_TWEAKS_RUN 'entry.ps1'), $code, [Text.Encoding]::Unicode)"
set "WINDOW_TWEAKS_STATUS=%errorlevel%"
if not "%WINDOW_TWEAKS_STATUS%"=="0" goto cleanup

"%WINDOW_TWEAKS_PS%" -NoProfile -ExecutionPolicy Bypass -File "%WINDOW_TWEAKS_RUN%\entry.ps1" %*
set "WINDOW_TWEAKS_STATUS=%errorlevel%"

:cleanup
del /q "%WINDOW_TWEAKS_RUN%\entry.ps1" 2>nul
rd "%WINDOW_TWEAKS_RUN%" 2>nul
exit /b %WINDOW_TWEAKS_STATUS%

# POWERSHELL SCRIPT
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
function Step($n, $m) { Write-Host "`n[$n/5] $m" -ForegroundColor Cyan }

Write-Host ""
Write-Host "  ===========================================" -ForegroundColor Cyan
Write-Host "   Stealth Panic Mode - Setup" -ForegroundColor Cyan
Write-Host "  ===========================================" -ForegroundColor Cyan

$repo      = ([IO.Path]::GetDirectoryName($env:WINDOW_TWEAKS_BATCH))
$local     = [Environment]::GetFolderPath('LocalApplicationData')
if (-not $local) { throw 'Could not locate Local AppData.' }
$dest      = Join-Path $local 'Stealth Panic Mode'
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
    Say "Not installed." 'Yellow'
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Say "winget isn't available here either." 'Red'
        Say "Install AutoHotkey v2 from https://www.autohotkey.com and re-run this." 'Red'
        exit 1
    }
    Say "Installing it with winget..." 'Yellow'
    winget install --id AutoHotkey.AutoHotkey --source winget `
                   --accept-package-agreements --accept-source-agreements --disable-interactivity
    $ahk = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $ahk) {
        Say "Still not found after installing. Stopping." 'Red'
        exit 1
    }
    Say "Installed $ahk" 'Green'
}

# ------------------------------------------------------ 2. stop old copy ----
Step 2 "Stopping any running copy"
$stopped = 0
$procs = @(Get-CimInstance Win32_Process -Filter "Name like 'AutoHotkey%'" -ErrorAction SilentlyContinue |
           Where-Object { $_.CommandLine -like '*Stealth Panic Mode.ahk*' -or $_.CommandLine -like '*StealthPanicUI.ahk*' })
foreach ($p in $procs) {
    $ErrorActionPreference = 'Continue'
    & taskkill.exe /PID $p.ProcessId 2>&1 | Out-Null
    $ErrorActionPreference = 'Stop'
    $stopped++
}
foreach ($p in $procs) {
    try { Wait-Process -Id $p.ProcessId -Timeout 5 -ErrorAction Stop } catch {}
    if (Get-Process -Id $p.ProcessId -ErrorAction SilentlyContinue) {
        Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
    }
}
Say $(if ($stopped) { "Stopped $stopped" } else { "Nothing was running" })

# ------------------------------------------------- 3. Copy Files ----
Step 3 "Copying engine"
if (-not (Test-Path $dest)) {
    New-Item -Path $dest -ItemType Directory -Force | Out-Null
}

Copy-Item "$repo\src\StealthPanic.ahk" $dest -Force
Copy-Item "$repo\src\StealthPanicUI.ahk" $dest -Force
Copy-Item "$repo\src\StealthPanicConfig.ahk" $dest -Force
Copy-Item -LiteralPath (Join-Path $repo 'Uninstall Stealth Panic Mode.bat') -Destination $dest -Force

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

# ------------------------------------------------- 4. Shortcuts ----
Step 4 "Creating shortcuts"
$WshShell = New-Object -ComObject WScript.Shell

if (-not $NoAutoStart) {
    $Shortcut = $WshShell.CreateShortcut($startup)
    $Shortcut.TargetPath = $ahk
    $Shortcut.Arguments = "`"$runnerPath`""
    $Shortcut.WorkingDirectory = $dest
    $Shortcut.Save()
    Say "Added to Startup" 'Green'
} else {
    if (Test-Path $startup) { Remove-Item $startup -Force -ErrorAction SilentlyContinue }
    Say "Autostart skipped" 'DarkGray'
}

$Shortcut = $WshShell.CreateShortcut($startMenu)
$Shortcut.TargetPath = $ahk
$Shortcut.Arguments = "`"$runnerPath`""
$Shortcut.WorkingDirectory = $dest
$Shortcut.Save()

# Named "(Standalone)" so it cannot overwrite the shortcut Install.bat creates.
# Both used to be called 'Stealth Panic Mode Settings.lnk', so installing both
# products left exactly one shortcut pointing at whichever folder was installed
# last - and it then edited an ini the other install's engine never reads.
# The ini path is passed explicitly for the same reason.
$uiShortcut = $WshShell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Programs')) 'Stealth Panic Mode Settings (Standalone).lnk'))
$uiShortcut.TargetPath = $ahk
$uiShortcut.Arguments = "`"$dest\StealthPanicUI.ahk`" `"$dest\StealthPanic.ini`""
$uiShortcut.WorkingDirectory = $dest
$uiShortcut.Save()

# No "Uninstall" Start Menu shortcut. It was a .lnk launching
# powershell.exe -ExecutionPolicy Bypass, a shape endpoint security flags on
# sight. Uninstall by running the script in the install folder instead; an old
# shortcut from a previous install is removed here.
$oldUninstallLnk = Join-Path ([Environment]::GetFolderPath('Programs')) 'Uninstall Stealth Panic Mode.lnk'
if (Test-Path $oldUninstallLnk) { Remove-Item $oldUninstallLnk -Force -ErrorAction SilentlyContinue }
Say "Added to Start Menu" 'Green'
Say "To uninstall: run '$dest\Uninstall Stealth Panic Mode.bat'" 'DarkGray'

# ------------------------------------------------- 5. Start ----
Step 5 "Starting Stealth Panic Mode"

Start-Process -FilePath $ahk -ArgumentList "`"$runnerPath`"" -WorkingDirectory $dest
Say "Running!" 'Green'

Write-Host "`nSetup complete!" -ForegroundColor Cyan
