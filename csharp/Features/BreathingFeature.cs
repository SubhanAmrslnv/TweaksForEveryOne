using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Text;
using System.Windows.Threading;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

/// <summary>
/// Breathing windows: a background window slowly fades once it has been idle, and wakes instantly
/// when it is focused or the cursor lands on it.
///
/// Opacity goes through AlphaCompositor as the "breathe" layer rather than being written directly.
/// That is what makes this effect compose with the transparency wheel: a window the user set to 50%
/// by hand now breathes between 50% and 50%*DimFactor, instead of being dragged to an absolute
/// value and then reset to fully opaque - which silently discarded the user's setting.
///
/// The old direct write also deliberately kept WS_EX_LAYERED on restore, because removing it caused
/// black flicker in apps that set it themselves. That knowledge now lives in AlphaCompositor, which
/// strips the style only when it was the one that added it.
/// </summary>
public class BreathingFeature : IDisposable
{
    /// <summary>
    /// Read once per tick, not per window: TickCore loops over every top-level window and a settings
    /// read takes a lock and parses a string. The default 47% matches the previous absolute dim of
    /// 120/255, so the effect looks unchanged until the user moves it.
    /// </summary>
    private int _idleMs;
    private double _dimFactor;

    private readonly DispatcherTimer _timer;
    private readonly Dictionary<IntPtr, DateTime> _lastActive = new();
    private readonly HashSet<IntPtr> _dimmed = new();

    public bool IsEnabled { get; private set; }

    public BreathingFeature()
    {
        _timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(200) };
        _timer.Tick += Timer_Tick;
    }

    public void SetEnabled(bool enabled)
    {
        if (enabled == IsEnabled) return;
        IsEnabled = enabled;

        if (enabled)
        {
            _lastActive.Clear();
            _dimmed.Clear();
            _timer.Start();
            Debug.WriteLine("Breathing Windows: Enabled");
        }
        else
        {
            _timer.Stop();
            RestoreAllWindows();
            _lastActive.Clear();
            Debug.WriteLine("Breathing Windows: Disabled");
        }
    }

    public void Toggle() => SetEnabled(!IsEnabled);

    private void Timer_Tick(object? sender, EventArgs e)
    {
        // The flag is tested inside the tick, not only at the call site: a feature that owns state
        // on other people's windows has to be able to clean up even if it is being switched off.
        if (!IsEnabled)
        {
            _timer.Stop();
            RestoreAllWindows();
            return;
        }

        try
        {
            _idleMs = TuningRegistry.Int(TuningRegistry.BreathingIdleSeconds) * 1000;
            _dimFactor = TuningRegistry.Fraction(TuningRegistry.BreathingDimPercent);
            TickCore();
        }
        catch (Exception ex)
        {
            // An exception escaping a timer callback kills the timer, and the feature would be dead
            // for the rest of the session with no visible cause.
            Debug.WriteLine("Breathing tick failed: " + ex.Message);
        }
    }

    private void TickCore()
    {
        IntPtr fgHwnd = NativeMethods.GetForegroundWindow();
        NativeMethods.GetCursorPos(out NativeMethods.POINT pt);
        IntPtr mouseHwnd = NativeMethods.GetAncestor(NativeMethods.WindowFromPoint(pt), NativeMethods.GA_ROOT);

        DateTime now = DateTime.Now;
        HashSet<IntPtr> aliveThisTick = new();

        NativeMethods.EnumWindows((hwnd, _) =>
        {
            if (!NativeMethods.IsWindowVisible(hwnd)) return true;

            StringBuilder sb = new(256);
            NativeMethods.GetClassName(hwnd, sb, sb.Capacity);
            string cls = sb.ToString();
            if (cls is "Shell_TrayWnd" or "Progman" or "WorkerW" or "Shell_SecondaryTrayWnd") return true;

            aliveThisTick.Add(hwnd);

            if (hwnd == fgHwnd || hwnd == mouseHwnd)
            {
                _lastActive[hwnd] = now;
                if (_dimmed.Remove(hwnd))
                    AlphaCompositor.ClearLayer(hwnd, AlphaCompositor.LayerBreathe);
                return true;
            }

            if (!_lastActive.ContainsKey(hwnd)) _lastActive[hwnd] = now;

            if ((now - _lastActive[hwnd]).TotalMilliseconds > _idleMs && _dimmed.Add(hwnd))
                AlphaCompositor.SetLayer(hwnd, AlphaCompositor.LayerBreathe, _dimFactor);

            return true;
        }, IntPtr.Zero);

        // Collect then delete: removing entries while enumerating shifts the remainder under the
        // enumerator and silently skips the next one.
        List<IntPtr>? gone = null;
        foreach (IntPtr key in _lastActive.Keys)
        {
            if (!aliveThisTick.Contains(key)) (gone ??= new List<IntPtr>()).Add(key);
        }

        if (gone == null) return;
        foreach (IntPtr key in gone)
        {
            _lastActive.Remove(key);
            _dimmed.Remove(key);
            // The window is gone, so there is nothing to restore - just drop its record so we do
            // not hold state against a handle Windows may reissue.
            AlphaCompositor.Forget(key);
        }
    }

    private void RestoreAllWindows()
    {
        foreach (IntPtr hwnd in new List<IntPtr>(_dimmed))
        {
            AlphaCompositor.ClearLayer(hwnd, AlphaCompositor.LayerBreathe);
        }
        _dimmed.Clear();
    }

    public void Dispose()
    {
        _timer.Stop();
        IsEnabled = false;
        RestoreAllWindows();
    }
}
