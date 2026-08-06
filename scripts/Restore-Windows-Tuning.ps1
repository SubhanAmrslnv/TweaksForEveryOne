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
$PATH_MOUSE    = 'HKCU:\Control Panel\Mouse'
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
Restore-One $PATH_DESKTOP  'MenuShowDelay'       $b.MenuShowDelay       'String'
Restore-One $PATH_MOUSE    'MouseHoverTime'      $b.MouseHoverTime      'String'
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
    # A non-numeric backed-up value would otherwise throw under
    # ErrorActionPreference = Stop and abort the rest of the restore.
    try {
        [WtSpi]::SystemParametersInfo(0x0025, [uint32]$b.DragFullWindows, [IntPtr]::Zero, $SPIF) | Out-Null
    } catch {
        Write-Host ("  {0,-22} -> could not re-apply: {1}" -f 'DragFullWindows', $_.Exception.Message) -ForegroundColor Yellow
    }
}

# Replay each effect from the mask we just restored, rather than forcing them.
#
# This used to be an unconditional SPI_SETUIEFFECTS = ON. With SPIF_UPDATEINIFILE
# that makes USER32 re-serialise its still-tuned in-memory mask straight back
# over the registry - undoing the UserPreferencesMask restore 40 lines above,
# and forcing UI effects on for anyone who had them off. Driving every SPI from
# the backed-up bits instead keeps registry and in-memory state in agreement.
$SPI_BITS = @(
    @{ Code = 0x103F; Byte = 3; Bit = 0x80 }   # SPI_SETUIEFFECTS
    @{ Code = 0x1003; Byte = 0; Bit = 0x02 }   # SPI_SETMENUANIMATION
    @{ Code = 0x1005; Byte = 0; Bit = 0x04 }   # SPI_SETCOMBOBOXANIMATION
    @{ Code = 0x1007; Byte = 0; Bit = 0x08 }   # SPI_SETLISTBOXSMOOTHSCROLLING
    @{ Code = 0x1013; Byte = 1; Bit = 0x02 }   # SPI_SETMENUFADE
    @{ Code = 0x1015; Byte = 1; Bit = 0x04 }   # SPI_SETSELECTIONFADE
    @{ Code = 0x1019; Byte = 1; Bit = 0x10 }   # SPI_SETTOOLTIPFADE
    @{ Code = 0x101B; Byte = 1; Bit = 0x20 }   # SPI_SETCURSORSHADOW
    @{ Code = 0x1025; Byte = 2; Bit = 0x04 }   # SPI_SETDROPSHADOW
    @{ Code = 0x1043; Byte = 4; Bit = 0x02 }   # SPI_SETCLIENTAREAANIMATION
)

if ($b.UserPreferencesMask) {
    try {
        $mb = [byte[]]($b.UserPreferencesMask -split ' ' | ForEach-Object { [Convert]::ToByte($_, 16) })
        $replayed = 0
        foreach ($s in $SPI_BITS) {
            if ($s.Byte -ge $mb.Length) { continue }
            $on = [bool]($mb[$s.Byte] -band $s.Bit)
            $val = if ($on) { [IntPtr]1 } else { [IntPtr]0 }
            [WtSpi]::SystemParametersInfo($s.Code, 0, $val, $SPIF) | Out-Null
            $replayed++
        }
        Write-Host ("  {0,-22} -> replayed {1} effects from the backed-up mask" -f 'UI effects', $replayed)
    } catch {
        Write-Host ("  {0,-22} -> could not replay: {1}" -f 'UI effects', $_.Exception.Message) -ForegroundColor Yellow
    }
} else {
    Write-Host "  UI effects             -> no mask in backup, left as-is" -ForegroundColor Yellow
}

# Explorer\Advanced values (ListviewAlphaSelect, ListviewShadow, TaskbarAnimations)
# are read at shell start, so nudge Explorer rather than waiting for a sign-out.
if (-not ('WtShell' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class WtShell {
  [DllImport("shell32.dll")]
  public static extern void SHChangeNotify(int eventId, uint flags, IntPtr a, IntPtr b);
}
'@
}
[WtShell]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)

Write-Host "`nDone. Restart Explorer or sign out for everything to settle.`n" -ForegroundColor Green
