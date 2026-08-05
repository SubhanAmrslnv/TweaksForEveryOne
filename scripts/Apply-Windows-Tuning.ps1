<#
.SYNOPSIS
    Turns on the Windows animation and Explorer settings that Window Tweaks
    needs and benefits from.

.DESCRIPTION
    Writes to HKCU only. No admin rights, no system files, no services, no
    drivers, nothing outside your user profile.

    Your current values are saved to tuning-backup.json (next to this script)
    the first time it runs. Restore-Windows-Tuning.ps1 puts them all back.

    Nothing here disables Windows Update, Defender, or any security feature.

.PARAMETER Animations
    Fluid window animations, Fluent transparency, and the one setting the ice
    glide genuinely requires (Show window contents while dragging).

.PARAMETER Explorer
    Explorer responsiveness: open to This PC, run folder windows in a separate
    process, and stop Quick Access probing recent files (a common cause of
    Explorer hanging for seconds on network paths).

.PARAMETER All
    Both of the above. This is the default if you pass nothing.

.EXAMPLE
    .\Apply-Windows-Tuning.ps1
    .\Apply-Windows-Tuning.ps1 -Animations
#>
[CmdletBinding()]
param(
    [switch]$Animations,
    [switch]$MinimalAnimations,
    [switch]$Explorer,
    [switch]$All
)

$ErrorActionPreference = 'Stop'
if (-not ($Animations -or $MinimalAnimations -or $Explorer)) { $All = $true }
if ($All) { $Animations = $true; $Explorer = $true }

$backupDir = Join-Path $env:LOCALAPPDATA 'Window Tweaks Backup'
if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
$backupFile = Join-Path $backupDir 'tuning-backup.json'

$PATH_DESKTOP  = 'HKCU:\Control Panel\Desktop'
$PATH_METRICS  = 'HKCU:\Control Panel\Desktop\WindowMetrics'
$PATH_ADVANCED = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$PATH_EXPLORER = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer'
$PATH_PERSONAL = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
$PATH_DWM      = 'HKCU:\Software\Microsoft\Windows\DWM'

function Set-Tuning($path, $name, $value, $type) {
    if (-not (Test-Path $path)) { New-Item -Path $path -Force -ErrorAction SilentlyContinue | Out-Null }
    try { Set-ItemProperty -Path $path -Name $name -Value $value -Type $type -ErrorAction Stop } catch { Write-Host "  Failed to set $name" -ForegroundColor Yellow }
}

function Get-Value($path, $name) {
    try { return (Get-ItemProperty -Path $path -Name $name -ErrorAction Stop).$name }
    catch { return $null }
}

function Say($msg, $colour = 'Green') { Write-Host "  $msg" -ForegroundColor $colour }

Write-Host "`nWindow Tweaks - Windows tuning" -ForegroundColor Cyan
Write-Host "HKCU only. Reversible with Restore-Windows-Tuning.ps1.`n" -ForegroundColor DarkGray

# ---------------------------------------------------------------- backup ----
# Only ever written once, so re-running never overwrites the real originals
# with values this script itself set.
if (Test-Path $backupFile) {
    Say "tuning-backup.json already exists - keeping your original values" 'DarkGray'
} elseif (Test-Path (Join-Path $PSScriptRoot 'tuning-backup.json')) {
    Say "tuning-backup.json exists in scripts folder - keeping your original values" 'DarkGray'
} else {
    $mask = Get-Value $PATH_DESKTOP 'UserPreferencesMask'
    $backup = [ordered]@{
        Created             = (Get-Date).ToString('s')
        Computer            = $env:COMPUTERNAME
        UserPreferencesMask = if ($mask) { ($mask | ForEach-Object { $_.ToString('X2') }) -join ' ' } else { $null }
        DragFullWindows     = Get-Value $PATH_DESKTOP  'DragFullWindows'
        MinAnimate          = Get-Value $PATH_METRICS  'MinAnimate'
        EnableTransparency  = Get-Value $PATH_PERSONAL 'EnableTransparency'
        TaskbarAnimations   = Get-Value $PATH_ADVANCED 'TaskbarAnimations'
        ListviewAlphaSelect = Get-Value $PATH_ADVANCED 'ListviewAlphaSelect'
        ListviewShadow      = Get-Value $PATH_ADVANCED 'ListviewShadow'
        LaunchTo            = Get-Value $PATH_ADVANCED 'LaunchTo'
        SeparateProcess     = Get-Value $PATH_ADVANCED 'SeparateProcess'
        ShowRecent          = Get-Value $PATH_EXPLORER 'ShowRecent'
        ShowFrequent        = Get-Value $PATH_EXPLORER 'ShowFrequent'
        EnableAeroPeek      = Get-Value $PATH_DWM      'EnableAeroPeek'
    }
    $backup | ConvertTo-Json | Set-Content $backupFile -Encoding utf8
    Say "Saved your current values to tuning-backup.json" 'DarkGray'
}

