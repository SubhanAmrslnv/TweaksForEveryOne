using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

public class MagneticGroupsFeature : IDisposable
{
    private bool _enabled = false;
    private IntPtr _hookStartEnd = IntPtr.Zero;
    private IntPtr _hookLocation = IntPtr.Zero;
    
    private NativeMethods.WinEventDelegate _startEndDelegate;
    private NativeMethods.WinEventDelegate _locationDelegate;

    private IntPtr _dragHwnd = IntPtr.Zero;
    private NativeMethods.RECT _lastDragRect;
    private List<IntPtr> _groupHwnds = new();
    
    private const int SNAP_THRESHOLD = 5;
    
    public MagneticGroupsFeature()
    {
        _startEndDelegate = new NativeMethods.WinEventDelegate(WinEventProcStartEnd);
        _locationDelegate = new NativeMethods.WinEventDelegate(WinEventProcLocation);
    }

    public bool IsEnabled => _enabled;

    /// <summary>
    /// IDEMPOTENT: FeatureRegistry calls Apply with the state it wants, not with an instruction to
    /// flip. See MagneticSnappingFeature.SetEnabled.
    /// </summary>
    public void SetEnabled(bool enabled)
    {
        if (enabled == _enabled) return;
        _enabled = enabled;

        if (_enabled)
        {
            _hookStartEnd = NativeMethods.SetWinEventHook(
                NativeMethods.EVENT_SYSTEM_MOVESIZESTART,
                NativeMethods.EVENT_SYSTEM_MOVESIZEEND,
                IntPtr.Zero,
                _startEndDelegate,
                0, 0,
                NativeMethods.WINEVENT_OUTOFCONTEXT);
                
            _hookLocation = NativeMethods.SetWinEventHook(
                NativeMethods.EVENT_OBJECT_LOCATIONCHANGE,
                NativeMethods.EVENT_OBJECT_LOCATIONCHANGE,
                IntPtr.Zero,
                _locationDelegate,
                0, 0,
                NativeMethods.WINEVENT_OUTOFCONTEXT);
        }
        else
        {
            if (_hookStartEnd != IntPtr.Zero)
            {
                NativeMethods.UnhookWinEvent(_hookStartEnd);
                _hookStartEnd = IntPtr.Zero;
            }
            if (_hookLocation != IntPtr.Zero)
            {
                NativeMethods.UnhookWinEvent(_hookLocation);
                _hookLocation = IntPtr.Zero;
            }
            _dragHwnd = IntPtr.Zero;
            _groupHwnds.Clear();
        }
    }

    public void Toggle() => SetEnabled(!_enabled);

