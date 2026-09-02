using System;
using System.Drawing;
using System.Windows;
using System.Windows.Media.Imaging;
using Application = System.Windows.Application;
using Size = System.Drawing.Size;

namespace WindowTweaks.Core;

/// <summary>
/// The application's own icon, loaded once from the embedded <c>Icon.ico</c> resource.
///
/// The same .ico is compiled into the executable as its Win32 icon (see
/// <c>ApplicationIcon</c> in WindowTweaks.csproj), so what Explorer shows on the file and what
/// the tray and the settings window show at runtime are one asset. It carries frames from 16 px
/// to 256 px; asking for a specific size below picks a real frame instead of scaling one.
///
/// Everything here fails soft. A missing or unreadable resource must never stop the app
/// starting - a tray utility with a generic icon still works, one that throws in its
/// constructor does not - so each accessor falls back to the previous behaviour
/// (<see cref="SystemIcons.Application"/>) and returns null for the WPF window icon,
/// which WPF reads as "use the default".
/// </summary>
public static class AppIcon
{
    // The ";component" form names the assembly that OWNS the resource. The short form
    // ("pack://application:,,,/Icon.ico") resolves against the ENTRY assembly instead, so it
    // silently falls back to a generic icon the moment this code is loaded by anything other
    // than WindowTweaks.exe itself. The assembly name is read rather than written out, so
    // renaming the assembly cannot leave a stale string here.
    private static readonly Uri ResourceUri = new(
        $"pack://application:,,,/{typeof(AppIcon).Assembly.GetName().Name};component/Icon.ico",
        UriKind.Absolute);

    private static Icon? _small;
    private static Icon? _large;
    private static BitmapFrame? _window;
    private static bool _smallTried, _largeTried, _windowTried;

    /// <summary>
    /// A tray-sized icon. Requests the frame matching the current small-icon metric, which is
    /// 16 px at 100% scaling and larger on a high-DPI display - the .ico has a frame for each.
    /// Never null: falls back to the system application icon.
    /// </summary>
    public static Icon Tray
    {
        get
        {
            if (!_smallTried)
            {
                _smallTried = true;
                _small = Load(SmallIconSize());
            }
            return _small ?? SystemIcons.Application;
        }
    }

    /// <summary>
    /// A 32 px icon, for anything that wants the standard large size. Never null.
    /// </summary>
    public static Icon Large
    {
        get
        {
            if (!_largeTried)
            {
                _largeTried = true;
                _large = Load(new Size(32, 32));
            }
            return _large ?? SystemIcons.Application;
        }
    }

    /// <summary>
    /// The icon as WPF wants it, for <see cref="Window.Icon"/>. Null means "leave the default",
    /// which is exactly what assigning null to that property does.
    /// </summary>
    public static BitmapFrame? WindowIcon
    {
        get
        {
            if (!_windowTried)
            {
                _windowTried = true;
                try
                {
                    var stream = Application.GetResourceStream(ResourceUri)?.Stream;
                    if (stream != null)
                    {
                        // OnLoad, so the frame does not hold the stream open for the app's lifetime.
                        _window = BitmapFrame.Create(stream, BitmapCreateOptions.None, BitmapCacheOption.OnLoad);
                    }
                }
                catch
                {
                    _window = null;
                }
            }
            return _window;
        }
    }

    /// <summary>The shell's small-icon metric, which is 16 px at 100% scaling and larger above it.</summary>
    private static Size SmallIconSize()
    {
        try
        {
            var s = System.Windows.Forms.SystemInformation.SmallIconSize;
            return s.Width > 0 && s.Height > 0 ? s : new Size(16, 16);
        }
        catch
        {
            return new Size(16, 16);
        }
    }

    private static Icon? Load(Size size)
    {
        try
        {
            using var stream = Application.GetResourceStream(ResourceUri)?.Stream;
            if (stream == null) return null;

            // This overload selects the closest frame in the .ico rather than scaling one.
            return new Icon(stream, size);
        }
        catch
        {
            return null;
        }
    }
}
