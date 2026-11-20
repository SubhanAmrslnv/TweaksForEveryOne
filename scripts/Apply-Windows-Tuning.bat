@echo off
setlocal DisableDelayedExpansion
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

"%WINDOW_TWEAKS_PS%" -NoProfile -ExecutionPolicy Bypass -File "%WINDOW_TWEAKS_RUN%\entry.ps1" %*
set "WINDOW_TWEAKS_STATUS=%errorlevel%"

:cleanup
del /q "%WINDOW_TWEAKS_RUN%\entry.ps1" 2>nul
rd "%WINDOW_TWEAKS_RUN%" 2>nul
exit /b %WINDOW_TWEAKS_STATUS%

# POWERSHELL SCRIPT
<#
.SYNOPSIS
    Applies the Windows animation and Explorer settings used by Window Tweaks.

.DESCRIPTION
    Writes only to HKCU. Saves the original values once in
    %LOCALAPPDATA%\Window Tweaks Backup\tuning-backup.json.
    Restore-Windows-Tuning.bat restores the original values.

.PARAMETER Animations
    Enables Windows animations, Fluent transparency, shadows, and full-window dragging.

.PARAMETER MinimalAnimations
    Enables full-window dragging and minimize/maximize animation and reduces menu
    and mouse-hover delays. Leaves the other visual effects as they are.

.PARAMETER Explorer
    Opens Explorer to This PC, uses a separate folder-window process, and
    stops Quick Access from probing recent and frequent items.

.PARAMETER All
    Applies Animations and Explorer. This is the default with no switches.
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
$backupFile = Join-Path $backupDir 'tuning-backup.json'
$legacyBackupFile = Join-Path ([IO.Path]::GetDirectoryName($env:WINDOW_TWEAKS_BATCH)) 'tuning-backup.json'

$desktop  = 'Control Panel\Desktop'
$mouse    = 'Control Panel\Mouse'
$metrics  = 'Control Panel\Desktop\WindowMetrics'
$explorerPath = 'Software\Microsoft\Windows\CurrentVersion\Explorer'
$advanced = "$explorerPath\Advanced"
$personal = 'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
$dwm      = 'Software\Microsoft\Windows\DWM'

# The required fields are shared with the original, unversioned backup format.
$settings = [ordered]@{
    UserPreferencesMask = @($desktop,  'Binary')
    DragFullWindows     = @($desktop,  'String')
    MenuShowDelay       = @($desktop,  'String')
    MouseHoverTime      = @($mouse,    'String')
    MinAnimate          = @($metrics,  'String')
    EnableTransparency  = @($personal, 'DWord')
    TaskbarAnimations   = @($advanced, 'DWord')
    ListviewAlphaSelect = @($advanced, 'DWord')
    ListviewShadow      = @($advanced, 'DWord')
    EnableAeroPeek      = @($dwm,      'DWord')
    LaunchTo            = @($advanced, 'DWord')
    SeparateProcess     = @($advanced, 'DWord')
    ShowRecent          = @($explorerPath, 'DWord')
    ShowFrequent        = @($explorerPath, 'DWord')
    IconsOnly           = @($advanced, 'DWord')
    FontSmoothing       = @($desktop,  'String')
    CursorBlinkRate     = @($desktop,  'String')
    CaretWidth          = @($desktop,  'DWord')
}
$displayFields = @('IconsOnly', 'FontSmoothing')
$delayFields = @('MenuShowDelay', 'MouseHoverTime')
$legacyCaretFields = @('CursorBlinkRate', 'CaretWidth')
$requiredFields = @($settings.Keys | Where-Object { $_ -notin ($displayFields + $delayFields + $legacyCaretFields) })

