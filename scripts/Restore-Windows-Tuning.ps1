<#
.SYNOPSIS
    Undoes Apply-Windows-Tuning.ps1.

.DESCRIPTION
    Reads tuning-backup.json (written by Apply-Windows-Tuning.ps1 on its first
    run) and puts every value back exactly as it was on THIS machine.

    It deliberately reads the backup rather than hard-coding any values -
    a hard-coded "original" would be one particular PC's settings and would
    corrupt anyone else's.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$backupDir = Join-Path $env:LOCALAPPDATA 'Window Tweaks Backup'
$backupFile = Join-Path $backupDir 'tuning-backup.json'

if (-not (Test-Path $backupFile)) {
    $backupFile = Join-Path $PSScriptRoot 'tuning-backup.json'
}

if (-not (Test-Path $backupFile)) {
    Write-Host "`nNo tuning-backup.json next to this script." -ForegroundColor Yellow
    Write-Host "Nothing to restore - either the tuning was never applied on this PC," -ForegroundColor Yellow
    Write-Host "or the backup was deleted.`n" -ForegroundColor Yellow
    return
}

$b = Get-Content $backupFile -Raw | ConvertFrom-Json

if ($b -is [array]) {
    Write-Host "`nThe backup file ($backupFile) is corrupt (contains a list instead of an object)." -ForegroundColor Yellow
    Write-Host "Cannot restore.`n" -ForegroundColor Yellow
    return
}

Write-Host "`nRestoring Windows tuning" -ForegroundColor Cyan
Write-Host "Backup taken $($b.Created) on $($b.Computer)`n" -ForegroundColor DarkGray

$PATH_DESKTOP  = 'HKCU:\Control Panel\Desktop'
$PATH_METRICS  = 'HKCU:\Control Panel\Desktop\WindowMetrics'
$PATH_ADVANCED = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$PATH_EXPLORER = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer'
$PATH_PERSONAL = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
$PATH_DWM      = 'HKCU:\Software\Microsoft\Windows\DWM'

# A value that was absent before must be removed again, not set to zero -
# otherwise "unset" silently becomes "explicitly off".
function Restore-One($path, $name, $value, $type) {
    if (-not (Test-Path $path)) { New-Item -Path $path -Force -ErrorAction SilentlyContinue | Out-Null }
    try {
        if ($null -eq $value) {
            Remove-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue
            Write-Host ("  {0,-22} -> removed (was not set)" -f $name) -ForegroundColor DarkGray
        } else {
            Set-ItemProperty -Path $path -Name $name -Value $value -Type $type -ErrorAction Stop
            Write-Host ("  {0,-22} -> {1}" -f $name, $value)
        }
    } catch {
        Write-Host ("  {0,-22} -> failed to restore: {1}" -f $name, $_.Exception.Message) -ForegroundColor Yellow
    }
}

if ($b.UserPreferencesMask) {
    if (-not (Test-Path $PATH_DESKTOP)) { New-Item -Path $PATH_DESKTOP -Force -ErrorAction SilentlyContinue | Out-Null }
    try {
        $bytes = [byte[]]($b.UserPreferencesMask -split ' ' | ForEach-Object { [Convert]::ToByte($_, 16) })
        Set-ItemProperty $PATH_DESKTOP 'UserPreferencesMask' $bytes -Type Binary -ErrorAction Stop
        Write-Host ("  {0,-22} -> {1}" -f 'UserPreferencesMask', $b.UserPreferencesMask)
    } catch {
        Write-Host ("  {0,-22} -> failed to restore: {1}" -f 'UserPreferencesMask', $_.Exception.Message) -ForegroundColor Yellow
    }
} else {
    Write-Host "  UserPreferencesMask    -> absent in backup (cannot restore animations)" -ForegroundColor Yellow
}

Restore-One $PATH_DESKTOP  'DragFullWindows'     $b.DragFullWindows     'String'
Restore-One $PATH_METRICS  'MinAnimate'          $b.MinAnimate          'String'
Restore-One $PATH_PERSONAL 'EnableTransparency'  $b.EnableTransparency  'DWord'
Restore-One $PATH_ADVANCED 'TaskbarAnimations'   $b.TaskbarAnimations   'DWord'
Restore-One $PATH_ADVANCED 'ListviewAlphaSelect' $b.ListviewAlphaSelect 'DWord'
Restore-One $PATH_ADVANCED 'ListviewShadow'      $b.ListviewShadow      'DWord'
Restore-One $PATH_ADVANCED 'LaunchTo'            $b.LaunchTo            'DWord'
Restore-One $PATH_ADVANCED 'SeparateProcess'     $b.SeparateProcess     'DWord'
Restore-One $PATH_EXPLORER 'ShowRecent'          $b.ShowRecent          'DWord'
Restore-One $PATH_EXPLORER 'ShowFrequent'        $b.ShowFrequent        'DWord'
Restore-One $PATH_DWM      'EnableAeroPeek'      $b.EnableAeroPeek      'DWord'

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
$SPIF = 3
if ($null -ne $b.DragFullWindows) {
    [WtSpi]::SystemParametersInfo(0x0025, [uint32]$b.DragFullWindows, [IntPtr]::Zero, $SPIF) | Out-Null
}
[WtSpi]::SystemParametersInfo(0x103F, 0, [IntPtr]1, $SPIF) | Out-Null

Write-Host "`nDone. Sign out and back in for everything to settle.`n" -ForegroundColor Green
