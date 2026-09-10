using System;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

/// <summary>
/// Zero-Delay Menus Feature.
///
/// Eliminates OS context menu delay timers (SPI_SETMENUSHOWDELAY = 0) to provide
/// instant, snappy menu appearance without artificial latency, restoring original
/// user preferences upon shutdown.
/// </summary>
public class ZeroDelayMenusFeature : IDisposable
{
    private int _origDelay = 400;
    private bool _modified;

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
        if (_modified) return;

        int current = 400;
        if (NativeMethods.SystemParametersInfoGet(NativeMethods.SPI_GETMENUSHOWDELAY, 0, ref current, 0))
        {
            _origDelay = current;
        }

        // Set to 0 for instant appearance
        NativeMethods.SystemParametersInfoSet(
            NativeMethods.SPI_SETMENUSHOWDELAY,
            0,
            IntPtr.Zero,
            NativeMethods.SPIF_SENDCHANGE);

        _modified = true;
    }

    private void Stop()
    {
        if (_modified)
        {
            NativeMethods.SystemParametersInfoSet(
                NativeMethods.SPI_SETMENUSHOWDELAY,
                (uint)_origDelay,
                IntPtr.Zero,
                NativeMethods.SPIF_SENDCHANGE);
            _modified = false;
        }
    }

    public void Dispose()
    {
        SetEnabled(false);
    }
}
