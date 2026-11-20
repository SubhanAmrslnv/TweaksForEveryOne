@echo off
setlocal DisableDelayedExpansion
if /i "%~f0"=="%WINDOW_TWEAKS_RUN%\runner.cmd" goto run
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

rem Transfer the batch context to a temporary launcher before removing the
rem installed copy. cmd reopens the current batch as it reads commands.
copy /y "%WINDOW_TWEAKS_BATCH%" "%WINDOW_TWEAKS_RUN%\runner.cmd" >nul
if errorlevel 1 goto cleanup_error
set "WINDOW_TWEAKS_CALLER_DIR=%CD%"
cd /d "%WINDOW_TWEAKS_RUN%"
if errorlevel 1 goto cleanup_error
"%WINDOW_TWEAKS_RUN%\runner.cmd" %*
goto cleanup_error

:run
"%WINDOW_TWEAKS_PS%" -NoProfile -ExecutionPolicy Bypass -File "%WINDOW_TWEAKS_RUN%\entry.ps1" %*
set "WINDOW_TWEAKS_STATUS=%errorlevel%"
cd /d "%WINDOW_TWEAKS_RUN%\.."
if exist "%WINDOW_TWEAKS_CALLER_DIR%\." cd /d "%WINDOW_TWEAKS_CALLER_DIR%"
del /q "%WINDOW_TWEAKS_RUN%\entry.ps1" 2>nul
rem Let this batch return its exit status before deleting the temporary runner.
start "" /b "%WINDOW_TWEAKS_PS%" -NoProfile -Command "Start-Sleep -Seconds 1; $runner = Join-Path $env:WINDOW_TWEAKS_RUN 'runner.cmd'; [IO.File]::Delete($runner); [IO.Directory]::Delete($env:WINDOW_TWEAKS_RUN)"
exit /b %WINDOW_TWEAKS_STATUS%

:cleanup_error
set "WINDOW_TWEAKS_STATUS=1"
:cleanup
del /q "%WINDOW_TWEAKS_RUN%\entry.ps1" "%WINDOW_TWEAKS_RUN%\runner.cmd" 2>nul
rd "%WINDOW_TWEAKS_RUN%" 2>nul
exit /b %WINDOW_TWEAKS_STATUS%

# POWERSHELL SCRIPT
<#
.SYNOPSIS
    Removes Window Tweaks.

.DESCRIPTION
    Stops the program, deletes the shortcuts and the program files.

    Your settings are KEPT by default - settings.ini, window-positions.ini and
    the Stealth Panic config stay in the install folder, so a later reinstall
    picks them up unchanged. Pass -RemoveSettings to delete them as well.

    AutoHotkey is left alone - remove it separately if you want:
        winget uninstall AutoHotkey.AutoHotkey
#>
[CmdletBinding()]
param(
    [switch]$Silent,
    # Also delete settings.ini, window-positions.ini and the Stealth Panic config.
    [switch]$RemoveSettings
)

function Say ($m, $c = 'Gray') { Write-Host "  $m" -ForegroundColor $c }

# Handle directory links as entries so cleanup stays inside the install root.
function Remove-InstallEntry($item) {
    if ($item.PSIsContainer) {
        if (-not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            foreach ($child in Get-ChildItem -LiteralPath $item.FullName -Force -ErrorAction Stop) {
                Remove-InstallEntry $child
            }
        }
        [IO.Directory]::Delete($item.FullName)
    } else {
        Remove-Item -LiteralPath $item.FullName -Force -ErrorAction Stop
    }
}

Write-Host "`n  Window Tweaks - uninstall`n" -ForegroundColor Cyan

$local = [Environment]::GetFolderPath('LocalApplicationData')
if (-not $local) { throw 'Could not locate Local AppData.' }
$dest      = Join-Path $local 'Window Tweaks'
$startup   = Join-Path ([Environment]::GetFolderPath('Startup'))  'Window Tweaks.lnk'
$startMenu = Join-Path ([Environment]::GetFolderPath('Programs')) 'Window Tweaks.lnk'
$desktop   = Join-Path ([Environment]::GetFolderPath('Desktop'))  'Window Tweaks.lnk'

$failed = $false
if (Test-Path -LiteralPath $dest) {
    $directory = Get-Item -LiteralPath $dest -Force -ErrorAction Stop
    if (-not $directory.PSIsContainer -or ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
        (Test-Path -LiteralPath (Join-Path $dest '.git')) -or (Test-Path -LiteralPath (Join-Path $dest 'src'))) {
        throw "Expected an installed program folder at $dest."
    }
}

