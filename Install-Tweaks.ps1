param (
    [switch]$Uninstall
)

# 1. Require Admin
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Requesting administrative privileges..."
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" $(if ($Uninstall) { '-Uninstall' })" -Verb RunAs
    exit
}

$InstallDir = "$env:ProgramFiles\WindowTweaks"
$StartupFolder = [Environment]::GetFolderPath('Startup')
$ShortcutPath = "$StartupFolder\WindowTweaks.lnk"

if ($Uninstall) {
    Write-Host "Uninstalling Window Tweaks..."
    
    # Kill process if running
    Get-Process WindowTweaks -ErrorAction SilentlyContinue | Stop-Process -Force
    
    # Remove Startup shortcut
    if (Test-Path $ShortcutPath) { Remove-Item $ShortcutPath -Force }
    
    # Remove Program Files directory
    if (Test-Path $InstallDir) { 
        Remove-Item $InstallDir -Recurse -Force 
    }
    
    Write-Host "Uninstalled successfully."
    Pause
    exit
}

Write-Host "Building and installing Window Tweaks..."

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ProjDir = Join-Path $ScriptDir "csharp"

if (-not (Test-Path (Join-Path $ProjDir "WindowTweaks.csproj"))) {
    Write-Error "Could not find csharp project at $ProjDir"
    Pause
    exit
}

# 2. Publish the C# App
Write-Host "Publishing the C# application..."
Set-Location $ProjDir
dotnet publish -c Release -r win-x64 --self-contained false -o "$ProjDir\publish"

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to build the project."
    Pause
    exit
}

# 3. Stop existing process
Get-Process WindowTweaks -ErrorAction SilentlyContinue | Stop-Process -Force

# 4. Copy to Program Files
Write-Host "Copying to $InstallDir..."
if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir | Out-Null
}
Copy-Item -Path "$ProjDir\publish\*" -Destination $InstallDir -Recurse -Force

# 5. Create Startup Shortcut
Write-Host "Creating shortcut in Startup folder..."
$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut($ShortcutPath)
$Shortcut.TargetPath = "$InstallDir\WindowTweaks.exe"
$Shortcut.WorkingDirectory = $InstallDir
$Shortcut.Description = "Window Tweaks"
$Shortcut.Save()

Write-Host "Installation Complete!"
Write-Host "Starting Window Tweaks..."
Start-Process "$InstallDir\WindowTweaks.exe"

Pause
