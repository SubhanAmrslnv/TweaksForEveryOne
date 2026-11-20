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
    Removes Stealth Panic Mode (Standalone).

.DESCRIPTION
    Stops the program and deletes its shortcuts and files. The Stealth Panic
    settings are kept by default. Pass -RemoveSettings to delete them too.
#>
[CmdletBinding()]
param([switch]$Silent, [switch]$RemoveSettings)

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

Write-Host "`n  Stealth Panic Mode - uninstall`n" -ForegroundColor Cyan

$local = [Environment]::GetFolderPath('LocalApplicationData')
if (-not $local) { throw 'Could not locate Local AppData.' }
$dest      = Join-Path $local 'Stealth Panic Mode'
$startup   = Join-Path ([Environment]::GetFolderPath('Startup'))  'Stealth Panic Mode.lnk'
$startMenu = Join-Path ([Environment]::GetFolderPath('Programs')) 'Stealth Panic Mode.lnk'
# Created by the installer and previously left behind on uninstall.
$settings  = Join-Path ([Environment]::GetFolderPath('Programs')) 'Stealth Panic Mode Settings (Standalone).lnk'
$unlink    = Join-Path ([Environment]::GetFolderPath('Programs')) 'Uninstall Stealth Panic Mode.lnk'

$failed = $false
if (Test-Path -LiteralPath $dest) {
    $directory = Get-Item -LiteralPath $dest -Force -ErrorAction Stop
    if (-not $directory.PSIsContainer -or ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
        (Test-Path -LiteralPath (Join-Path $dest '.git')) -or (Test-Path -LiteralPath (Join-Path $dest 'src'))) {
        throw "Expected an installed program folder at $dest."
    }
}

Write-Host "[1/3] Stopping the program" -ForegroundColor Cyan
$entryPoints = 'Stealth Panic Mode.ahk', 'StealthPanicUI.ahk' | ForEach-Object {
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

Write-Host "[2/3] Deleting Shortcuts" -ForegroundColor Cyan
$del = 0
foreach ($lnk in $startup, $startMenu, $settings, $unlink) {
    if (Test-Path $lnk) {
        Remove-Item $lnk -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path $lnk)) { $del++ }
        else { Say "Could not remove $(Split-Path $lnk -Leaf)" 'Yellow'; $failed = $true }
    }
}
Say "Deleted $del shortcuts"

Write-Host "[3/3] Removing program files" -ForegroundColor Cyan
try {
    if (Test-Path -LiteralPath $dest) {
        $keep = if ($RemoveSettings) { @() } else { @('StealthPanic.ini', 'StealthPanicApps.txt') }
        $uninstaller = Join-Path $dest 'Uninstall Stealth Panic Mode.bat'
        foreach ($item in Get-ChildItem -LiteralPath $dest -Force -ErrorAction Stop) {
            if ($keep -contains $item.Name -or $item.FullName -eq $uninstaller) { continue }
            Remove-InstallEntry $item
        }
        if (-not $failed -and (Test-Path -LiteralPath $uninstaller)) {
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
