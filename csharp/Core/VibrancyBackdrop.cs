using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Effects;
using Point = System.Windows.Point;
using Color = System.Windows.Media.Color;

namespace WindowTweaks.Core;

/// <summary>
/// macOS-Tier "Liquid Glass" Vibrancy and DWM Backdrop Management.
///
/// Implements dual-pass materials:
///   - Windows 11 DWM system backdrops (Acrylic DWMSBT_TRANSIENTWINDOW, Mica Alt DWMSBT_TABBEDWINDOW).
///   - 1px continuous inner specular reflection border (top 0.16 alpha -> bottom 0.04 alpha).
///   - Multi-pole drop shadows (Ambient blur=12px offsetY=4px + Key blur=48px offsetY=20px).
/// </summary>
internal static class VibrancyBackdrop
{
    public enum BackdropType
    {
        None = 1,
        Mica = 2,
        Acrylic = 3,
        MicaAlt = 4
    }

    /// <summary>
    /// Attempts to apply the native Windows 11 DWM system backdrop to an HWND.
    /// Safely falls back on earlier Windows builds without throwing.
    /// </summary>
    public static bool ApplyNativeBackdrop(IntPtr hwnd, BackdropType type)
    {
        if (hwnd == IntPtr.Zero || !NativeMethods.IsWindow(hwnd)) return false;

        try
        {
            int backdrop = (int)type;
            int hr = NativeMethods.DwmSetWindowAttribute(
                hwnd,
                NativeMethods.DWMWA_SYSTEMBACKDROP_TYPE,
                ref backdrop,
                sizeof(int));

            int cornerPref = NativeMethods.DWMWCP_ROUND;
            NativeMethods.DwmSetWindowAttribute(
                hwnd,
                NativeMethods.DWMWA_WINDOW_CORNER_PREFERENCE,
                ref cornerPref,
                sizeof(int));

            return hr == 0;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>
    /// Convenience helper to apply backdrop to a WPF Window.
    /// </summary>
    public static bool ApplyNativeBackdrop(Window window, BackdropType type)
    {
        IntPtr hwnd = new WindowInteropHelper(window).Handle;
        return ApplyNativeBackdrop(hwnd, type);
    }

    /// <summary>
    /// 1px continuous specular reflection border brush (top edge 16% specular, bottom edge 4% specular).
    /// </summary>
    public static LinearGradientBrush CreateSpecularBorderBrush()
    {
        var brush = new LinearGradientBrush
        {
            StartPoint = new Point(0.5, 0.0),
            EndPoint = new Point(0.5, 1.0)
        };
        brush.GradientStops.Add(new GradientStop(Color.FromArgb(41, 255, 255, 255), 0.0));  // 0.16
        brush.GradientStops.Add(new GradientStop(Color.FromArgb(20, 255, 255, 255), 0.5));  // 0.08
        brush.GradientStops.Add(new GradientStop(Color.FromArgb(10, 255, 255, 255), 1.0));  // 0.04
        brush.Freeze();
        return brush;
    }

    /// <summary>
    /// Frosted glass background tint brush for Dark Mode HUDs / OSDs.
    /// </summary>
    public static SolidColorBrush CreateFrostedBackgroundBrush(bool isDark = true)
    {
        var brush = isDark
            ? new SolidColorBrush(Color.FromArgb(173, 28, 28, 30))   // ~68% dark liquid glass
            : new SolidColorBrush(Color.FromArgb(194, 242, 242, 247)); // ~76% light frosted
        brush.Freeze();
        return brush;
    }

    /// <summary>
    /// macOS-tier Key Shadow (deep spatial elevation: blur=48px, offsetY=20px, opacity=0.28).
    /// </summary>
    public static DropShadowEffect CreateKeyShadowEffect()
    {
        var effect = new DropShadowEffect
        {
            BlurRadius = 48,
            Direction = 270,
            ShadowDepth = 20,
            Opacity = 0.28,
            Color = Colors.Black,
            RenderingBias = RenderingBias.Performance
        };
        effect.Freeze();
        return effect;
    }

    /// <summary>
    /// macOS-tier Ambient Shadow (diffuse contact grounding: blur=12px, offsetY=4px, opacity=0.12).
    /// </summary>
    public static DropShadowEffect CreateAmbientShadowEffect()
    {
        var effect = new DropShadowEffect
        {
            BlurRadius = 12,
            Direction = 270,
            ShadowDepth = 4,
            Opacity = 0.12,
            Color = Colors.Black,
            RenderingBias = RenderingBias.Performance
        };
        effect.Freeze();
        return effect;
    }
}
