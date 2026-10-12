<#
.SYNOPSIS
    Installs Window Tweaks.

.DESCRIPTION
    Copies the program to %LOCALAPPDATA%\Window Tweaks, creates Start Menu,
    Desktop and Startup shortcuts, and starts it.

    No admin rights. No registry keys for the program itself. Nothing outside
    your user profile. Uninstall.ps1 removes all of it. The one exception is
    the optional ExplorerPatcher step (-ExplorerPatcher), which is a third-party
    shell extension: its own setup asks for administrator rights (UAC) and puts
    files under C:\Windows. It is never installed unless you ask for it.

    Network access: winget, only if AutoHotkey v2 is missing; GitHub, only with
    -ExplorerPatcher. See docs\SECURITY.md for everything the program touches.

.PARAMETER Silent
    Skip every prompt and take the defaults: install + autostart, no Windows
    tuning, no ExplorerPatcher, no Explorer restart.

.PARAMETER NoAutoStart
    Don't run at login.

.PARAMETER Tuning
    Also apply the Windows animation and Explorer tuning (scripts\).

.PARAMETER ExplorerPatcher
    Also install ExplorerPatcher (pinned release, SHA-256 verified; needs UAC)
    and import PatcherSettings\*.reg. Off by default.
#>
[CmdletBinding()]
param(
    [switch]$Silent,
    [switch]$NoAutoStart,
    [switch]$Tuning,
    [switch]$ExplorerPatcher
)

$ErrorActionPreference = 'Stop'

function Say ($m, $c = 'Gray') { Write-Host "  $m" -ForegroundColor $c }
function Step($n, $m) { Write-Host "`n[$n/7] $m" -ForegroundColor Cyan }

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

# ------------------------------------------------- 2. ExplorerPatcher ----
Step 2 "Checking for ExplorerPatcher"
$epInstalled = Test-Path "C:\Windows\dxgi.dll"
if (-not $epInstalled) {
    $epInstalled = Test-Path "C:\Windows\SystemApps\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy\dxgi.dll"
}

# OPT-IN ONLY. ExplorerPatcher is a third-party shell extension that installs
# into C:\Windows and needs UAC - on a managed machine that is IT's decision, not
# a default. It used to be downloaded from "releases/latest" and run silently on
# every install, unverified. Now: only on request, a pinned release, and the
# file's SHA-256 must match before it is executed. To move to a newer release,
# update both constants from the release's asset "digest" on the GitHub API.
$EP_TAG    = '26100.8457.70.3'
$EP_SHA256 = '8146db4d3a87201fb80ad1d3712ba8f56883e9a0811758bd39f62d73a9f2c586'
$EP_URL    = "https://github.com/valinet/ExplorerPatcher/releases/download/$EP_TAG/ep_setup.exe"

$wantEP = [bool]$ExplorerPatcher
if (-not $wantEP -and -not $Silent) {
    Say "ExplorerPatcher (optional, third-party) enables the Win10 taskbar style and" 'Gray'
    Say "small-icon options. It needs administrator rights and may be blocked by" 'Gray'
    Say "company policy. Window Tweaks works fully without it." 'Gray'
    $answer = Read-Host "  Install ExplorerPatcher $EP_TAG and apply its settings? (y/N)"
    $wantEP = ($answer -match '^[Yy]')
}

$epApplied = $false
if ($epInstalled) {
    Say "ExplorerPatcher is already installed." 'Green'
} elseif (-not $wantEP) {
    Say "Skipped (optional). Re-run with -ExplorerPatcher to add it." 'DarkGray'
} else {
    $epSetup = Join-Path $env:TEMP "ep_setup_$EP_TAG.exe"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Say "Downloading ExplorerPatcher $EP_TAG from GitHub..." 'DarkGray'
        Invoke-WebRequest -Uri $EP_URL -OutFile $epSetup -UseBasicParsing -ErrorAction Stop
        $hash = (Get-FileHash -Path $epSetup -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($hash -ne $EP_SHA256) {
            Say "SHA-256 mismatch - refusing to run it." 'Red'
            Say "  expected $EP_SHA256" 'Red'
            Say "  got      $hash" 'Red'
        } else {
            Say "Checksum verified. Installing (accept the UAC prompt)..." 'Yellow'
            $proc = Start-Process -FilePath $epSetup -Wait -PassThru
            if ($proc.ExitCode -eq 0) {
                Say "ExplorerPatcher installed." 'Green'
                $epInstalled = $true
            } else {
                Say "ExplorerPatcher setup failed or was cancelled (exit $($proc.ExitCode))." 'Red'
            }
        }
    } catch {
        Say "Could not install ExplorerPatcher: $_" 'Red'
    } finally {
        Remove-Item $epSetup -Force -ErrorAction SilentlyContinue
    }
}

# ------------------------------------------------- 2.5 ExplorerPatcher Settings ----
Step 2.5 "ExplorerPatcher settings"
# Only together with an explicit ExplorerPatcher opt-in. The .reg is trimmed to
# ExplorerPatcher's own keys (see its header) and imported visibly.
$regFile = Get-ChildItem -Path "$repo\PatcherSettings\ExplorerPatcher*.reg" -ErrorAction SilentlyContinue |
           Select-Object -First 1
if (-not $wantEP) {
    Say "Skipped (ExplorerPatcher not requested)." 'DarkGray'
} elseif (-not $epInstalled) {
    Say "Skipped (ExplorerPatcher is not installed)." 'DarkGray'
} elseif (-not $regFile) {
    Say "No PatcherSettings\ExplorerPatcher*.reg found, skipping." 'DarkGray'
} else {
    Say "Importing $($regFile.Name) (HKCU only)..." 'Yellow'
    $ErrorActionPreference = 'Continue'     # reg.exe reports success on stderr
    & reg.exe import "$($regFile.FullName)" 2>&1 | ForEach-Object { Say "$_" 'DarkGray' }
    $ErrorActionPreference = 'Stop'
    if ($LASTEXITCODE -eq 0) { Say "Settings applied." 'Green'; $epApplied = $true }
    else                     { Say "Failed to apply settings (reg.exe exit $LASTEXITCODE)." 'Red' }
}

# ------------------------------------------------------ 3. stop old copy ----
Step 3 "Stopping any running copy"
# Ask first, force only as a fallback. A forced kill skips the program's exit
# handler, which is what writes pending settings and hands back every window it
# changed (always-on-bottom, ghosted, rolled-up, hidden to tray) - an upgrade
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

# ------------------------------------------------------------- 4. files ----
Step 4 "Installing to $dest"
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

# --------------------------------------------------------- 5. shortcuts ----
Step 5 "Creating shortcuts"
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

# ----------------------------------------------------------- 6. Windows ----
Step 6 "Windows settings"

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
if ($applyExplorerTuning -or $epApplied) {
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

# ------------------------------------------------------------ 7. launch ----
Step 7 "Starting Window Tweaks"
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
