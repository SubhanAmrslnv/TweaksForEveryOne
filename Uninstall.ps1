<#
.SYNOPSIS
    Removes Window Tweaks.

.DESCRIPTION
    Stops the program, deletes the shortcuts and the install folder.

    AutoHotkey is left alone - remove it separately if you want:
        winget uninstall AutoHotkey.AutoHotkey
#>
[CmdletBinding()]
param([switch]$Silent)

$ErrorActionPreference = 'SilentlyContinue'
function Say ($m, $c = 'Gray') { Write-Host "  $m" -ForegroundColor $c }

Write-Host "`n  Window Tweaks - uninstall`n" -ForegroundColor Cyan

$dest      = Join-Path $env:LOCALAPPDATA 'Window Tweaks'
$startup   = Join-Path ([Environment]::GetFolderPath('Startup'))  'Window Tweaks.lnk'
$startMenu = Join-Path ([Environment]::GetFolderPath('Programs')) 'Window Tweaks.lnk'
$desktop   = Join-Path ([Environment]::GetFolderPath('Desktop'))  'Window Tweaks.lnk'

Write-Host "[1/5] Stopping the program" -ForegroundColor Cyan
# Graceful first (taskkill without /F posts WM_CLOSE), so the program's exit
# handler hands back every window it changed; force only what does not exit.
# The Stealth Panic settings GUI is a separate process and is stopped too.
$procs = @(Get-CimInstance Win32_Process -Filter "Name like 'AutoHotkey%'" |
           Where-Object { $_.CommandLine -like '*WindowTweaks.ahk*' -or $_.CommandLine -like '*StealthPanicUI.ahk*' })
foreach ($p in $procs) { & taskkill.exe /PID $p.ProcessId 2>&1 | Out-Null }
foreach ($p in $procs) {
    Wait-Process -Id $p.ProcessId -Timeout 5
    if (Get-Process -Id $p.ProcessId) { Stop-Process -Id $p.ProcessId -Force }
}
Say $(if ($procs.Count) { "Stopped $($procs.Count)" } else { "Wasn't running" })

Write-Host "[2/5] Taskbar" -ForegroundColor Cyan
# The program restores the taskbar when it exits cleanly. Killing it does not
# run that path, so offer the guaranteed reset.
if ($Silent) {
    Say "Skipped (silent). Restart Explorer if the taskbar looks short." 'DarkGray'
} else {
    $a = Read-Host "  Restart Explorer to be certain the taskbar is back to normal? (y/N)"
    if ($a -match '^[Yy]') {
        Stop-Process -Name explorer -Force
        Start-Sleep -Seconds 3
        if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
        Say "Explorer restarted" 'Green'
    } else {
        Say "Skipped - if the taskbar looks short, restart Explorer from Task Manager"
    }
}

Write-Host "[3/5] Windows Tuning" -ForegroundColor Cyan
if (Test-Path $dest) {
    $restoreScript = Join-Path $dest 'scripts\Restore-Windows-Tuning.ps1'
    if (Test-Path $restoreScript) {
        if (-not $Silent) {
            $a = Read-Host "  Restore Windows tuning settings? (y/N)"
            if ($a -match '^[Yy]') {
                & $restoreScript
            } else {
                Say "Skipped"
            }
        } else {
            Say "Skipped (silent)" 'DarkGray'
        }
    }
}
$backupDir = Join-Path $env:LOCALAPPDATA 'Window Tweaks Backup'
$dragBackupFile = Join-Path $backupDir 'drag-backup.txt'
if (Test-Path $dragBackupFile) {
    $drag = Get-Content $dragBackupFile
    if ($drag -eq 'absent') {
        Remove-ItemProperty 'HKCU:\Control Panel\Desktop' 'DragFullWindows' -ErrorAction SilentlyContinue
        $val = 0
    } else {
        Set-ItemProperty 'HKCU:\Control Panel\Desktop' 'DragFullWindows' $drag -Type String
        $val = [int]$drag
    }
    if (-not ('WtSpi' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class WtSpi {
  [DllImport("user32.dll", SetLastError=true)]
  public static extern bool SystemParametersInfo(uint a, uint p, IntPtr v, uint w);
}
'@
    }
    [WtSpi]::SystemParametersInfo(0x0025, $val, [IntPtr]::Zero, 3) | Out-Null
}
if (Test-Path $backupDir) {
    Remove-Item $backupDir -Recurse -Force
}

Write-Host "[4/5] Removing shortcuts" -ForegroundColor Cyan
$spSettings = Join-Path ([Environment]::GetFolderPath('Programs')) 'Stealth Panic Mode Settings.lnk'
foreach ($l in @($startup, $startMenu, $desktop, $spSettings)) {
    if (Test-Path $l) { Remove-Item $l -Force; Say "Removed $(Split-Path $l -Leaf)" }
}
# Older versions wrote the Stealth Panic launch log to %APPDATA%, outside the
# install folder; it now lives inside it and goes with the folder below.
$legacyLog = Join-Path $env:APPDATA 'StealthPanic_Launch.log'
if (Test-Path $legacyLog) { Remove-Item $legacyLog -Force; Say "Removed StealthPanic_Launch.log" }

Write-Host "[5/5] Removing the install folder" -ForegroundColor Cyan
if (Test-Path $dest) {
    if ($PSScriptRoot -eq $dest) {
        # Can't delete the folder we're executing from; hand it back to the user.
        Say "You're running the copy inside the install folder." 'Yellow'
        Say "Delete it yourself once this window closes:" 'Yellow'
        Say $dest 'Yellow'
    } else {
        Remove-Item $dest -Recurse -Force
        Say "Deleted $dest" 'Green'
    }
} else {
    Say "Nothing installed at $dest"
}

Write-Host "`n  Done. No services or system files were ever created.`n" -ForegroundColor Green
