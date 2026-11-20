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
    Restores the Windows settings backed up by Apply-Windows-Tuning.bat.

.DESCRIPTION
    Validates the entire snapshot before restoring its registry values.
    Sign out and back in to reload the original visual effects.
    The backup is retained for verification or retry.

.PARAMETER BackupFile
    Uses an explicit snapshot. Otherwise searches LocalAppData, then the script directory.
#>
[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$BackupFile
)

$ErrorActionPreference = 'Stop'

$desktop  = 'Control Panel\Desktop'
$mouse    = 'Control Panel\Mouse'
$metrics  = 'Control Panel\Desktop\WindowMetrics'
$explorer = 'Software\Microsoft\Windows\CurrentVersion\Explorer'
$advanced = "$explorer\Advanced"
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
    ShowRecent          = @($explorer, 'DWord')
    ShowFrequent        = @($explorer, 'DWord')
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

function Restore-TuningValue([string]$name, $value) {
    $path, $kind = $settings[$name]
    if ($null -eq $value) {
        $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($path, $true)
        if ($null -eq $key) { return }
        try {
            $key.DeleteValue($name, $false)
        } finally {
            $key.Dispose()
        }
        return
    }
    if ($kind -eq 'Binary') {
        $value = [byte[]]@(if ($value.Length -gt 0) {
            foreach ($octet in ($value -split ' ')) { [Convert]::ToByte($octet, 16) }
        })
    }
    Set-Tuning $name $value
}

Invoke-WithTuningLock {
    if (-not $BackupFile) {
        $BackupFile = Join-Path $env:LOCALAPPDATA 'Window Tweaks Backup\tuning-backup.json'
        if (-not (Test-Path -LiteralPath $BackupFile)) {
            $BackupFile = Join-Path ([IO.Path]::GetDirectoryName($env:WINDOW_TWEAKS_BATCH)) 'tuning-backup.json'
        }
    }
    if (-not (Test-Path -LiteralPath $BackupFile)) {
        throw "Windows tuning backup not found at '$BackupFile'."
    }
    $snapshot = Read-TuningBackup $BackupFile
    $fields = @($snapshot.PSObject.Properties.Name)

    Initialize-TuningApi
    Write-Host "`nRestoring Windows tuning" -ForegroundColor Cyan
    Write-Host "Backup taken $($snapshot.Created) on $($snapshot.Computer)" -ForegroundColor DarkGray

    $failures = 0
    # Refresh live drag and minimize settings when the original value is known.
    # Do not persist through SPI; the registry below receives the exact originals.
    $sendChange = 2
    if ($snapshot.DragFullWindows -in @('0', '1')) {
        try {
            Assert-Spi ([WtTuningNative]::SystemParametersInfo(0x0025, [uint32]$snapshot.DragFullWindows, [IntPtr]::Zero, $sendChange)) 'DragFullWindows'
        } catch {
            Write-Warning $_.Exception.Message
            $failures++
        }
    }
    if ($snapshot.MinAnimate -in @('0', '1')) {
        try {
            $animation = New-Object WtTuningNative+ANIMATIONINFO
            $animation.cbSize = [Runtime.InteropServices.Marshal]::SizeOf($animation)
            $animation.iMinAnimate = [int]$snapshot.MinAnimate
            Assert-Spi ([WtTuningNative]::SystemParametersInfo(0x0049, $animation.cbSize, [ref]$animation, $sendChange)) 'MinAnimate'
        } catch {
            Write-Warning $_.Exception.Message
            $failures++
        }
    }

    # Windows reloads the exact UserPreferencesMask on sign-in. Replaying
    # selected effects through SPI can change other bits in the saved mask.
    foreach ($name in $settings.Keys) {
        if ($name -notin $fields) { continue }
        try {
            Restore-TuningValue $name $snapshot.$name
            Write-Host "  Restored $name"
        } catch {
            Write-Warning "Could not restore '$name'. $($_.Exception.Message)"
            $failures++
        }
    }
    Update-Explorer
    if ($failures -gt 0) {
        throw "$failures Windows tuning restore operation(s) failed. The backup is available at '$BackupFile'."
    }
    Write-Host "`nDone. Sign out and back in to reload the original visual effects.`n" -ForegroundColor Green
}
