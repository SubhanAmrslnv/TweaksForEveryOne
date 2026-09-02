using System;
using System.Runtime.InteropServices;

namespace WindowTweaks.Core;

public static class AudioManager
{
    [ComImport]
    [Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    private class MMDeviceEnumerator { }

    [ComImport]
    [Guid("A95664D2-9614-4F35-A746-DE8DB63617E6")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IMMDeviceEnumerator
    {
        int EnumAudioEndpoints(int dataFlow, int stateMask, out IntPtr ppDevices);
        [PreserveSig]
        int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice ppEndpoint);
    }

    [ComImport]
    [Guid("D666063F-1587-4E43-81F1-B948E807363F")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IMMDevice
    {
        [PreserveSig]
        int Activate(ref Guid iid, int dwClsCtx, IntPtr pActivationParams, out IAudioEndpointVolume ppInterface);
    }

    [ComImport]
    [Guid("5CDF2C82-841E-4546-9722-0CF74078229A")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IAudioEndpointVolume
    {
        int RegisterControlChangeNotify(IntPtr pNotify);
        int UnregisterControlChangeNotify(IntPtr pNotify);
        int GetChannelCount(out int pnChannelCount);
        int SetMasterVolumeLevel(float fLevelDB, Guid pguidEventContext);

        // PreserveSig on these two because the caller CHECKS the HRESULT: a failure here means the
        // endpoint has gone (a headset unplugged, a Bluetooth speaker asleep) and the cached
        // pointer has to be dropped. Without PreserveSig the runtime turns the HRESULT into an
        // exception and reinterprets the declared int as an [out, retval] parameter, so the return
        // value read back is always zero and every failure looks like success.
        [PreserveSig]
        int SetMasterVolumeLevelScalar(float fLevel, Guid pguidEventContext);

        int GetMasterVolumeLevel(out float pfLevelDB);

        [PreserveSig]
        int GetMasterVolumeLevelScalar(out float pfLevel);
        int SetChannelVolumeLevel(uint nChannel, float fLevelDB, Guid pguidEventContext);
        int SetChannelVolumeLevelScalar(uint nChannel, float fLevel, Guid pguidEventContext);
        int GetChannelVolumeLevel(uint nChannel, out float pfLevelDB);
        int GetChannelVolumeLevelScalar(uint nChannel, out float pfLevel);
        [PreserveSig]
        int SetMute([MarshalAs(UnmanagedType.Bool)] bool bMute, Guid pguidEventContext);
        [PreserveSig]
        int GetMute([MarshalAs(UnmanagedType.Bool)] out bool pbMute);
    }

    private static IAudioEndpointVolume GetMasterVolumeObject()
    {
        IMMDeviceEnumerator deviceEnumerator = null;
        IMMDevice defaultDevice = null;
        IAudioEndpointVolume endpointVolume = null;
        try
        {
            deviceEnumerator = (IMMDeviceEnumerator)new MMDeviceEnumerator();
            deviceEnumerator.GetDefaultAudioEndpoint(0, 1, out defaultDevice); // eRender = 0, eMultimedia = 1
            if (defaultDevice != null)
            {
                Guid iid = typeof(IAudioEndpointVolume).GUID;
                defaultDevice.Activate(ref iid, 23, IntPtr.Zero, out endpointVolume); // CLSCTX_INPROC_SERVER = 1 | CLSCTX_LOCAL_SERVER = 4 ... CLSCTX_ALL = 23
            }
        }
        catch { }
        return endpointVolume;
    }

    private static IAudioEndpointVolume GetMicVolumeObject()
    {
        IMMDeviceEnumerator deviceEnumerator = null;
        IMMDevice defaultDevice = null;
        IAudioEndpointVolume endpointVolume = null;
        try
        {
            deviceEnumerator = (IMMDeviceEnumerator)new MMDeviceEnumerator();
            // eCapture = 1, eMultimedia = 1
            deviceEnumerator.GetDefaultAudioEndpoint(1, 1, out defaultDevice); 
            if (defaultDevice != null)
            {
                Guid iid = typeof(IAudioEndpointVolume).GUID;
                defaultDevice.Activate(ref iid, 23, IntPtr.Zero, out endpointVolume); 
            }
        }
        catch { }
        return endpointVolume;
    }

    public static bool GetMute()
    {
        try
        {
            var vol = GetMasterVolumeObject();
            if (vol != null)
            {
                vol.GetMute(out bool isMuted);
                Marshal.ReleaseComObject(vol);
                return isMuted;
            }
        }
        catch { }
        return false;
    }

    public static void SetMute(bool mute)
    {
        try
        {
            var vol = GetMasterVolumeObject();
            if (vol != null)
            {
                vol.SetMute(mute, Guid.Empty);
                Marshal.ReleaseComObject(vol);
            }
        }
        catch { }
    }

    public static bool GetMicMute()
    {
        try
        {
            var vol = GetMicVolumeObject();
            if (vol != null)
            {
                vol.GetMute(out bool isMuted);
                Marshal.ReleaseComObject(vol);
                return isMuted;
            }
        }
        catch { }
        return false;
    }

    public static void SetMicMute(bool mute)
    {
        try
        {
            var vol = GetMicVolumeObject();
            if (vol != null)
            {
                vol.SetMute(mute, Guid.Empty);
                Marshal.ReleaseComObject(vol);
            }
        }
        catch { }
    }

    // -------------------------------------------------------------------------------------------
    // Master volume, for the taskbar scroll wheel.
    //
    // THE ENDPOINT IS CACHED, and that is a measured requirement rather than tidiness: building the
    // enumerator and activating IAudioEndpointVolume costs about 6,500 microseconds (see the
    // performance table in CLAUDE.md). Doing that per wheel notch made scrolling the taskbar feel
    // broken - the first notch was slow and a fast scroll queued up behind itself.
    //
    // THE CACHE IS ONLY EVER TOUCHED FROM THE UI THREAD. These are COM objects with no declared
    // threading contract of their own, and the alternative to one owning thread is a marshalling
    // problem on an input path. The taskbar wheel feature hops to the dispatcher for exactly this
    // reason; it needs to be there for the on-screen readout anyway.
    //
    // Any failing call drops the cache: a device that is being removed - a headset unplugged, a
    // Bluetooth speaker going to sleep - leaves a stale pointer that fails every call afterwards,
    // and the volume wheel would be dead for the rest of the session.
    // -------------------------------------------------------------------------------------------

    private static IAudioEndpointVolume? _cachedRender;

    private static IAudioEndpointVolume? EnsureRender()
    {
        if (_cachedRender != null) return _cachedRender;
        _cachedRender = GetMasterVolumeObject();
        return _cachedRender;
    }

    private static void DropRenderCache()
    {
        IAudioEndpointVolume? stale = _cachedRender;
        _cachedRender = null;

        if (stale == null) return;
        try { Marshal.ReleaseComObject(stale); } catch { }
    }

    /// <summary>
    /// Reads the master volume as 0.0-1.0, and whether the device is muted. Returns false when there
    /// is no usable endpoint - no sound card, or a device mid-removal.
    /// </summary>
    public static bool TryGetMasterVolume(out float level, out bool muted)
    {
        level = 0;
        muted = false;

        try
        {
            IAudioEndpointVolume? vol = EnsureRender();
            if (vol == null) return false;

            if (vol.GetMasterVolumeLevelScalar(out float current) != 0)
            {
                DropRenderCache();
                return false;
            }

            vol.GetMute(out bool isMuted);

            level = current;
            muted = isMuted;
            return true;
        }
        catch
        {
            DropRenderCache();
            return false;
        }
    }

    /// <summary>
    /// Moves the master volume by <paramref name="steps"/> notches of
    /// <paramref name="stepPercent"/> each, unmuting first if it was muted - which is what a person
    /// scrolling up expects, and what the hardware volume keys do.
    /// </summary>
    /// <returns>The resulting level as 0.0-1.0, or -1 when there is no usable endpoint.</returns>
    public static float NudgeMasterVolume(int steps, int stepPercent)
    {
        if (steps == 0) return -1;

        try
        {
            IAudioEndpointVolume? vol = EnsureRender();
            if (vol == null) return -1;

            if (vol.GetMasterVolumeLevelScalar(out float current) != 0)
            {
                DropRenderCache();
                return -1;
            }

            vol.GetMute(out bool isMuted);

            // Scrolling up on a muted device means "let me hear it", not "silently raise the number
            // that is still muted".
            if (isMuted && steps > 0) vol.SetMute(false, Guid.Empty);

            float next = current + steps * (stepPercent / 100.0f);
            next = Math.Clamp(next, 0.0f, 1.0f);

            if (vol.SetMasterVolumeLevelScalar(next, Guid.Empty) != 0)
            {
                DropRenderCache();
                return -1;
            }

            return next;
        }
        catch
        {
            DropRenderCache();
            return -1;
        }
    }

    /// <summary>Toggles the master mute and reports the new state. -1 when there is no endpoint.</summary>
    public static int ToggleMasterMute()
    {
        try
        {
            IAudioEndpointVolume? vol = EnsureRender();
            if (vol == null) return -1;

            if (vol.GetMute(out bool isMuted) != 0)
            {
                DropRenderCache();
                return -1;
            }

            if (vol.SetMute(!isMuted, Guid.Empty) != 0)
            {
                DropRenderCache();
                return -1;
            }

            return !isMuted ? 1 : 0;
        }
        catch
        {
            DropRenderCache();
            return -1;
        }
    }

    /// <summary>Releases the cached endpoint. Exit only.</summary>
    public static void Shutdown()
    {
        DropRenderCache();
    }
}
