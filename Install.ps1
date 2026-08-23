<#
.SYNOPSIS
    Installs Window Tweaks.

.DESCRIPTION
    Copies the program to %LOCALAPPDATA%\Window Tweaks, creates Start Menu,
    Desktop and Startup shortcuts, and starts it.

    No admin rights. No registry keys for the program itself. Nothing outside
    your user profile. Uninstall.ps1 removes all of it.

.PARAMETER Silent
    Skip every prompt and take the defaults (install + autostart, no tuning).

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

if ($epInstalled) {
    Say "ExplorerPatcher is already installed." 'Green'
} else {
    Say "ExplorerPatcher provides the taskbar style and small-icon options." 'Yellow'
    Say "Installing it automatically..." 'Yellow'
    $doEP = $true
    
    if ($doEP) {
        Say "Fetching latest ExplorerPatcher from GitHub..." 'Yellow'
        try {
            # Use TLS 1.2
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $release = Invoke-RestMethod -Uri "https://api.github.com/repos/valinet/ExplorerPatcher/releases/latest" -ErrorAction Stop
            $asset = $release.assets | Where-Object { $_.name -eq 'ep_setup.exe' }
            if ($asset) {
                $epSetup = Join-Path $env:TEMP 'ep_setup.exe'
                Say "Downloading $($asset.name)..." 'DarkGray'
                Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $epSetup -ErrorAction Stop
                Say "Installing ExplorerPatcher (Please accept the UAC prompt if it appears)..." 'Yellow'
                $proc = Start-Process -FilePath $epSetup -ArgumentList "/quiet" -Wait -PassThru
                if ($proc.ExitCode -eq 0) {
                    Say "ExplorerPatcher installed successfully." 'Green'
                } else {
                    Say "ExplorerPatcher installation failed or was cancelled." 'Red'
                }
            } else {
                Say "Could not find ep_setup.exe in the latest release." 'Red'
            }
        } catch {
            Say "Failed to download ExplorerPatcher: $_" 'Red'
        }
    }
}

# ------------------------------------------------- 2.5 ExplorerPatcher Settings ----
Step 2.5 "Applying ExplorerPatcher Settings"
$regFiles = Get-ChildItem -Path "$repo\PatcherSettings\ExplorerPatcher*.reg" -ErrorAction SilentlyContinue
if ($regFiles) {
    $regFile = $regFiles | Select-Object -First 1
    
    $apply = $true
    if (-not $Silent) {
        $answer = Read-Host "Do you want to apply ExplorerPatcher settings from $($regFile.Name)? (Y/n)"
        if ($answer -eq 'n' -or $answer -eq 'N') {
            $apply = $false
        }
    }

    if ($apply) {
        Say "Applying settings from $($regFile.Name)..." 'Yellow'
        $regProc = Start-Process reg.exe -ArgumentList "import `"$($regFile.FullName)`"" -Wait -WindowStyle Hidden -PassThru
        if ($regProc.ExitCode -eq 0) {
            Say "Settings applied." 'Green'
        } else {
            Say "Failed to apply settings." 'Red'
        }
    } else {
        Say "Skipping ExplorerPatcher settings." 'DarkGray'
    }
} else {
    Say "No PatcherSettings\ExplorerPatcher*.reg found, skipping." 'DarkGray'
}

# ------------------------------------------------------ 3. stop old copy ----
Step 3 "Stopping any running copy"
$stopped = 0
Get-CimInstance Win32_Process -Filter "Name like 'AutoHotkey%'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*WindowTweaks.ahk*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue; $stopped++ }
Say $(if ($stopped) { "Stopped $stopped" } else { "Nothing was running" })
Start-Sleep -Milliseconds 700

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
foreach ($f in 'GUIDE.md', 'HOTKEYS.md', 'ANIMATIONS.md', 'TASKBAR-AND-INTERNALS.md', 'WINDOWS-TUNING.md') {
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

if (-not ('WtSpi' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class WtSpi {
  [DllImport("user32.dll", SetLastError=true)]
  public static extern bool SystemParametersInfo(uint a, uint p, IntPtr v, uint w);
  [DllImport("user32.dll", SetLastError=true)]
  public static extern bool SystemParametersInfo(uint a, uint p, ref ANIMATIONINFO v, uint w);
    [StructLayout(LayoutKind.Sequential)]
    public struct ANIMATIONINFO { public uint cbSize; public int iMinAnimate; }
}
'@
}

$drag = (Get-ItemProperty 'HKCU:\Control Panel\Desktop' -ErrorAction SilentlyContinue).DragFullWindows
$applyVisualEffects = $true

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
    
    [WtSpi]::SystemParametersInfo(0x0025, 1, [IntPtr]::Zero, 3) | Out-Null
    Say "Turned on 'Show window contents while dragging' (required) - nothing else changed" 'Yellow'
} else {
    Say "Skipped Windows Visual Effects tuning." 'DarkGray'
}

$applyExplorerTuning = $true
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

Say "Restarting Explorer to apply all settings..." 'Yellow'
Stop-Process -Name explorer -Force
Start-Sleep -Seconds 2

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
