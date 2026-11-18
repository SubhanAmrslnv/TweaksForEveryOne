<#
.SYNOPSIS
    Installs Window Tweaks.

.DESCRIPTION
    Copies the program to %LOCALAPPDATA%\Window Tweaks, creates Start Menu,
    Desktop and Startup shortcuts, and starts it.

    No admin rights. No registry keys for the program itself. Nothing outside
    your user profile. Uninstall.ps1 removes all of it.

    Network access: winget, only if AutoHotkey v2 is missing. See
    docs\SECURITY.md for everything the program touches.

.PARAMETER Silent
    Skip every prompt and take the defaults: install + autostart, no Windows
    tuning, no Explorer restart.

.PARAMETER NoAutoStart
    Don't run at login.

.PARAMETER Tuning
    Also apply the Windows animation and Explorer tuning (scripts\).
#>
[CmdletBinding()]
param(
    [switch]$Silent,
    [switch]$NoAutoStart,
    [switch]$Tuning
)

$ErrorActionPreference = 'Stop'

function Say ($m, $c = 'Gray') { Write-Host "  $m" -ForegroundColor $c }
function Step($n, $m) { Write-Host "`n[$n/6] $m" -ForegroundColor Cyan }

Write-Host ""
Write-Host "  ===========================================" -ForegroundColor Cyan
Write-Host "   Window Tweaks - Setup" -ForegroundColor Cyan
Write-Host "  ===========================================" -ForegroundColor Cyan

$repo      = $PSScriptRoot
$dest      = Join-Path $env:LOCALAPPDATA 'Window Tweaks'
$startup   = Join-Path ([Environment]::GetFolderPath('Startup'))  'Window Tweaks.lnk'
$startMenu = Join-Path ([Environment]::GetFolderPath('Programs')) 'Window Tweaks.lnk'
$desktop   = Join-Path ([Environment]::GetFolderPath('Desktop'))  'Window Tweaks.lnk'

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
        return
    }
    Say "Installing it with winget..." 'Yellow'
    winget install --id AutoHotkey.AutoHotkey --source winget `
                   --accept-package-agreements --accept-source-agreements --disable-interactivity
    $ahk = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $ahk) {
        Say "Still not found after installing. Stopping." 'Red'
        return
    }
    Say "Installed $ahk" 'Green'
}

# ------------------------------------------------------ 2. stop old copy ----
Step 2 "Stopping any running copy"
# Ask first, force only as a fallback. A forced kill skips the program's exit
# handler, which is what writes pending settings and hands back every window it
# changed (ghosted, rolled-up, hidden to tray) - an upgrade
# over a running copy used to strand those. taskkill without /F posts WM_CLOSE.
$stopped = 0
$procs = @(Get-CimInstance Win32_Process -Filter "Name like 'AutoHotkey%'" -ErrorAction SilentlyContinue |
           Where-Object { $_.CommandLine -like '*WindowTweaks.ahk*' -or $_.CommandLine -like '*StealthPanicUI.ahk*' })
foreach ($p in $procs) {
    # 'Continue' locally: under 'Stop', Windows PowerShell 5.1 turns a native
    # command's redirected stderr into a terminating error.
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

# ------------------------------------------------------------- 3. files ----
Step 3 "Installing to $dest"
New-Item -ItemType Directory -Path $dest -Force | Out-Null

# The program is installed flat: WindowTweaks.ahk includes SnapCore.ahk
# from its own folder, and its Guide button opens GUIDE.md from there too.
#
# Every .ahk in src\ is copied, discovered rather than listed. A missing include
# target is a LOAD-time error, so a module left out of a hardcoded list installed
# an app that could not start - and running from src\ never showed it, because
# the file was there. Keep this in step with build\Build-Installer.ps1, which
# discovers the same set. test_*.ahk are standalone harnesses, not the program.
$copied = 0
$ahkFiles = Get-ChildItem (Join-Path $repo 'src') -Filter '*.ahk' -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notlike 'test_*' } |
            Sort-Object Name
if (-not ($ahkFiles.Name -contains 'WindowTweaks.ahk')) {
    Say "MISSING: src\WindowTweaks.ahk (the entry point)" 'Red'; return
}
foreach ($f in $ahkFiles) {
    Copy-Item $f.FullName (Join-Path $dest $f.Name) -Force
    $copied++
}
foreach ($f in 'GUIDE.md', 'HOTKEYS.md', 'ANIMATIONS.md', 'TASKBAR-AND-INTERNALS.md', 'WINDOWS-TUNING.md', 'SECURITY.md') {
    $p = Join-Path $repo "docs\$f"
    if (Test-Path $p) { Copy-Item $p (Join-Path $dest $f) -Force; $copied++ }
}
$icoPathSrc = Join-Path $repo 'assets\WindowTweaks.ico'
if (Test-Path $icoPathSrc) { Copy-Item $icoPathSrc (Join-Path $dest 'WindowTweaks.ico') -Force; $copied++ }
New-Item -ItemType Directory -Path (Join-Path $dest 'scripts') -Force | Out-Null
foreach ($f in 'Apply-Windows-Tuning.ps1', 'Restore-Windows-Tuning.ps1') {
    $p = Join-Path $repo "scripts\$f"
    if (Test-Path $p) { Copy-Item $p (Join-Path $dest "scripts\$f") -Force; $copied++ }
}
$un = Join-Path $repo 'Uninstall.ps1'
if (Test-Path $un) { Copy-Item $un (Join-Path $dest 'Uninstall.ps1') -Force; $copied++ }
Say "Copied $copied files" 'Green'

# Settings precedence, the same rule as build\Setup.cs:
#   1. an existing settings.ini is the user's and is NEVER touched - an update
#      keeps every value, and keys added since are filled in by LoadSettings()
#   2. otherwise the packaged baseline (build\baseline-settings.ini) seeds it
#   3. otherwise the program writes its own factory defaults on first run
# Copy-if-absent is idempotent: running the installer again changes nothing.
$userIni     = Join-Path $dest 'settings.ini'
$baselineIni = Join-Path $repo 'build\baseline-settings.ini'
if (Test-Path $userIni) {
    Say "Kept your existing settings.ini" 'Green'
} elseif (Test-Path $baselineIni) {
    Copy-Item $baselineIni $userIni
    Say "Applied the packaged baseline settings" 'Green'
} else {
    Say "No baseline found - the program will write its defaults on first run" 'DarkGray'
}

# --------------------------------------------------------- 4. shortcuts ----
Step 4 "Creating shortcuts"
$WshShell = New-Object -ComObject WScript.Shell
$icoPathDest = Join-Path $dest 'WindowTweaks.ico'

$Shortcut = $WshShell.CreateShortcut($startMenu)
$Shortcut.TargetPath = $ahk
$Shortcut.Arguments = "`"$dest\WindowTweaks.ahk`""
$Shortcut.WorkingDirectory = $dest
if (Test-Path $icoPathDest) { $Shortcut.IconLocation = $icoPathDest }
$Shortcut.Save()