    private void WinEventProcStartEnd(IntPtr hWinEventHook, uint eventType, IntPtr hwnd, int idObject, int idChild, uint dwEventThread, uint dwmsEventTime)
    {
        if (idObject != 0 || idChild != 0) return; // OBJID_WINDOW = 0

        if (eventType == NativeMethods.EVENT_SYSTEM_MOVESIZESTART)
        {
            _dragHwnd = hwnd;
            NativeMethods.GetWindowRect(_dragHwnd, out _lastDragRect);
            
            // Build the group
            _groupHwnds.Clear();
            var queue = new Queue<IntPtr>();
            var visited = new HashSet<IntPtr>();
            
            queue.Enqueue(_dragHwnd);
            visited.Add(_dragHwnd);

            while (queue.Count > 0)
            {
                IntPtr curr = queue.Dequeue();
                
                if (NativeMethods.DwmGetWindowAttribute(curr, NativeMethods.DWMWA_EXTENDED_FRAME_BOUNDS, out NativeMethods.RECT cFrame, Marshal.SizeOf(typeof(NativeMethods.RECT))) != 0)
                {
                    NativeMethods.GetWindowRect(curr, out cFrame);
                }

                NativeMethods.EnumWindows((IntPtr otherHwnd, IntPtr lParam) =>
                {
                    if (!visited.Contains(otherHwnd) && NativeMethods.IsWindowVisible(otherHwnd))
                    {
                        StringBuilder sb = new StringBuilder(256);
                        NativeMethods.GetClassName(otherHwnd, sb, sb.Capacity);
                        string cls = sb.ToString();
                        if (cls != "Shell_TrayWnd" && cls != "Progman" && cls != "WorkerW")
                        {
                            if (NativeMethods.DwmGetWindowAttribute(otherHwnd, NativeMethods.DWMWA_EXTENDED_FRAME_BOUNDS, out NativeMethods.RECT oFrame, Marshal.SizeOf(typeof(NativeMethods.RECT))) != 0)
                            {
                                NativeMethods.GetWindowRect(otherHwnd, out oFrame);
                            }

                            bool isAdjacent = false;
                            
                            // Check horizontal adjacency (touching L/R edges and overlapping Y)
                            if (Math.Abs(cFrame.Right - oFrame.Left) <= SNAP_THRESHOLD || Math.Abs(cFrame.Left - oFrame.Right) <= SNAP_THRESHOLD)
                            {
                                if (cFrame.Top < oFrame.Bottom && cFrame.Bottom > oFrame.Top) isAdjacent = true;
                            }
                            
                            // Check vertical adjacency (touching T/B edges and overlapping X)
                            if (Math.Abs(cFrame.Bottom - oFrame.Top) <= SNAP_THRESHOLD || Math.Abs(cFrame.Top - oFrame.Bottom) <= SNAP_THRESHOLD)
                            {
                                if (cFrame.Left < oFrame.Right && cFrame.Right > oFrame.Left) isAdjacent = true;
                            }

                            if (isAdjacent)
                            {
                                visited.Add(otherHwnd);
                                queue.Enqueue(otherHwnd);
                                _groupHwnds.Add(otherHwnd);
                            }
                        }
                    }
                    return true;
                }, IntPtr.Zero);
            }
        }
        else if (eventType == NativeMethods.EVENT_SYSTEM_MOVESIZEEND)
        {
            if (hwnd == _dragHwnd)
            {
                _dragHwnd = IntPtr.Zero;
                _groupHwnds.Clear();
            }
        }
    }

    private void WinEventProcLocation(IntPtr hWinEventHook, uint eventType, IntPtr hwnd, int idObject, int idChild, uint dwEventThread, uint dwmsEventTime)
    {
        if (idObject != 0 || idChild != 0) return;
        if (hwnd != _dragHwnd || _dragHwnd == IntPtr.Zero || _groupHwnds.Count == 0) return;

        if (NativeMethods.GetWindowRect(_dragHwnd, out NativeMethods.RECT newRect))
        {
            int dx = newRect.Left - _lastDragRect.Left;
            int dy = newRect.Top - _lastDragRect.Top;

            if (dx != 0 || dy != 0)
            {
                // To break tear-away (like in AHK), we can check velocity or simple threshold here.
                // For simplicity, we apply dx, dy to all grouped windows.
                
                // If dragged too fast, break group?
                if (Math.Abs(dx) > 100 || Math.Abs(dy) > 100)
                {
                    _groupHwnds.Clear();
                }
                else
                {
                    IntPtr hdwp = NativeMethods.BeginDeferWindowPos(_groupHwnds.Count);
                    
                    foreach (var groupedHwnd in _groupHwnds)
                    {
                        if (NativeMethods.GetWindowRect(groupedHwnd, out NativeMethods.RECT gRect))
                        {
                            int gW = gRect.Right - gRect.Left;
                            int gH = gRect.Bottom - gRect.Top;
                            hdwp = NativeMethods.DeferWindowPos(hdwp, groupedHwnd, IntPtr.Zero, 
                                gRect.Left + dx, gRect.Top + dy, gW, gH, 
                                NativeMethods.SWP_NOACTIVATE | NativeMethods.SWP_NOZORDER);
                        }
                    }
                    
                    NativeMethods.EndDeferWindowPos(hdwp);
                }

                _lastDragRect = newRect;
            }
        }
    }

    public void Dispose()
    {
        if (_hookStartEnd != IntPtr.Zero)
        {
            NativeMethods.UnhookWinEvent(_hookStartEnd);
            _hookStartEnd = IntPtr.Zero;
        }
        if (_hookLocation != IntPtr.Zero)
        {
            NativeMethods.UnhookWinEvent(_hookLocation);
            _hookLocation = IntPtr.Zero;
        }
    }
}
