using System;
using System.Collections.Generic;
using System.Diagnostics;
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
///
/// THE TICK IS TWO PASSES, and the split is load-bearing. The enumeration does nothing but the cheap
/// style and class tests in WindowFilter and collects the handles that are about to change; the
/// expensive eligibility work - a window rect, a process name, an audio-session sweep - runs after
/// EnumWindows has returned. Cost is only half the reason. The other half is that a COM call on the
/// WPF UI thread can pump messages, and pumping inside an EnumWindows callback lets the dispatcher
/// re-enter and start another tick while the enumeration is still live.
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
    private bool _exemptAudio;

    private readonly DispatcherTimer _timer;
    private readonly Dictionary<IntPtr, DateTime> _lastActive = new();
    private readonly HashSet<IntPtr> _dimmed = new();

    /// <summary>
    /// One delegate for the life of the feature. A lambda passed straight to EnumWindows allocates a
    /// fresh delegate every 200 ms and has to stay rooted for the duration of the call; holding one
    /// in a field does both jobs.
    /// </summary>
    private readonly NativeMethods.EnumWindowsProc _enumProc;

    // Reused across ticks rather than reallocated. Cleared at the top of each tick.
    private readonly HashSet<IntPtr> _aliveThisTick = new();
    private readonly List<IntPtr> _candidates = new();
    private readonly List<IntPtr> _recheck = new();
    private readonly List<IntPtr> _gone = new();

    /// <summary>
    /// The parsed exclusion list, and the raw string it was parsed from. Keeping the raw string is
    /// what lets RefreshExcludeSet skip a Split and a HashSet rebuild on the ticks - almost all of
    /// them - where the setting has not changed.
    /// </summary>
    private readonly HashSet<string> _excludeSet = new(StringComparer.Ordinal);
    private string _excludeRaw = string.Empty;

    // Per-tick scratch. These are fields because the enumeration callback is a method now.
    private IntPtr _fgHwnd;
    private IntPtr _mouseHwnd;
    private DateTime _now;
    private bool _recheckDue;
    private int _tick;

    public bool IsEnabled { get; private set; }

    public BreathingFeature()
    {
        _timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(200) };
        _timer.Tick += Timer_Tick;
        _enumProc = EnumProc;
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
            _exemptAudio = TuningRegistry.Is(TuningRegistry.BreathingExemptAudio, "on");
            RefreshExcludeSet();
            TickCore();
        }
        catch (Exception ex)
        {
            // An exception escaping a timer callback kills the timer, and the feature would be dead
            // for the rest of the session with no visible cause.
            Debug.WriteLine("Breathing tick failed: " + ex.Message);
        }
    }

    /// <summary>
    /// Re-parse the exclusion list, but only when it has actually changed. One settings read per tick
    /// is the documented budget; a Split plus a HashSet rebuild five times a second is not.
    /// </summary>
    private void RefreshExcludeSet()
    {
        string raw = TuningRegistry.Text(TuningRegistry.BreathingExcludeProcesses);
        if (string.Equals(raw, _excludeRaw, StringComparison.Ordinal)) return;

        _excludeRaw = raw;
        _excludeSet.Clear();

        foreach (string part in raw.Split(','))
        {
            string name = part.Trim();
            if (name.Length == 0) continue;

            // A typed ".exe" is stripped so that both "vlc" and "VLC.exe" work, and the name is
            // lower-cased to match what ProcessNameCache returns.
            if (name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase))
                name = name.Substring(0, name.Length - 4);

            if (name.Length != 0) _excludeSet.Add(name.ToLowerInvariant());
        }
    }

    private void TickCore()
    {
        _fgHwnd = NativeMethods.GetForegroundWindow();
        NativeMethods.GetCursorPos(out NativeMethods.POINT pt);
        _mouseHwnd = NativeMethods.GetAncestor(NativeMethods.WindowFromPoint(pt), NativeMethods.GA_ROOT);

        _now = DateTime.Now;

        _aliveThisTick.Clear();
        _candidates.Clear();
        _recheck.Clear();
        _gone.Clear();

        // Already-dimmed windows are re-tested once a second rather than five times. This is the
        // path that releases a window whose video STARTED after it had already faded, and it is the
        // only reason to spend anything on a window that has already reached its resting state.
        _recheckDue = (++_tick % 5) == 0;

        NativeMethods.EnumWindows(_enumProc, IntPtr.Zero);

        // --- Pass two: everything expensive, on the handful of windows that are about to change ---

        if (_exemptAudio && (_candidates.Count > 0 || _recheck.Count > 0))
        {
            // Once per tick at most, and only when something is genuinely at stake. Outside the
            // enumeration on purpose - see the class header.
            AudioSessionMonitor.Refresh();
        }

        foreach (IntPtr hwnd in _candidates)
        {
            if (!NativeMethods.IsWindow(hwnd)) continue;

            if (IsExempt(hwnd))
            {
                // The clock is reset rather than left to run. That throttles IsExempt - the only
                // expensive predicate here - from every tick to once per idle period per window, and
                // it means a window gets a fresh full idle period once its exemption ends, which is
                // what a person expects after pausing a video.
                _lastActive[hwnd] = _now;
                continue;
            }

            if (_dimmed.Add(hwnd))
                AlphaCompositor.SetLayer(hwnd, AlphaCompositor.LayerBreathe, _dimFactor);
        }

        foreach (IntPtr hwnd in _recheck)
        {
            if (!NativeMethods.IsWindow(hwnd)) continue;
            if (!IsExempt(hwnd)) continue;

            if (_dimmed.Remove(hwnd))
                AlphaCompositor.ClearLayer(hwnd, AlphaCompositor.LayerBreathe);

            _lastActive[hwnd] = _now;
        }

        Reap();
    }

    private bool EnumProc(IntPtr hwnd, IntPtr _)
    {
        // The whole cheap gate, in one call: visible, not minimized, not ours, not a tool window,
        // not a shell surface, not cloaked onto another virtual desktop.
        if (!WindowFilter.IsOrdinaryAppWindow(hwnd)) return true;

        _aliveThisTick.Add(hwnd);

        if (hwnd == _fgHwnd || hwnd == _mouseHwnd)
        {
            _lastActive[hwnd] = _now;
            if (_dimmed.Remove(hwnd))
                AlphaCompositor.ClearLayer(hwnd, AlphaCompositor.LayerBreathe);
            return true;
        }

        if (_dimmed.Contains(hwnd))
        {
            if (_recheckDue) _recheck.Add(hwnd);
            return true;
        }

        if (!_lastActive.TryGetValue(hwnd, out DateTime last))
        {
            _lastActive[hwnd] = _now;
            return true;
        }

        // Decided, not dimmed. Pass two takes it from here.
        if ((_now - last).TotalMilliseconds > _idleMs) _candidates.Add(hwnd);

        return true;
    }

    /// <summary>
    /// Whether this window must be left alone.
    ///
    /// This is the eligibility decision, taken BEFORE the window is touched, which is the rule
    /// AlphaCompositor's header states and this feature previously never honoured: "Never make a
    /// foreign window layered speculatively ... can break exclusive full-screen presentation."
    ///
    /// Ordered by cost. The two style getters behind Picture-in-Picture come first, then the window
    /// rect behind the fullscreen test, and only then anything that has to name a process - and that
    /// last group is skipped outright when there is nothing it could match.
    /// </summary>
    private bool IsExempt(IntPtr hwnd)
    {
        try
        {
            if (WindowFilter.IsPictureInPicture(hwnd)) return true;
            if (WindowFilter.IsFullScreenOnItsMonitor(hwnd)) return true;

            // The O(1) "could anything match?" gate: with no exclusion list and no audio exemption
            // there is no reason to name the process at all.
            if (_excludeSet.Count == 0 && !_exemptAudio) return false;

            string exe = ProcessNameCache.ForWindow(hwnd);
            if (exe.Length == 0) return false;

            if (_excludeSet.Contains(exe)) return true;

            return _exemptAudio && AudioSessionMonitor.IsRenderingAudio(exe);
        }
        catch
        {
            // No information behaves as the old code did - fade it - rather than switching the
            // effect off wholesale. The one case where that is NOT acceptable is geometry, which is
            // why IsFullScreenOnItsMonitor answers TRUE on failure instead of leaning on this.
            return false;
        }
    }

    /// <summary>
    /// Drop state for windows that were not seen this tick, and release any dim still committed to
    /// one that is merely out of sight.
    ///
    /// The distinction matters now that the gate rejects minimized and cloaked windows: a window that
    /// is minimized, or moved to another virtual desktop, disappears from the sweep WHILE STILL
    /// EXISTING and still dimmed. Forgetting its record there would abandon it with our dim alpha
    /// written, and it would come back permanently faded.
    /// </summary>
    private void Reap()
    {
        // Collect then delete: removing entries while enumerating shifts the remainder under the
        // enumerator and silently skips the next one.
        foreach (IntPtr key in _lastActive.Keys)
        {
            if (!_aliveThisTick.Contains(key)) _gone.Add(key);
        }

        foreach (IntPtr key in _gone)
        {
            bool alive = NativeMethods.IsWindow(key);

            // Still there, just not eligible any more - release it rather than abandoning it.
            if (_dimmed.Remove(key) && alive)
                AlphaCompositor.ClearLayer(key, AlphaCompositor.LayerBreathe);

            // Really gone, so there is nothing to restore - just drop its record so we do not hold
            // state against a handle Windows may reissue.
            if (!alive) AlphaCompositor.Forget(key);

            _lastActive.Remove(key);
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
