<#
.SYNOPSIS
    Builds WindowTweaksSetup.exe - the whole project as one file.

.DESCRIPTION
    Embeds every file the program needs as a manifest resource inside a small
    WinForms installer, then compiles it with the csc.exe that ships with the
    .NET Framework. That compiler is present on every Windows 11 machine, so
    this builds anywhere with no downloads and no SDK.

    Output: build\out\WindowTweaksSetup.exe

.NOTES
    The resulting .exe is unsigned. Windows SmartScreen will warn the first
    few times anyone downloads it ("More info" -> "Run anyway"). Signing needs
    a paid code-signing certificate; there is no free way around it.
#>
[CmdletBinding()]
param(
    [string]$OutputName = 'WindowTweaksSetup.exe'
)

$ErrorActionPreference = 'Stop'

$repo    = Split-Path $PSScriptRoot -Parent
$outDir  = Join-Path $PSScriptRoot 'out'
$stage   = Join-Path $PSScriptRoot 'obj'
$exePath = Join-Path $outDir $OutputName

Write-Host "`nBuilding Window Tweaks installer" -ForegroundColor Cyan
Write-Host "Repo: $repo`n" -ForegroundColor DarkGray

# ------------------------------------------------------------- compiler ----
$csc = Get-ChildItem "$env:WINDIR\Microsoft.NET\Framework64" -Filter 'csc.exe' -Recurse -ErrorAction SilentlyContinue |
       Sort-Object FullName | Select-Object -Last 1
if (-not $csc) {
    $csc = Get-ChildItem "$env:WINDIR\Microsoft.NET\Framework" -Filter 'csc.exe' -Recurse -ErrorAction SilentlyContinue |
           Sort-Object FullName | Select-Object -Last 1
}
if (-not $csc) { throw "No csc.exe found. The .NET Framework should ship one with Windows." }
Write-Host "  Compiler: $($csc.FullName)" -ForegroundColor DarkGray

# --------------------------------------------------------------- staging ----
# Resource names cannot contain a path separator, so a subfolder is encoded
# with an underscore and Setup.cs turns it back into a backslash on extract.
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage  -Force | Out-Null
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

$payload = @(
    @{ From = 'src\WindowTweaks.ahk';                Res = 'WindowTweaks.ahk' }
    @{ From = 'src\SnapCore.ahk';                    Res = 'SnapCore.ahk' }
    @{ From = 'src\TaskbarCore.ahk';                 Res = 'TaskbarCore.ahk' }
    @{ From = 'docs\GUIDE.md';                       Res = 'GUIDE.md' }
    @{ From = 'docs\HOTKEYS.md';                     Res = 'HOTKEYS.md' }
    @{ From = 'docs\ANIMATIONS.md';                  Res = 'ANIMATIONS.md' }
    @{ From = 'docs\WINDOWS-TUNING.md';              Res = 'WINDOWS-TUNING.md' }
    @{ From = 'docs\TASKBAR-AND-INTERNALS.md';       Res = 'TASKBAR-AND-INTERNALS.md' }
    @{ From = 'Uninstall.ps1';                       Res = 'Uninstall.ps1' }
    @{ From = 'scripts\Apply-Windows-Tuning.ps1';    Res = 'scripts_Apply-Windows-Tuning.ps1' }
    @{ From = 'scripts\Restore-Windows-Tuning.ps1';  Res = 'scripts_Restore-Windows-Tuning.ps1' }
    @{ From = 'assets\WindowTweaks.ico';             Res = 'WindowTweaks.ico' }
)

$resArgs = @()
foreach ($p in $payload) {
    $srcFile = Join-Path $repo $p.From
    if (-not (Test-Path $srcFile)) { throw "Missing payload file: $($p.From)" }
    $staged = Join-Path $stage $p.Res
    Copy-Item $srcFile $staged -Force
    # /resource:<file>,<name>  ->  name is what Setup.cs looks for
    $resArgs += '/resource:"{0}",res.{1}' -f $staged, $p.Res
}
Write-Host "  Embedding $($payload.Count) files" -ForegroundColor DarkGray

# --------------------------------------------------------------- compile ----
$cscArgs = @(
    '/target:winexe'
    '/optimize+'
    '/nologo'
    "/out:`"$exePath`""
    '/reference:System.dll'
    '/reference:System.Drawing.dll'
    '/reference:System.Windows.Forms.dll'
    '/reference:System.Management.dll'
)
$icoPath = Join-Path $repo 'assets\WindowTweaks.ico'
if (Test-Path $icoPath) { $cscArgs += "/win32icon:`"$icoPath`"" }
$cscArgs += $resArgs
$cscArgs += "`"$(Join-Path $PSScriptRoot 'Setup.cs')`""

$argFile = Join-Path $stage 'csc.rsp'
[System.IO.File]::WriteAllText($argFile, ($cscArgs -join "`r`n"))

$log = & cmd.exe /c "`"$($csc.FullName)`" `"@$argFile`" 2>&1" | Out-String
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $exePath)) {
    Write-Host "`nCompile failed:" -ForegroundColor Red
    Write-Host $log -ForegroundColor Red
    throw "Build failed."
}
if ($log.Trim()) { Write-Host $log.Trim() -ForegroundColor Yellow }

$size = [math]::Round((Get-Item $exePath).Length / 1KB, 1)
Write-Host "`n  Built: $exePath  ($size KB)" -ForegroundColor Green
Write-Host @"

  Give anyone that single file. Running it will:
    - install AutoHotkey v2 if they don't have it
    - unpack the program to %LOCALAPPDATA%\Window Tweaks
    - make Start Menu / Desktop / Startup shortcuts
    - optionally apply the Windows tuning

  It is unsigned, so SmartScreen will warn on first download.

"@ -ForegroundColor Gray
