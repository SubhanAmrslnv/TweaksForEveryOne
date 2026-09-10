using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Windows.Threading;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

/// <summary>
/// Privacy Blur Feature.
///
/// Automatically veils sensitive application windows (browsers, terminal sessions,
/// password vaults, chat clients) with an opaque frosted privacy layer via AlphaCompositor
/// the instant they lose foreground focus.
/// </summary>
public class PrivacyBlurFeature : IDisposable
{
    private static readonly HashSet<string> SensitiveProcesses = new(StringComparer.OrdinalIgnoreCase)
    {
        "chrome", "firefox", "msedge", "brave", "opera",
        "slack", "discord", "telegram", "teams", "signal",
        "windowsterminal", "cmd", "powershell", "pwsh",
        "keepass", "1password", "bitwarden"
    };

    private DispatcherTimer? _pollTimer;
    private IntPtr _lastForeground;
    private readonly HashSet<IntPtr> _veiledWindows = new();

    public bool IsEnabled { get; private set; }

    public void SetEnabled(bool enabled)
    {
        if (enabled == IsEnabled) return;
        IsEnabled = enabled;
        if (enabled) Start();
        else Stop();
    }
    
    public void Toggle() => SetEnabled(!IsEnabled);

    private void Start()
    {
        _pollTimer = new DispatcherTimer(DispatcherPriority.Background)
        {
            Interval = TimeSpan.FromMilliseconds(100)
        };
        _pollTimer.Tick += OnPollTick;
        _pollTimer.Start();
    }

    private void OnPollTick(object? sender, EventArgs e)
    {
        IntPtr fg = NativeMethods.GetForegroundWindow();
        if (fg == _lastForeground) return;
        _lastForeground = fg;

        // If newly focused window was veiled, unveil it immediately
        if (fg != IntPtr.Zero && _veiledWindows.Remove(fg))
        {
            AlphaCompositor.ClearLayer(fg, "privacy");
        }

        // Check background windows for sensitive processes
        NativeMethods.EnumWindows((hwnd, _) =>
        {
            if (hwnd == fg) return true;
            if (!WindowFilter.IsOrdinaryAppWindow(hwnd)) return true;

            string procName = ProcessNameCache.ForWindow(hwnd);
            if (SensitiveProcesses.Contains(procName))
            {
                AlphaCompositor.SetLayer(hwnd, "privacy", 0.22);
                _veiledWindows.Add(hwnd);
            }

            return true;
        }, IntPtr.Zero);
    }

    private void Stop()
    {
        _pollTimer?.Stop();
        _pollTimer = null;

        foreach (IntPtr hwnd in _veiledWindows)
        {
            AlphaCompositor.ClearLayer(hwnd, "privacy");
        }
        _veiledWindows.Clear();
        _lastForeground = IntPtr.Zero;
    }

    public void Dispose()
    {
        SetEnabled(false);
    }
}