# The settings GUI is a separate process, so it is told which StealthPanic.ini
# to edit rather than deriving one from its own folder. Without this it would
# guess from A_ScriptDir, and a machine that also has the standalone install
# ends up with the GUI editing one folder's config while the engine reads
# another's - settings that appear to save and then have no effect.
$uiShortcut = $WshShell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Programs')) 'Stealth Panic Mode Settings.lnk'))
$uiShortcut.TargetPath = $ahk
$uiShortcut.Arguments = "`"$dest\StealthPanicUI.ahk`" `"$dest\StealthPanic.ini`""
$uiShortcut.WorkingDirectory = $dest
$uiShortcut.Save()

Say "Added to Start Menu" 'Green'

function New-Link ($path) {
    $s = $WshShell.CreateShortcut($path)
    $s.TargetPath       = $ahk
    $s.Arguments        = '"' + (Join-Path $dest 'WindowTweaks.ahk') + '"'
    $s.WorkingDirectory = $dest
    $s.Description      = 'Window Tweaks'
    if (Test-Path $icoPathDest) { $s.IconLocation = "$icoPathDest,0" }
    $s.Save()
}
New-Link $desktop   ; Say "Desktop" 'Green'

$auto = -not $NoAutoStart
if ($auto) { New-Link $startup ; Say "Startup - runs at login" 'Green' }
else       { if (Test-Path $startup) { Remove-Item $startup -Force }; Say "Autostart skipped" 'DarkGray' }

# ----------------------------------------------------------- 5. Windows ----
Step 5 "Windows settings"

# No runtime-compiled C# here any more. The only thing this step must guarantee
# is DragFullWindows=1, and the program itself applies that live at startup
# (CheckDragFullWindows -> SPI_SETDRAGFULLWINDOWS), so the registry value is
# all the installer needs to write.
$drag = (Get-ItemProperty 'HKCU:\Control Panel\Desktop' -ErrorAction SilentlyContinue).DragFullWindows