function Read-TuningBackup([string]$path) {
    $json = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    # Windows PowerShell can unwrap a one-element JSON array into its element.
    if ($json -notmatch '^\s*\{') { throw "Invalid Windows tuning backup '$path'. Expected a JSON object." }
    $backup = ConvertFrom-Json -InputObject $json
    $fields = @($backup.PSObject.Properties.Name)
    $expected = $requiredFields + @('Created', 'Computer')
    if ('SchemaVersion' -in $fields) {
        if ($backup.SchemaVersion -isnot [int] -or $backup.SchemaVersion -ne 1) {
            throw "Unsupported Windows tuning backup version in '$path'."
        }
        $expected += @('SchemaVersion') + $displayFields + $delayFields
    } else {
        # These pairs were added together. A missing member of a pair is incomplete.
        if (@($displayFields | Where-Object { $_ -in $fields }).Count -gt 0) {
            $expected += $displayFields
        }
        if (@($delayFields | Where-Object { $_ -in $fields }).Count -gt 0) {
            $expected += $delayFields
        }
        if (@($legacyCaretFields | Where-Object { $_ -in $fields }).Count -gt 0) {
            $expected += $legacyCaretFields
        }
    }
    foreach ($field in $expected) {
        if ($field -cnotin $fields) { throw "Incomplete Windows tuning backup '$path'. Missing '$field'." }
    }
    foreach ($field in $fields) {
        if ($field -cnotin $expected) { throw "Unexpected field '$field' in Windows tuning backup '$path'." }
    }
    $created = [DateTime]::MinValue
    if (($backup.Created -isnot [datetime] -and -not [DateTime]::TryParseExact(
            [string]$backup.Created, 's', [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::None, [ref]$created)) -or
        $backup.Computer -isnot [string] -or [string]::IsNullOrWhiteSpace($backup.Computer)) {
        throw "Invalid snapshot metadata in Windows tuning backup '$path'."
    }
    foreach ($field in $settings.Keys) {
        if ($field -notin $fields) { continue }
        $value = $backup.$field
        # Explicit JSON null records a registry value that was absent at snapshot time.
        if ($null -eq $value) { continue }
        $valid = switch ($settings[$field][1]) {
            'Binary' { $value -is [string] -and $value -match '^(?:[0-9a-f]{2}(?: [0-9a-f]{2})*)?\z' }
            'String' { $value -is [string] -and -not $value.Contains([char]0) }
            'DWord'  { ($value -is [int] -or $value -is [long]) -and $value -ge [int]::MinValue -and $value -le [int]::MaxValue }
        }
        if (-not $valid) { throw "Invalid value for '$field' in Windows tuning backup '$path'." }
    }
    return $backup
}

function Set-Tuning([string]$name, $value) {
    $path, $kind = $settings[$name]
    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($path)
    try {
        $key.SetValue($name, $value, [Microsoft.Win32.RegistryValueKind]$kind)
    } finally {
        $key.Dispose()
    }
}

function Assert-Spi([bool]$success, [string]$setting) {
    if (-not $success) { throw "Windows could not apply '$setting' through SystemParametersInfo." }
}

function Invoke-WithTuningLock([scriptblock]$action) {
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $mutex = [Threading.Mutex]::new($false, "Global\WindowTweaks.WindowsTuning.$sid")
    $locked = $false
    try {
        try {
            $locked = $mutex.WaitOne([TimeSpan]::FromSeconds(30))
        } catch [Threading.AbandonedMutexException] {
            $locked = $true
        }
        if (-not $locked) { throw 'Another Windows tuning operation is in progress.' }
        & $action
    } finally {
        if ($locked) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

function Initialize-TuningApi {
    if ('WtTuningNative' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class WtTuningNative {
    [DllImport("user32.dll", EntryPoint = "SystemParametersInfoW")]
    public static extern bool SystemParametersInfo(uint action, uint param, IntPtr value, uint flags);

    [DllImport("user32.dll", EntryPoint = "SystemParametersInfoW")]
    public static extern bool SystemParametersInfo(uint action, uint param, ref ANIMATIONINFO value, uint flags);

    [DllImport("shell32.dll")]
    public static extern void SHChangeNotify(int eventId, uint flags, IntPtr first, IntPtr second);

    [StructLayout(LayoutKind.Sequential)]
    public struct ANIMATIONINFO {
        public uint cbSize;
        public int iMinAnimate;
    }
}
'@
}

function Update-Explorer {
    # SHCNE_ASSOCCHANGED, SHCNF_IDLIST
    [WtTuningNative]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)
}

function Get-TuningValue([string]$name) {
    $path, $kind = $settings[$name]
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($path)
    if ($null -eq $key) { return $null }
    try {
        if ($name -notin $key.GetValueNames()) { return $null }
        if ($key.GetValueKind($name) -ne [Microsoft.Win32.RegistryValueKind]$kind) {
            throw "Cannot back up '$name' because its registry type is not $kind."
        }
        $value = $key.GetValue($name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        if ($null -eq $value) { throw "Cannot read '$name' for the Windows tuning backup." }
        if ($kind -eq 'Binary') { return [BitConverter]::ToString($value).Replace('-', ' ') }
        return $value
    } finally {
        $key.Dispose()
    }
}

function Save-TuningBackup {
    $backup = [ordered]@{
        SchemaVersion = 1
        Created       = (Get-Date).ToString('s')
        Computer      = $env:COMPUTERNAME
    }
    foreach ($name in $settings.Keys) {
        if ($name -notin $legacyCaretFields) { $backup[$name] = Get-TuningValue $name }
    }
    [void][IO.Directory]::CreateDirectory($backupDir)
    $pending = Join-Path $backupDir ([Guid]::NewGuid().ToString() + '.tmp')
    try {
        [IO.File]::WriteAllText($pending, ($backup | ConvertTo-Json), [Text.Encoding]::UTF8)
        $snapshot = Read-TuningBackup $pending
        # Publishing by same-directory rename prevents readers from seeing a partial snapshot.
        [IO.File]::Move($pending, $backupFile)
        return $snapshot
    } finally {
        [IO.File]::Delete($pending)
    }
}

function Say($message, $colour = 'Green') {
    Write-Host "  $message" -ForegroundColor $colour
}

Write-Host "`nWindow Tweaks - Windows tuning" -ForegroundColor Cyan
Invoke-WithTuningLock {
    if (Test-Path -LiteralPath $backupFile) {
        $snapshot = Read-TuningBackup $backupFile
        Say "Using the existing backup at '$backupFile'." 'DarkGray'
    } elseif (Test-Path -LiteralPath $legacyBackupFile) {
        $snapshot = Read-TuningBackup $legacyBackupFile
        Say "Using the original backup at '$legacyBackupFile'." 'DarkGray'
    } else {
        $snapshot = Save-TuningBackup
        Say "Saved your current values to '$backupFile'." 'DarkGray'
    }

    Initialize-TuningApi
    if ($Animations -or $MinimalAnimations) {
        if ($Animations) { Write-Host "`n[Animations]" -ForegroundColor Cyan }
        else { Write-Host "`n[Minimal Animations]" -ForegroundColor Cyan }

        $spif = 3  # SPIF_UPDATEINIFILE | SPIF_SENDCHANGE
        Assert-Spi ([WtTuningNative]::SystemParametersInfo(0x0025, 1, [IntPtr]::Zero, $spif)) 'DragFullWindows'
        Set-Tuning 'DragFullWindows' '1'
        Say 'Show window contents while dragging (required by the glide)'

        if ('MenuShowDelay' -in $snapshot.PSObject.Properties.Name) {
            Set-Tuning 'MenuShowDelay' '50'
            Set-Tuning 'MouseHoverTime' '100'
            Say 'Reduce menu and mouse-hover delays'
        } else {
            Say 'Keeping current menu and mouse-hover delays because the legacy backup predates them.' 'DarkGray'
        }

        $animation = New-Object WtTuningNative+ANIMATIONINFO
        $animation.cbSize = [Runtime.InteropServices.Marshal]::SizeOf($animation)
        $animation.iMinAnimate = 1
        Assert-Spi ([WtTuningNative]::SystemParametersInfo(0x0049, $animation.cbSize, [ref]$animation, $spif)) 'MinAnimate'
        Say 'Animate windows when minimizing and maximizing'

        if ($Animations) {
            $effects = [ordered]@{
                'UI effects'                          = 0x103F  # SPI_SETUIEFFECTS
                'Fade or slide menus into view'       = 0x1003  # SPI_SETMENUANIMATION
                'Slide open combo boxes'              = 0x1005  # SPI_SETCOMBOBOXANIMATION
                'Smooth-scroll list boxes'            = 0x1007  # SPI_SETLISTBOXSMOOTHSCROLLING
                'Fade out menu items after clicking'  = 0x1015  # SPI_SETSELECTIONFADE
                'Fade or slide ToolTips into view'    = 0x1017  # SPI_SETTOOLTIPANIMATION
                'Show shadows under windows'         = 0x1025  # SPI_SETDROPSHADOW
                'Animate controls inside windows'     = 0x1043  # SPI_SETCLIENTAREAANIMATION
            }
            foreach ($name in $effects.Keys) {
                Assert-Spi ([WtTuningNative]::SystemParametersInfo($effects[$name], 0, [IntPtr]1, $spif)) $name
                Say $name
            }

            Set-Tuning 'TaskbarAnimations' 1
            Set-Tuning 'ListviewAlphaSelect' 1
            Set-Tuning 'ListviewShadow' 1
            Set-Tuning 'EnableTransparency' 1
            Set-Tuning 'EnableAeroPeek' 1
            Say 'Taskbar animations, translucent selection rectangles, icon label shadows, transparency, and Aero Peek enabled'

            if ('IconsOnly' -in $snapshot.PSObject.Properties.Name) {
                Set-Tuning 'IconsOnly' 0
                Set-Tuning 'FontSmoothing' '2'
                Say 'Thumbnails and font smoothing enabled'
            } else {
                Say 'Keeping current thumbnail and font smoothing settings because the legacy backup predates them.' 'DarkGray'
            }
        }
    }

    if ($Explorer) {
        Write-Host "`n[Explorer]" -ForegroundColor Cyan
        Set-Tuning 'LaunchTo' 1
        Set-Tuning 'SeparateProcess' 1
        Set-Tuning 'ShowRecent' 0
        Set-Tuning 'ShowFrequent' 0
        Say 'Open File Explorer to This PC'
        Say 'Run folder windows in a separate process'
        Say 'Hide recent and frequent files from Quick Access'
    }

    Update-Explorer
    $snap = Get-ItemPropertyValue -LiteralPath "HKCU:\$desktop" -Name WindowArrangementActive -ErrorAction SilentlyContinue
    if ($snap -eq 1) {
        Say "Windows Snap is on and takes priority at screen edges. See docs\ANIMATIONS.md." 'Yellow'
    }
    Write-Host "`nDone. Restart Explorer or sign out for all changes to take effect.`n" -ForegroundColor Green
}