Write-Host "[1/5] Stopping the program" -ForegroundColor Cyan
# Graceful first (taskkill without /F posts WM_CLOSE), so the program's exit
# handler hands back every window it changed; force only what does not exit.
# The Stealth Panic settings GUI is a separate process and is stopped too.
$entryPoints = 'WindowTweaks.ahk', 'StealthPanicUI.ahk' | ForEach-Object {
    [regex]::Escape((Join-Path $dest $_))
}
$installedCommand = '(?:^|\s)(?:"(?:{0})"|(?:{0}))(?=\s|$)' -f ($entryPoints -join '|')
$sessionId = (Get-Process -Id $PID -ErrorAction Stop).SessionId
$procs = @(Get-CimInstance Win32_Process -Filter "Name like 'AutoHotkey%' AND SessionId = $sessionId" -ErrorAction Stop |
           Where-Object { $_.CommandLine -match $installedCommand })
foreach ($p in $procs) { & taskkill.exe /PID $p.ProcessId 2>&1 | Out-Null }
foreach ($p in $procs) {
    Wait-Process -Id $p.ProcessId -Timeout 5 -ErrorAction SilentlyContinue
    if (Get-Process -Id $p.ProcessId -ErrorAction SilentlyContinue) {
        Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
        Wait-Process -Id $p.ProcessId -Timeout 5 -ErrorAction SilentlyContinue
    }
}
foreach ($p in $procs) {
    if (Get-Process -Id $p.ProcessId -ErrorAction SilentlyContinue) {
        throw "Could not stop process $($p.ProcessId). Close the program and retry."
    }
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
        $sessionId = (Get-Process -Id $PID).SessionId
        Get-Process -Name explorer -ErrorAction SilentlyContinue |
            Where-Object { $_.SessionId -eq $sessionId } |
            Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
        if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $sessionId })) {
            Start-Process explorer.exe
        }
        Say "Explorer restarted" 'Green'
    } else {
        Say "Skipped - if the taskbar looks short, restart Explorer from Task Manager"
    }
}

Write-Host "[3/5] Windows Tuning" -ForegroundColor Cyan
$backupDir = Join-Path $env:LOCALAPPDATA 'Window Tweaks Backup'
$dragBackupFile = Join-Path $backupDir 'drag-backup.txt'
$installedScripts = Join-Path $dest 'scripts'
$sourceScripts = Join-Path ([IO.Path]::GetDirectoryName($env:WINDOW_TWEAKS_BATCH)) 'scripts'
$legacyTuningBackup = Join-Path $installedScripts 'tuning-backup.json'
$scriptFolders = @($sourceScripts, $installedScripts) | Select-Object -Unique | Where-Object {
    $folder = Get-Item -LiteralPath $_ -Force -ErrorAction SilentlyContinue
    $folder.PSIsContainer -and -not ($folder.Attributes -band [IO.FileAttributes]::ReparsePoint)
}
$backupPaths = @(Join-Path $backupDir 'tuning-backup.json')
$backupPaths += @($scriptFolders | Sort-Object { $_ -ne $installedScripts } |
    ForEach-Object { Join-Path $_ 'tuning-backup.json' })
$tuningBackupFile = $backupPaths | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
$restoreScript = $scriptFolders | ForEach-Object { Join-Path $_ 'Restore-Windows-Tuning.bat' } |
    Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1