# ------------------------------------------------------------ animations ----
if ($Animations -or $MinimalAnimations) {
    if ($Animations) { Write-Host "`n[Animations]" -ForegroundColor Cyan }
    else { Write-Host "`n[Minimal Animations]" -ForegroundColor Cyan }

    # The one setting the ice glide genuinely requires. With it off, Windows
    # drags a hollow outline and you would never see the slide.
    Set-Tuning $PATH_DESKTOP 'DragFullWindows' '1' 'String'
    Say "Show window contents while dragging  (REQUIRED by the glide)"

    # Use the documented API rather than hand-editing UserPreferencesMask, so
    # Windows recalculates its own mask and applies it without a sign-out.
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
    $SPIF = 3            # SPIF_UPDATEINIFILE | SPIF_SENDCHANGE
    $ON   = [IntPtr]1

    $ai = New-Object WtSpi+ANIMATIONINFO
    $ai.cbSize = 8
    $ai.iMinAnimate = 1
    $null = [WtSpi]::SystemParametersInfo(0x0049, 8, [ref]$ai, $SPIF)
    Say "Animate windows when minimizing and maximizing"

    $OFF = [IntPtr]0

    $effectsOn = [ordered]@{
        'UI effects (master switch)'         = 0x103F
        'Fade or slide menus into view'      = 0x1003
        'Slide open combo boxes'             = 0x1005
        'Smooth-scroll list boxes'           = 0x1007
        'Fade out menu items after clicking' = 0x1017
    }

    $effectsOff = [ordered]@{
        'Selection fade'                     = 0x1015
        'Animate controls inside windows'    = 0x1043
        'Show shadows under windows'         = 0x104B
        'Fade or slide ToolTips into view'   = 0x1019
        'Show shadows under mouse pointer'   = 0x101D
    }
    
    foreach ($name in $effectsOn.Keys) {
        $null = [WtSpi]::SystemParametersInfo($effectsOn[$name], 0, $ON, $SPIF)
        Say $name
    }

    foreach ($name in $effectsOff.Keys) {
        $null = [WtSpi]::SystemParametersInfo($effectsOff[$name], 0, $OFF, $SPIF)
    }
    Say "Disabled other visual effects (shadows, selection fade, etc.)" 'DarkGray'

    Set-Tuning $PATH_ADVANCED 'TaskbarAnimations'   1 'DWord'
    Say "Taskbar animations"

    Set-Tuning $PATH_ADVANCED 'ListviewAlphaSelect' 0 'DWord'
    Set-Tuning $PATH_ADVANCED 'ListviewShadow'      0 'DWord'
    Set-Tuning $PATH_PERSONAL 'EnableTransparency'  0 'DWord'
    Set-Tuning $PATH_DWM      'EnableAeroPeek'      0 'DWord'
    Say "Disabled heavy UI features (Transparency, Shadows, Aero peek, Alpha select)" 'DarkGray'
}

# -------------------------------------------------------------- explorer ----
if ($Explorer) {
    Write-Host "`n[Explorer]" -ForegroundColor Cyan
    Set-Tuning $PATH_ADVANCED 'LaunchTo'        1 'DWord'
    Set-Tuning $PATH_ADVANCED 'SeparateProcess' 1 'DWord'
    Set-Tuning $PATH_EXPLORER 'ShowRecent'      0 'DWord'
    Set-Tuning $PATH_EXPLORER 'ShowFrequent'    0 'DWord'
    Say "Open File Explorer to This PC"
    Say "Run folder windows in a separate process (one hang can't freeze the shell)"
    Say "Stop Quick Access probing recent and frequent files"
    Write-Host "  Sign out and back in for these three to take effect." -ForegroundColor DarkGray
}

# --------------------------------------------------------------- notices ----
$snap = Get-Value $PATH_DESKTOP 'WindowArrangementActive'
if ($snap -eq 1) {
    Write-Host "`n[Note]" -ForegroundColor Yellow
    Write-Host "  Windows' own 'Snap windows' is ON, so Windows wins at screen edges." -ForegroundColor Yellow
    Write-Host "  Window-to-window magnetism is unaffected. Left alone on purpose:" -ForegroundColor Yellow
    Write-Host "  turning it off also disables Win+Left / Win+Right. See docs\ANIMATIONS.md." -ForegroundColor Yellow
}

Write-Host "`nDone.`n" -ForegroundColor Green
