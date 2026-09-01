using System;
using System.Windows;
using System.Windows.Interop;

namespace WindowTweaks.Core;

/// <summary>
/// A message-only window that exists solely so the app can be asked to exit.
///
/// This is a tray app with no visible window, and that used to make it unstoppable by ordinary
/// means: `taskkill` without /F, an installer's stop step and a Windows shutdown all work by posting
/// WM_CLOSE to a process's top-level windows, and there were none to post to. The only thing left
/// was a forced kill - which skips OnExit entirely, so settings were never flushed AND every feature
/// lost its chance to undo what it had done to other applications' windows: opacity left on them,
/// windows hidden to the tray with no icon to restore them, windows still parented to the desktop.
///
/// The window is never shown and has no pixels. It just answers WM_CLOSE.
/// </summary>
internal sealed class ShutdownListener : IDisposable
{
    private HwndSource? _source;
    private readonly Action _onShutdownRequested;

    public ShutdownListener(Action onShutdownRequested)
    {
        _onShutdownRequested = onShutdownRequested;

        HwndSourceParameters parameters = new("WindowTweaks.ShutdownListener")
        {
            Width = 0,
            Height = 0,
            PositionX = 0,
            PositionY = 0,
            WindowStyle = 0,
            // A tool window so it can never appear in Alt-Tab or the taskbar.
            ExtendedWindowStyle = unchecked((int)NativeMethods.WS_EX_TOOLWINDOW)
        };

        _source = new HwndSource(parameters);
        _source.AddHook(WndProc);
    }

    private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == (int)NativeMethods.WM_CLOSE || msg == WM_QUERYENDSESSION)
        {
            handled = true;

            // Do not shut down inside the message handler - the caller is waiting on this message,
            // and OnExit runs teardown that can take a moment. Hand it to the dispatcher.
            System.Windows.Application.Current?.Dispatcher.BeginInvoke(_onShutdownRequested);

            // WM_QUERYENDSESSION must answer TRUE, or Windows treats us as blocking its shutdown.
            return msg == WM_QUERYENDSESSION ? new IntPtr(1) : IntPtr.Zero;
        }

        return IntPtr.Zero;
    }

    private const int WM_QUERYENDSESSION = 0x0011;

    public void Dispose()
    {
        try
        {
            if (_source != null)
            {
                _source.RemoveHook(WndProc);
                _source.Dispose();
                _source = null;
            }
        }
        catch
        {
        }
    }
}