function Restore-LegacyDrag($backup) {
    $drag = ([IO.File]::ReadAllText($backup)).Trim()
    if ($drag -notmatch '^(absent|[01])$') { throw 'Invalid drag-backup.txt contents.' }
    if (-not ('WtDragRestore' -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class WtDragRestore {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SystemParametersInfo(uint action, uint parameter, IntPtr value, uint flags);
}
"@ -ErrorAction Stop
    }
    $val = if ($drag -eq '1') { [uint32]1 } else { [uint32]0 }
    # Apply live without persisting a new value. Restore registry presence separately.
    if (-not [WtDragRestore]::SystemParametersInfo(0x0025, $val, [IntPtr]::Zero, 2)) {
        $code = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "SystemParametersInfo failed (Win32 error $code)."
    }
    $desktopKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Control Panel\Desktop', $true)
    if ($null -eq $desktopKey) { throw 'Could not open the Desktop registry key.' }
    try {
        if ($drag -eq 'absent') {
            $desktopKey.DeleteValue('DragFullWindows', $false)
        } else {
            $desktopKey.SetValue('DragFullWindows', $drag, [Microsoft.Win32.RegistryValueKind]::String)
        }
    } finally {
        $desktopKey.Dispose()
    }
}

$restoreRequested = $false
if ($tuningBackupFile -and -not $Silent) {
    $restoreRequested = (Read-Host "  Restore Windows tuning settings? (y/N)") -match '^[Yy]'
}

# A legacy drag backup may predate the wider tuning snapshot. Replay it last,
# and keep both copies until the requested rollback has succeeded.
if (-not $tuningBackupFile -or $restoreRequested) {
    try {
        if ($tuningBackupFile) {
            if (-not $restoreScript) { throw 'Restore-Windows-Tuning.bat is missing. Use a current source copy of Uninstall.bat to retry.' }
            & $restoreScript -BackupFile $tuningBackupFile
            if ($LASTEXITCODE -ne 0) { throw "Restore exited with code $LASTEXITCODE." }
        }
        $dragPending = Test-Path -LiteralPath $dragBackupFile
        if ($dragPending) { Restore-LegacyDrag $dragBackupFile }
        if ($tuningBackupFile) { Remove-Item -LiteralPath $tuningBackupFile -Force -ErrorAction Stop }
        if ($dragPending) { Remove-Item -LiteralPath $dragBackupFile -Force -ErrorAction Stop }
    } catch {
        Say "Could not finish restoring Windows settings: $($_.Exception.Message)" 'Yellow'
        $failed = $true
    }
}

$recoveryPending = @(($backupPaths + $dragBackupFile) | Where-Object { Test-Path -LiteralPath $_ }).Count -gt 0
if ($recoveryPending) {
    Say "Kept the Windows settings backup. Run Uninstall.bat again to restore it." 'Yellow'
}

Write-Host "[4/5] Removing shortcuts" -ForegroundColor Cyan
$spSettings = Join-Path ([Environment]::GetFolderPath('Programs')) 'Stealth Panic Mode Settings.lnk'
foreach ($l in @($startup, $startMenu, $desktop, $spSettings)) {
    if (Test-Path $l) {
        Remove-Item $l -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path $l)) { Say "Removed $(Split-Path $l -Leaf)" }
        else { Say "Could not remove $(Split-Path $l -Leaf)" 'Yellow'; $failed = $true }
    }
}
# Older versions wrote the Stealth Panic launch log to %APPDATA%, outside the
# install folder; it now lives inside it and goes with the folder below.
$legacyLog = Join-Path $env:APPDATA 'StealthPanic_Launch.log'
if (Test-Path $legacyLog) {
    Remove-Item $legacyLog -Force -ErrorAction SilentlyContinue
    if (-not (Test-Path $legacyLog)) { Say "Removed StealthPanic_Launch.log" }
    else { Say "Could not remove StealthPanic_Launch.log" 'Yellow'; $failed = $true }
}

Write-Host "[5/5] Removing program files" -ForegroundColor Cyan
try {
    if (Test-Path -LiteralPath $dest) {
        $keep = if ($RemoveSettings) { @() } else {
            @('settings.ini', 'window-positions.ini', 'StealthPanic.ini', 'StealthPanicApps.txt')
        }
        $uninstaller = Join-Path $dest 'Uninstall.bat'
        $entries = Get-ChildItem -LiteralPath $dest -Force -ErrorAction Stop
        foreach ($item in $entries) {
            if ($keep -contains $item.Name -or $item.FullName -eq $uninstaller) { continue }
            if ($recoveryPending -and $item.FullName -eq $installedScripts -and $scriptFolders -contains $installedScripts) {
                foreach ($scriptItem in Get-ChildItem -LiteralPath $installedScripts -Force -ErrorAction Stop) {
                    if ($scriptItem.FullName -eq $legacyTuningBackup -or $scriptItem.Name -eq 'Restore-Windows-Tuning.bat') { continue }
                    Remove-InstallEntry $scriptItem
                }
            } else {
                Remove-InstallEntry $item
            }
        }
        if (-not $failed -and -not $recoveryPending -and (Test-Path -LiteralPath $uninstaller)) {
            Remove-InstallEntry (Get-Item -LiteralPath $uninstaller -Force -ErrorAction Stop)
        }
        $remaining = @(Get-ChildItem -LiteralPath $dest -Force -ErrorAction Stop)
        if ($remaining.Count -eq 0) { [IO.Directory]::Delete($dest) }
        if (@($remaining | Where-Object { $keep -contains $_.Name }).Count) {
            Say "Kept your settings in $dest"
        }
    }
} catch {
    Say "Could not clean up $dest. $($_.Exception.Message)" 'Yellow'
    $failed = $true
}

if ($failed) {
    Say 'Uninstall did not complete.' 'Yellow'
    exit 1
}
Write-Host "Program files removed." -ForegroundColor Green
