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

# --- Graceful stop helper ---------------------------------------------------------------------
# The app is a tray app with NO VISIBLE WINDOW, and that breaks the usual polite-stop routes:
# taskkill without /F and .CloseMainWindow() both only target VISIBLE top-level windows, so
# neither reaches it (verified - taskkill reports success and the process keeps running). The app
# does answer WM_CLOSE on a hidden message-only window, so post it to every top-level window the
# process owns.
#
# This matters beyond tidiness: a forced kill skips the app's exit path, which is what flushes
# settings AND undoes what it did to other applications' windows - opacity applied to them,
# windows hidden to the tray with no icon left to restore them, windows parented to the desktop.
Add-Type -ErrorAction SilentlyContinue -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class WtWindows {
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr p);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    delegate bool EnumProc(IntPtr h, IntPtr p);
    public static int CloseAll(uint targetPid) {
        int n = 0;
        var handles = new List<IntPtr>();
        EnumWindows((h, p) => {
            uint pid; GetWindowThreadProcessId(h, out pid);
            if (pid == targetPid) handles.Add(h);
            return true;
        }, IntPtr.Zero);
        foreach (var h in handles) { if (PostMessage(h, 0x0010 /* WM_CLOSE */, IntPtr.Zero, IntPtr.Zero)) n++; }
        return n;
    }
}
'@

function Stop-WindowTweaks {
    param([int]$TimeoutSeconds = 6)

    $procs = Get-Process WindowTweaks -ErrorAction SilentlyContinue
    if (-not $procs) {
        Write-Host "Not running."
        return
    }

    Write-Host "Stopping WindowTweaks..."
    foreach ($p in $procs) {
        try { [void][WtWindows]::CloseAll($p.Id) } catch { }
    }

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (-not (Get-Process WindowTweaks -ErrorAction SilentlyContinue)) { break }
        Start-Sleep -Milliseconds 200
    }

    $left = Get-Process WindowTweaks -ErrorAction SilentlyContinue
    if ($left) {
        Write-Host "  did not exit in time; forcing. Settings may not have been saved." -ForegroundColor Yellow
        $left | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 400
    } else {
        Write-Host "  stopped cleanly." -ForegroundColor Green
    }
}

$InstallDir = "$env:ProgramFiles\WindowTweaks"
$StartupFolder = [Environment]::GetFolderPath('Startup')
$ShortcutPath = "$StartupFolder\WindowTweaks.lnk"

if ($Uninstall) {
    Write-Host "Uninstalling Window Tweaks..."
    
    # Stop the process politely; see Stop-WindowTweaks.
    Stop-WindowTweaks
    
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
# Ask it to exit rather than killing it: a forced kill skips the app's exit path, which is what
# flushes settings and undoes the opacity, tray-hiding and re-parenting it applied to other
# applications' windows. Reinstalling over a running copy should not cost the user their config.
Stop-WindowTweaks

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
