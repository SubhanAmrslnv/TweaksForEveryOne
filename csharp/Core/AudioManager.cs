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
        int SetMasterVolumeLevelScalar(float fLevel, Guid pguidEventContext);
        int GetMasterVolumeLevel(out float pfLevelDB);
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
}
