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
    Fluid window animations, Fluent transparency, shadows, the translucent
    selection rectangle, and the one setting the ice glide genuinely requires
    (Show window contents while dragging).

.PARAMETER MinimalAnimations
    Only the essentials: Show window contents while dragging, the menu and
    taskbar-preview delay removals, the caret, and minimise/maximise animation.
    Skips the decorative effects that -Animations turns on.

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
$PATH_MOUSE    = 'HKCU:\Control Panel\Mouse'
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

# Explorer\Advanced values are read once at shell start. Without this nudge the
# change is real in the registry but invisible until the next sign-out, which
# reads as "the script did nothing".
function Update-Explorer {
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
    # SHCNE_ASSOCCHANGED, SHCNF_IDLIST
    [WtShell]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)
}

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
    # -not ($mask) would be TRUE for a one-byte 0x00 mask, recording $null and
    # making the animations permanently unrestorable. Test length, not truth.
    $maskText = $null
    if ($null -ne $mask -and $mask.Length -gt 0) {
        $maskText = ($mask | ForEach-Object { $_.ToString('X2') }) -join ' '
    }
    $backup = [ordered]@{
        Created             = (Get-Date).ToString('s')
        Computer            = $env:COMPUTERNAME
        UserPreferencesMask = $maskText
        DragFullWindows     = Get-Value $PATH_DESKTOP  'DragFullWindows'
        MenuShowDelay       = Get-Value $PATH_DESKTOP  'MenuShowDelay'
        MouseHoverTime      = Get-Value $PATH_MOUSE    'MouseHoverTime'
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

    Set-Tuning $PATH_DESKTOP 'MenuShowDelay' '50' 'String'
    Set-Tuning $PATH_MOUSE   'MouseHoverTime' '100' 'String'
    Say "Eliminate artificial menu and taskbar preview opening delays"

    # Repair broken caret from previous versions
    $currentBlink = Get-Value $PATH_DESKTOP 'CursorBlinkRate'
    if ($currentBlink -eq '-1') {
        Set-Tuning $PATH_DESKTOP 'CursorBlinkRate' '530' 'String'
    }
    $currentWidth = Get-Value $PATH_DESKTOP 'CaretWidth'
    if ($currentWidth -eq 3) {
        Set-Tuning $PATH_DESKTOP 'CaretWidth' 1 'DWord'
    }

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

    # The one setting the ice glide genuinely requires. The registry write above
    # is not enough on its own - without this call it stays inert until the next
    # sign-out, so the headline feature is invisible for the whole session.
    $null = [WtSpi]::SystemParametersInfo(0x0025, 1, [IntPtr]::Zero, $SPIF)
    Say "Show window contents while dragging  (REQUIRED by the glide)"

    $ai = New-Object WtSpi+ANIMATIONINFO
    $ai.cbSize = 8
    $ai.iMinAnimate = 1
    $null = [WtSpi]::SystemParametersInfo(0x0049, 8, [ref]$ai, $SPIF)
    Say "Animate windows when minimizing and maximizing"

    if ($currentBlink -eq '-1') {
        $null = [WtSpi]::SystemParametersInfo(0x0201, 530, [IntPtr]::Zero, $SPIF)
    }
    if ($currentWidth -eq 3) {
        $null = [WtSpi]::SystemParametersInfo(0x2007, 0, [IntPtr]1, $SPIF)
    }

    # Every constant here is the SET half of its pair, checked against the
    # documented SPI_* values. Three of these were previously wrong and silently
    # flipped unrelated system flags:
    #   0x1017 is SETTOOLTIPANIMATION,  not SETMENUFADE      (0x1013)
    #   0x104B is SETSPEECHRECOGNITION, not SETDROPSHADOW    (0x1025)
    #   0x101D is SETMOUSESONAR,        not SETCURSORSHADOW  (0x101B)
    $effectsOn = [ordered]@{
        'UI effects (master switch)'         = 0x103F   # SPI_SETUIEFFECTS
        'Fade or slide menus into view'      = 0x1003   # SPI_SETMENUANIMATION
        'Slide open combo boxes'             = 0x1005   # SPI_SETCOMBOBOXANIMATION
        'Smooth-scroll list boxes'           = 0x1007   # SPI_SETLISTBOXSMOOTHSCROLLING
        'Fade out menu items after clicking' = 0x1013   # SPI_SETMENUFADE
        'Selection fade'                     = 0x1015   # SPI_SETSELECTIONFADE
        'Fade or slide ToolTips into view'   = 0x1019   # SPI_SETTOOLTIPFADE
        'Show shadows under mouse pointer'   = 0x101B   # SPI_SETCURSORSHADOW
        'Animate controls inside windows'    = 0x1043   # SPI_SETCLIENTAREAANIMATION
    }

    $effectsOff = [ordered]@{
        'Show shadows under windows'         = 0x1025   # SPI_SETDROPSHADOW
    }

    # -MinimalAnimations stops here: the glide dependency, the delay removals,
    # the caret, and minimise/maximise animation. Everything past this point is
    # decoration, which is exactly what "minimal" is asking to skip. (These two
    # switches used to run identical code despite the docs promising otherwise.)
    if ($MinimalAnimations -and -not $Animations) {
        Say "Minimal: skipped the decorative effects" 'DarkGray'
        Update-Explorer
    } else {
        foreach ($name in $effectsOn.Keys) {
            $null = [WtSpi]::SystemParametersInfo($effectsOn[$name], 0, $ON, $SPIF)
            Say $name
        }
        foreach ($name in $effectsOff.Keys) {
            $null = [WtSpi]::SystemParametersInfo($effectsOff[$name], 0, [IntPtr]::Zero, $SPIF)
            Say "Disabled $name" 'Yellow'
        }

        Set-Tuning $PATH_ADVANCED 'TaskbarAnimations'   1 'DWord'
        Say "Taskbar animations"

        # The Performance Options checkboxes. All ON: this script is named for
        # animations and its own help promises Fluent transparency.
        # ListviewAlphaSelect is "Show translucent selection rectangle", the
        # Explorer marquee. It must stay enabled.
        Set-Tuning $PATH_ADVANCED 'ListviewAlphaSelect' 1 'DWord'
        Set-Tuning $PATH_ADVANCED 'ListviewShadow'      1 'DWord'
        Set-Tuning $PATH_PERSONAL 'EnableTransparency'  0 'DWord'
        Set-Tuning $PATH_DWM      'EnableAeroPeek'      1 'DWord'
        Say "Translucent selection rectangle, icon label shadows, transparency, Aero Peek"

        Update-Explorer
        Write-Host "  Some of these settle fully only after an Explorer restart." -ForegroundColor DarkGray
    }
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
    Update-Explorer
    Write-Host "  Restart Explorer or sign out for these four to take effect." -ForegroundColor DarkGray
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
