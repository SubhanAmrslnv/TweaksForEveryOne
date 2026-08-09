<#
.SYNOPSIS
    Removes Stealth Panic Mode (Standalone).

.DESCRIPTION
    Stops the program, deletes the shortcuts and the install folder.
#>
[CmdletBinding()]
param([switch]$Silent)

$ErrorActionPreference = 'SilentlyContinue'
function Say ($m, $c = 'Gray') { Write-Host "  $m" -ForegroundColor $c }

Write-Host "`n  Stealth Panic Mode - uninstall`n" -ForegroundColor Cyan

$dest      = Join-Path $env:LOCALAPPDATA 'Stealth Panic Mode'
$startup   = Join-Path ([Environment]::GetFolderPath('Startup'))  'Stealth Panic Mode.lnk'
$startMenu = Join-Path ([Environment]::GetFolderPath('Programs')) 'Stealth Panic Mode.lnk'
# Created by the installer and previously left behind on uninstall.
$settings  = Join-Path ([Environment]::GetFolderPath('Programs')) 'Stealth Panic Mode Settings (Standalone).lnk'
$unlink    = Join-Path ([Environment]::GetFolderPath('Programs')) 'Uninstall Stealth Panic Mode.lnk'

Write-Host "[1/3] Stopping the program" -ForegroundColor Cyan
$found = 0
Get-CimInstance Win32_Process -Filter "Name like 'AutoHotkey%'" |
    Where-Object { $_.CommandLine -like '*Stealth Panic Mode.ahk*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force; $found++ }
Say $(if ($found) { "Stopped $found" } else { "Wasn't running" })
Start-Sleep -Milliseconds 800

Write-Host "[2/3] Deleting Shortcuts" -ForegroundColor Cyan
$del = 0
foreach ($lnk in $startup, $startMenu, $settings, $unlink) {
    if (Test-Path $lnk) { Remove-Item $lnk -Force; $del++ }
}
Say "Deleted $del shortcuts"

Write-Host "[3/3] Removing Files" -ForegroundColor Cyan
if (Test-Path $dest) {
    Remove-Item $dest -Recurse -Force
    Say "Removed $dest"
} else {
    Say "Already removed"
}

Write-Host "`nStandalone Stealth Panic Mode is gone." -ForegroundColor Cyan
