using System;

namespace WindowTweaks.Core;

/// <summary>
/// The one Windows setting this app cannot work around.
///
/// DragFullWindows is a hard functional dependency, not cosmetic. With it off, Windows drags a
/// hollow outline and the window rect does not move until release - so every velocity sample
/// reads zero, and drag parallax, the glide and velocity-scaled snapping all silently do nothing.
/// There is no error to see; the features just have no effect.
///
/// So it is ENABLED at startup rather than merely warned about, and only when a feature that
/// actually needs it is on. The change is system-wide and persisted (SPIF_UPDATEINIFILE), and is
/// deliberately NOT reverted on exit - reverting it would fight the user's own preference every
/// time they closed the app.
/// </summary>
internal static class SystemTuning
{
    public static bool IsDragFullWindowsEnabled()
    {
        try
        {
            int value = 0;
            if (!NativeMethods.SystemParametersInfoGet(NativeMethods.SPI_GETDRAGFULLWINDOWS, 0, ref value, 0))
                return true; // Cannot read it: assume fine rather than changing the user's system.
            return value != 0;
        }
        catch
        {
            return true;
        }
    }

    /// <returns>True if it is now on (already was, or we turned it on).</returns>
    public static bool EnsureDragFullWindows()
    {
        try
        {
            if (IsDragFullWindowsEnabled()) return true;

            NativeMethods.SystemParametersInfoSet(
                NativeMethods.SPI_SETDRAGFULLWINDOWS,
                1,
                IntPtr.Zero,
                NativeMethods.SPIF_UPDATEINIFILE | NativeMethods.SPIF_SENDCHANGE);

            // Read it back: the call can report success without the change taking effect.
            return IsDragFullWindowsEnabled();
        }
        catch
        {
            return false;
        }
    }
}