# -Tuning: apply without asking. -Silent alone: no tuning (as documented).
# Interactive: ask, default yes.
$applyVisualEffects = [bool]$Tuning
if (-not $Tuning -and -not $Silent) {
    if ("$drag" -ne '1') {
        Say "'Show window contents while dragging' is OFF - the ice glide needs it." 'Yellow'
    } else {
        Say "'Show window contents while dragging' is on - the required setting is fine" 'Green'
    }
    Say "Window Tweaks can apply the recommended Visual Effects settings for you." 'Cyan'
    $answer = Read-Host "  Apply the recommended Windows Visual Effects? (Y/n)"
    $applyVisualEffects = -not ($answer -match '^[Nn]')
}

if ($applyVisualEffects) {
    Say "Applying Windows Visual Effects tuning..." 'Cyan'
    & (Join-Path $dest 'scripts\Apply-Windows-Tuning.ps1') -Animations
} elseif ("$drag" -ne '1') {
    # Never leave the program in a state where its headline feature is invisible.
    $dragBackupDir = Join-Path $env:LOCALAPPDATA 'Window Tweaks Backup'
    if (-not (Test-Path $dragBackupDir)) { New-Item -ItemType Directory -Path $dragBackupDir -Force | Out-Null }
    $dragBackupFile = Join-Path $dragBackupDir 'drag-backup.txt'
    if (-not (Test-Path $dragBackupFile)) {
        if ($null -eq $drag -or "$drag" -eq "") { Set-Content $dragBackupFile 'absent' } else { Set-Content $dragBackupFile $drag }
    }
    Set-ItemProperty 'HKCU:\Control Panel\Desktop' 'DragFullWindows' '1' -Type String
    Say "Turned on 'Show window contents while dragging' (required) - nothing else changed" 'Yellow'
} else {
    Say "Skipped Windows Visual Effects tuning." 'DarkGray'
}

$applyExplorerTuning = [bool]$Tuning
if (-not $Tuning -and -not $Silent) {
    Say "Optional: Faster Explorer (Launch to This PC, run folder windows in a separate process)."
    Say "All HKCU only and fully reversible. See docs\WINDOWS-TUNING.md."
    $answer = Read-Host "  Apply the Explorer tuning as well? (Y/n)"
    $applyExplorerTuning = -not ($answer -match '^[Nn]')
}

if ($applyExplorerTuning) {
    & (Join-Path $dest 'scripts\Apply-Windows-Tuning.ps1') -Explorer
} else {
    Say "Skipped Explorer tuning - run scripts\Apply-Windows-Tuning.ps1 any time" 'DarkGray'
}

# Explorer is restarted only when something that needs it was applied, and never
# without asking in an interactive install. It used to be force-killed on every
# install, and nothing relaunched it if Windows did not.
if ($applyExplorerTuning) {
    $restart = $Silent
    if (-not $Silent) {
        $answer = Read-Host "  Restart Explorer now so the changes take effect? (Y/n)"
        $restart = -not ($answer -match '^[Nn]')
    }
    if ($restart) {
        Say "Restarting Explorer..." 'Yellow'
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
        if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
    } else {
        Say "Explorer not restarted - the changes apply at next sign-in." 'DarkGray'
    }
}

# ------------------------------------------------------------ 6. launch ----
Step 6 "Starting Window Tweaks"
Start-Process -FilePath $ahk -ArgumentList ('"' + (Join-Path $dest 'WindowTweaks.ahk') + '"') -WorkingDirectory $dest
Start-Sleep -Seconds 2
$running = Get-CimInstance Win32_Process -Filter "Name like 'AutoHotkey%'" -ErrorAction SilentlyContinue |
           Where-Object { $_.CommandLine -like '*WindowTweaks.ahk*' }
if ($running) { Say "Running - look for the tray icon" 'Green' }
else          { Say "It didn't start. Run '$dest\WindowTweaks.ahk' by hand to see the error." 'Red' }

Write-Host ""
Write-Host "  ===========================================" -ForegroundColor Green
Write-Host "   Done" -ForegroundColor Green
Write-Host "  ===========================================" -ForegroundColor Green
Write-Host @"

   Shift + Alt + W    settings
   Shift + Alt + O    always on top
   Shift + Alt + S    magnetic snapping on/off

   Installed to  $dest
   Guide         $dest\GUIDE.md
   Remove        $dest\Uninstall.ps1

"@ -ForegroundColor Gray
