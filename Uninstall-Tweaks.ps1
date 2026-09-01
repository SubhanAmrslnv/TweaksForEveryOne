<#
.SYNOPSIS
    Uninstalls Window Tweaks (the C# / .NET build).

.DESCRIPTION
    Removes everything Install-Tweaks.ps1 creates, and nothing else:
      - stops the running process
      - removes the Startup shortcut from BOTH possible locations
      - removes %ProgramFiles%\WindowTweaks
      - optionally removes the per-user settings in %APPDATA%\WindowTweaks

    Settings are KEPT by default. Uninstalling and reinstalling is a normal thing to do, and
    silently discarding a configuration the user spent time on is not a decision this script gets
    to make. Pass -RemoveSettings to delete them.

.PARAMETER RemoveSettings
    Also delete %APPDATA%\WindowTweaks (settings.json and window-positions.json).

.PARAMETER Silent
    No prompts and no Pause at the end. For unattended use.

.EXAMPLE
    .\Uninstall-Tweaks.ps1
    .\Uninstall-Tweaks.ps1 -RemoveSettings -Silent
#>
param (
    [switch]$RemoveSettings,
    [switch]$Silent
)

$ErrorActionPreference = 'Continue'

# --- 1. Require admin -------------------------------------------------------------------------
# The install directory is under %ProgramFiles%, so removing it needs elevation. Re-launch
# ourselves elevated and forward the switches rather than failing halfway through.
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Requesting administrative privileges..."

    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    if ($RemoveSettings) { $argList += '-RemoveSettings' }
    if ($Silent) { $argList += '-Silent' }

    Start-Process powershell -ArgumentList $argList -Verb RunAs
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

$InstallDir     = Join-Path $env:ProgramFiles 'WindowTweaks'
$StartupFolder  = [Environment]::GetFolderPath('Startup')
$ShortcutPath   = Join-Path $StartupFolder 'WindowTweaks.lnk'
$SettingsDir    = Join-Path $env:APPDATA 'WindowTweaks'

Write-Host ""
Write-Host "Uninstalling Window Tweaks" -ForegroundColor Cyan
Write-Host "--------------------------"

# --- 2. Stop the running app ------------------------------------------------------------------
Stop-WindowTweaks

# --- 3. Startup shortcut ----------------------------------------------------------------------
# Two places create this shortcut with the same name and target: the installer, and the app's own
# "Start with Windows" toggle. Removing the path is enough for both, but check the all-users
# Startup folder too in case an older build wrote there.
$removedShortcut = $false
foreach ($lnk in @($ShortcutPath, (Join-Path ([Environment]::GetFolderPath('CommonStartup')) 'WindowTweaks.lnk'))) {
    if (Test-Path $lnk) {
        Remove-Item $lnk -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path $lnk)) {
            Write-Host "Removed startup shortcut: $lnk" -ForegroundColor Green
            $removedShortcut = $true
        }
    }
}
if (-not $removedShortcut) { Write-Host "No startup shortcut found." }

# --- 4. Install directory ---------------------------------------------------------------------
# This is an ELEVATED recursive force-delete, so it verifies the target is actually our install
# before touching it. $env:ProgramFiles is inherited from the environment; if it were empty or
# pointed somewhere else, an unguarded Remove-Item -Recurse -Force here would take out whatever
# tree it happened to name. Requiring our own executable in the directory makes that impossible.
$looksLikeOurs = (Test-Path $InstallDir) -and (Test-Path (Join-Path $InstallDir 'WindowTweaks.exe'))

if ((Test-Path $InstallDir) -and -not $looksLikeOurs) {
    Write-Host "Refusing to delete $InstallDir - it does not contain WindowTweaks.exe." -ForegroundColor Red
    Write-Host "Remove it by hand if you are sure it is ours." -ForegroundColor Yellow
}
elseif ($looksLikeOurs) {
    Write-Host "Removing $InstallDir..."
    Remove-Item $InstallDir -Recurse -Force -ErrorAction SilentlyContinue

    if (Test-Path $InstallDir) {
        Write-Host "  could not remove it. A file is probably still locked - reboot and run this again." -ForegroundColor Red
    } else {
        Write-Host "  removed." -ForegroundColor Green
    }
}
else {
    Write-Host "$InstallDir does not exist."
}

# --- 5. Settings ------------------------------------------------------------------------------
if ($RemoveSettings) {
    if (Test-Path $SettingsDir) {
        Remove-Item $SettingsDir -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path $SettingsDir) {
            Write-Host "Could not remove $SettingsDir." -ForegroundColor Red
        } else {
            Write-Host "Removed settings: $SettingsDir" -ForegroundColor Green
        }
    } else {
        Write-Host "No settings directory to remove."
    }
} elseif (Test-Path $SettingsDir) {
    Write-Host ""
    Write-Host "Settings kept at $SettingsDir" -ForegroundColor Yellow
    Write-Host "Re-run with -RemoveSettings to delete them as well."
}

# --- 6. What this deliberately does NOT do ----------------------------------------------------
# DragFullWindows is left as it is. The app can turn that Windows setting ON at startup (snapping
# and parallax cannot measure drag speed without it), but it is a system-wide preference that the
# user may well have wanted anyway, and an uninstaller silently changing display behaviour on the
# way out would be worse than leaving it.

Write-Host ""
Write-Host "Uninstall complete." -ForegroundColor Cyan
Write-Host ""

if (-not $Silent) { Pause }
