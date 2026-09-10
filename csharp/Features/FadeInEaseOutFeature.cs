using System;
using System.Collections.Generic;
using System.Windows.Threading;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

/// <summary>
/// Fade In / Ease-Out Feature.
///
/// Intercepts window show events via SetWinEventHook and substitutes harsh pop-ins
/// with cinematic 120ms spring fades using AlphaCompositor.
/// </summary>
public class FadeInEaseOutFeature : IDisposable
{
    private IntPtr _hook;
    private NativeMethods.WinEventDelegate? _winEventDelegate;
    private DispatcherTimer? _animTimer;

    private class ActiveFade
    {
        public double Alpha;
        public double Velocity;
    }

    private readonly Dictionary<IntPtr, ActiveFade> _fadingWindows = new();

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
        if (_hook != IntPtr.Zero) return;

        _winEventDelegate = OnWinEvent;
        _hook = NativeMethods.SetWinEventHook(
            NativeMethods.EVENT_OBJECT_SHOW,
            NativeMethods.EVENT_OBJECT_SHOW,
            IntPtr.Zero,
            _winEventDelegate,
            0,
            0,
            NativeMethods.WINEVENT_OUTOFCONTEXT);

        _animTimer = new DispatcherTimer(DispatcherPriority.Render)
        {
            Interval = TimeSpan.FromMilliseconds(15)
        };
        _animTimer.Tick += OnAnimTick;
    }

    private void OnWinEvent(IntPtr hWinEventHook, uint eventType, IntPtr hwnd, int idObject, int idChild, uint dwEventThread, uint dwmsEventTime)
    {
        if (idObject != 0 || hwnd == IntPtr.Zero) return;
        if (!WindowFilter.IsOrdinaryAppWindow(hwnd)) return;

        // Self-exclusion
        NativeMethods.GetWindowThreadProcessId(hwnd, out uint pid);
        if (pid == (uint)Environment.ProcessId) return;

        lock (_fadingWindows)
        {
            if (!_fadingWindows.ContainsKey(hwnd))
            {
                _fadingWindows[hwnd] = new ActiveFade { Alpha = 0.05, Velocity = 5.0 };
                AlphaCompositor.SetLayer(hwnd, "fadein", 0.05);

                if (_animTimer != null && !_animTimer.IsEnabled)
                {
                    _animTimer.Start();
                }
            }
        }
    }

    private void OnAnimTick(object? sender, EventArgs e)
    {
        List<IntPtr>? finished = null;

        lock (_fadingWindows)
        {
            foreach (var (hwnd, state) in _fadingWindows)
            {
                if (!NativeMethods.IsWindow(hwnd))
                {
                    (finished ??= new()).Add(hwnd);
                    continue;
                }

                double cur = state.Alpha;
                double vel = state.Velocity;
                AppleSpringEngine.Step(ref cur, ref vel, 1.0, 0.015, AppleSpringEngine.SpringConfig.Snappy);
                state.Alpha = cur;
                state.Velocity = vel;

                if (cur >= 0.99)
                {
                    (finished ??= new()).Add(hwnd);
                    AlphaCompositor.ClearLayer(hwnd, "fadein");
                }
                else
                {
                    AlphaCompositor.SetLayer(hwnd, "fadein", cur);
                }
            }

            if (finished != null)
            {
                foreach (var h in finished) _fadingWindows.Remove(h);
            }

            if (_fadingWindows.Count == 0 && _animTimer != null)
            {
                _animTimer.Stop();
            }
        }
    }

    private void Stop()
    {
        if (_hook != IntPtr.Zero)
        {
            NativeMethods.UnhookWinEvent(_hook);
            _hook = IntPtr.Zero;
        }

        _animTimer?.Stop();
        _animTimer = null;

        lock (_fadingWindows)
        {
            foreach (var hwnd in _fadingWindows.Keys)
            {
                AlphaCompositor.ClearLayer(hwnd, "fadein");
            }
            _fadingWindows.Clear();
        }

        _winEventDelegate = null;
    }

    public void Dispose()
    {
        SetEnabled(false);
    }
}
