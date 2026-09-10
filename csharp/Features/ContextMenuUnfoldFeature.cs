using System;
using System.Collections.Generic;
using System.Text;
using System.Windows.Threading;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

/// <summary>
/// Context Menu Unfold Feature (macOS Cascading Menu Parity).
///
/// Unfolds context menus with an origami-style top-down cascading spring reveal
/// within 100ms using AppleSpringEngine.
/// </summary>
public class ContextMenuUnfoldFeature : IDisposable
{
    private IntPtr _hook;
    private NativeMethods.WinEventDelegate? _winEventDelegate;
    private DispatcherTimer? _animTimer;

    private class ActiveMenu
    {
        public IntPtr Hwnd;
        public int X, Y, Width, TargetHeight;
        public double CurrentHeight = 10.0;
        public double VelH = 1800.0;
    }

    private readonly List<ActiveMenu> _menus = new();

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
            Interval = TimeSpan.FromMilliseconds(12)
        };
        _animTimer.Tick += OnAnimTick;
    }

    private void OnWinEvent(IntPtr hWinEventHook, uint eventType, IntPtr hwnd, int idObject, int idChild, uint dwEventThread, uint dwmsEventTime)
    {
        if (hwnd == IntPtr.Zero) return;

        var sb = new StringBuilder(64);
        NativeMethods.GetClassName(hwnd, sb, sb.Capacity);
        if (sb.ToString() != "#32768") return; // Win32 Popup Menu Class

        if (!NativeMethods.GetWindowRect(hwnd, out NativeMethods.RECT rect)) return;

        int ww = rect.Right - rect.Left;
        int wh = rect.Bottom - rect.Top;
        if (ww <= 20 || wh <= 20) return;

        lock (_menus)
        {
            _menus.Add(new ActiveMenu
            {
                Hwnd = hwnd,
                X = rect.Left,
                Y = rect.Top,
                Width = ww,
                TargetHeight = wh,
                CurrentHeight = 15.0,
                VelH = 2000.0
            });

            NativeMethods.SetWindowPos(hwnd, IntPtr.Zero, rect.Left, rect.Top, ww, 15,
                NativeMethods.SWP_NOZORDER | NativeMethods.SWP_NOACTIVATE);

            if (_animTimer != null && !_animTimer.IsEnabled)
            {
                _animTimer.Start();
            }
        }
    }

    private void OnAnimTick(object? sender, EventArgs e)
    {
        lock (_menus)
        {
            for (int i = _menus.Count - 1; i >= 0; i--)
            {
                var m = _menus[i];
                if (!NativeMethods.IsWindow(m.Hwnd))
                {
                    _menus.RemoveAt(i);
                    continue;
                }

                AppleSpringEngine.Step(ref m.CurrentHeight, ref m.VelH, m.TargetHeight, 0.012, AppleSpringEngine.SpringConfig.Snappy);

                int curH = Math.Max(15, (int)Math.Round(m.CurrentHeight));
                NativeMethods.SetWindowPos(m.Hwnd, IntPtr.Zero, m.X, m.Y, m.Width, curH,
                    NativeMethods.SWP_NOZORDER | NativeMethods.SWP_NOACTIVATE);

                if (Math.Abs(m.CurrentHeight - m.TargetHeight) < 2.0 && Math.Abs(m.VelH) < 5.0)
                {
                    NativeMethods.SetWindowPos(m.Hwnd, IntPtr.Zero, m.X, m.Y, m.Width, m.TargetHeight,
                        NativeMethods.SWP_NOZORDER | NativeMethods.SWP_NOACTIVATE);
                    _menus.RemoveAt(i);
                }
            }

            if (_menus.Count == 0)
            {
                _animTimer?.Stop();
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

        lock (_menus)
        {
            _menus.Clear();
        }

        _winEventDelegate = null;
    }

    public void Dispose()
    {
        SetEnabled(false);
    }
}
