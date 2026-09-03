using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace WindowTweaks.Core;

/// <summary>
/// Which applications are CURRENTLY rendering audio, keyed by exe name.
///
/// KEYED ON EXE NAME AND NOT ON PROCESS ID, and that is a correctness requirement rather than a
/// convenience. Chromium renders all audio from a separate utility process
/// (--utility-sub-type=audio.mojom.AudioService) which owns NO WINDOWS AT ALL, so the process id that
/// IAudioSessionControl2.GetProcessId reports for a playing YouTube tab matches nothing EnumWindows
/// will ever return. Firefox and Electron apps split the same way. The image name is the only key
/// that joins an audio session back to a window.
///
/// The consequence is stated rather than worked around: this exempts EVERY window of an application
/// that is playing sound, not only the one with the video in it. Per-window granularity is not
/// obtainable from these APIs at all.
///
/// THE SESSION MANAGER IS CACHED, for the reason AudioManager records: building the enumerator and
/// activating an endpoint interface is expensive. Measured here, on the first call: about 21,000
/// microseconds. That is a once-per-session cost paid on the first tick that has a window about to
/// fade, and it is why this is throttled, cached, and never anywhere near an input path. A
/// subsequent throttled call measured under 0.01 us.
///
/// THE SESSION ENUMERATOR IS NOT cached, and must not be - it is a snapshot taken when
/// GetSessionEnumerator() was called, so a video started afterwards never appears in it.
///
/// UI THREAD ONLY, like AudioManager's cache, and never from inside an EnumWindows callback: a COM
/// call on the WPF UI thread can pump messages, and pumping inside an enumeration lets the dispatcher
/// re-enter whatever started it.
/// </summary>
internal static class AudioSessionMonitor
{
    // A second is short enough that un-pausing a video releases the window within about one idle
    // check, and long enough that the COM work is nowhere near a hot path.
    private const int RefreshIntervalMs = 1000;

    private const int AudioSessionStateActive = 1;

    private static readonly HashSet<string> Rendering = new(StringComparer.Ordinal);
    private static IAudioSessionManager2? _cachedManager;
    private static long _lastRefreshTicks = -RefreshIntervalMs;

    /// <summary>
    /// True when an application with this image name has an active render session.
    ///
    /// The name is lower-case and without ".exe", as ProcessNameCache returns it. False means "not
    /// rendering" OR "no information": the two are deliberately not distinguished, because every
    /// caller does the same thing with both.
    /// </summary>
    public static bool IsRenderingAudio(string exeName)
    {
        if (string.IsNullOrEmpty(exeName)) return false;
        return Rendering.Contains(exeName);
    }

    /// <summary>
    /// Rebuild the set, at most once per <see cref="RefreshIntervalMs"/>. Cheap to call on every tick;
    /// it returns immediately inside the interval.
    /// </summary>
    public static void Refresh()
    {
        long now = Environment.TickCount64;
        if (now - _lastRefreshTicks < RefreshIntervalMs) return;
        _lastRefreshTicks = now;

        IAudioSessionManager2? manager = EnsureManager();
        if (manager == null) return;

        IAudioSessionEnumerator? sessions = null;
        try
        {
            if (manager.GetSessionEnumerator(out sessions) != 0 || sessions == null)
            {
                // A device mid-removal leaves a stale pointer that fails every call afterwards, and
                // the exemption would be dead for the rest of the session.
                DropManager();
                return;
            }

            if (sessions.GetCount(out int count) != 0) { DropManager(); return; }

            // Reused, never reallocated. Only cleared once the enumeration has actually succeeded, so
            // a mid-way failure leaves the previous answer in place rather than an empty one.
            Rendering.Clear();

            for (int i = 0; i < count; i++)
            {
                IAudioSessionControl? control = null;
                IAudioSessionControl2? control2 = null;
                try
                {
                    if (sessions.GetSession(i, out control) != 0 || control == null) continue;

                    control2 = control as IAudioSessionControl2;
                    if (control2 == null) continue;

                    if (control2.GetState(out int state) != 0) continue;

                    // Only Active counts. Inactive is a paused or silent stream, which must not
                    // exempt anything - that is what lets a paused video fade again.
                    if (state != AudioSessionStateActive) continue;

                    // The system-sounds session is not an application playing something.
                    if (control2.IsSystemSoundsSession() == 0) continue;

                    if (control2.GetProcessId(out uint pid) != 0 || pid == 0) continue;

                    // Our own keyboard-click and clipboard sounds hold an active session while they
                    // play, and this app must not exempt itself from anything.
                    if (pid == (uint)Environment.ProcessId) continue;

                    string exe = ProcessNameCache.ForPid(pid);
                    if (exe.Length != 0) Rendering.Add(exe);
                }
                catch
                {
                    // One unreadable session must not cost the whole sweep.
                }
                finally
                {
                    // ONE release, not two. Casting a COM object to another interface hands back the
                    // SAME runtime wrapper - it holds every interface pointer it has queried for - so
                    // control2 and control are one object, and releasing both would decrement the
                    // same wrapper twice.
                    if (control != null) { try { Marshal.ReleaseComObject(control); } catch { } }
                }
            }
        }
        catch
        {
            DropManager();
        }
        finally
        {
            if (sessions != null) { try { Marshal.ReleaseComObject(sessions); } catch { } }
        }
    }

    /// <summary>Release the cached session manager. Exit only.</summary>
    public static void Shutdown()
    {
        DropManager();
        Rendering.Clear();
    }

    private static IAudioSessionManager2? EnsureManager()
    {
        if (_cachedManager != null) return _cachedManager;

        IMMDeviceEnumerator? enumerator = null;
        IMMDevice? device = null;
        try
        {
            enumerator = (IMMDeviceEnumerator)new MMDeviceEnumerator();

            // eRender = 0, eMultimedia = 1.
            if (enumerator.GetDefaultAudioEndpoint(0, 1, out device) != 0 || device == null) return null;

            Guid iid = typeof(IAudioSessionManager2).GUID;
            if (device.Activate(ref iid, 23, IntPtr.Zero, out object? raw) != 0 || raw == null) return null;

            _cachedManager = raw as IAudioSessionManager2;
            return _cachedManager;
        }
        catch
        {
            // No sound card, or a device mid-removal. The caller treats null as "no information".
            return null;
        }
        finally
        {
            if (device != null) { try { Marshal.ReleaseComObject(device); } catch { } }
            if (enumerator != null) { try { Marshal.ReleaseComObject(enumerator); } catch { } }
        }
    }

    private static void DropManager()
    {
        IAudioSessionManager2? stale = _cachedManager;
        _cachedManager = null;

        if (stale == null) return;
        try { Marshal.ReleaseComObject(stale); } catch { }
    }

    // -------------------------------------------------------------------------------------------
    // COM declarations.
    //
    // THESE CANNOT BE SHARED WITH AudioManager, and the reason must not be "de-duplicated" away.
    // AudioManager's IMMDevice.Activate is typed "out IAudioEndpointVolume", and a [ComImport]
    // interface binds its methods to VTABLE SLOTS IN DECLARATION ORDER - so adding an Activate
    // overload there would shift every slot after it and silently corrupt every call. This file
    // declares its own minimal IMMDeviceEnumerator/IMMDevice whose Activate hands back an untyped
    // object instead.
    //
    // Every method is [PreserveSig] because the caller CHECKS the HRESULT, for the reason spelled
    // out in AudioManager: without it the runtime turns the HRESULT into an exception and
    // reinterprets the declared int as an [out, retval] parameter, so every failure reads as success.
    //
    // Methods this file never calls are still declared, in order, as IntPtr-only placeholders. They
    // are not padding - they hold the vtable slots, and removing one shifts everything below it.
    // -------------------------------------------------------------------------------------------

    [ComImport]
    [Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    private class MMDeviceEnumerator { }

    [ComImport]
    [Guid("A95664D2-9614-4F35-A746-DE8DB63617E6")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IMMDeviceEnumerator
    {
        [PreserveSig] int EnumAudioEndpoints(int dataFlow, int stateMask, out IntPtr ppDevices);
        [PreserveSig] int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice? ppEndpoint);
        [PreserveSig] int GetDevice([MarshalAs(UnmanagedType.LPWStr)] string pwstrId, out IMMDevice? ppDevice);
        [PreserveSig] int RegisterEndpointNotificationCallback(IntPtr pClient);
        [PreserveSig] int UnregisterEndpointNotificationCallback(IntPtr pClient);
    }

    [ComImport]
    [Guid("D666063F-1587-4E43-81F1-B948E807363F")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IMMDevice
    {
        [PreserveSig]
        int Activate(ref Guid iid, int dwClsCtx, IntPtr pActivationParams, [MarshalAs(UnmanagedType.IUnknown)] out object? ppInterface);

        [PreserveSig] int OpenPropertyStore(int stgmAccess, out IntPtr ppProperties);
        [PreserveSig] int GetId([MarshalAs(UnmanagedType.LPWStr)] out string ppstrId);
        [PreserveSig] int GetState(out int pdwState);
    }

    /// <summary>
    /// IAudioSessionManager2. The first two slots belong to IAudioSessionManager, which it derives
    /// from, so GetSessionEnumerator is the THIRD slot and not the first.
    /// </summary>
    [ComImport]
    [Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IAudioSessionManager2
    {
        // --- IAudioSessionManager ---
        [PreserveSig] int GetAudioSessionControl(IntPtr audioSessionGuid, int streamFlags, out IntPtr sessionControl);
        [PreserveSig] int GetSimpleAudioVolume(IntPtr audioSessionGuid, int streamFlags, out IntPtr audioVolume);

        // --- IAudioSessionManager2 ---
        [PreserveSig] int GetSessionEnumerator(out IAudioSessionEnumerator? sessionEnum);
        [PreserveSig] int RegisterSessionNotification(IntPtr sessionNotification);
        [PreserveSig] int UnregisterSessionNotification(IntPtr sessionNotification);
        [PreserveSig] int RegisterDuckNotification([MarshalAs(UnmanagedType.LPWStr)] string sessionId, IntPtr duckNotification);
        [PreserveSig] int UnregisterDuckNotification(IntPtr duckNotification);
    }

    [ComImport]
    [Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IAudioSessionEnumerator
    {
        [PreserveSig] int GetCount(out int sessionCount);
        [PreserveSig] int GetSession(int sessionCount, out IAudioSessionControl? session);
    }

    /// <summary>
    /// Declared only because IAudioSessionEnumerator.GetSession hands one back; every call this file
    /// makes goes through IAudioSessionControl2, which it is queried for.
    /// </summary>
    [ComImport]
    [Guid("F4B1A599-7266-4319-A8CA-E70ACB11E8CD")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IAudioSessionControl
    {
        [PreserveSig] int GetState(out int pRetVal);
        [PreserveSig] int GetDisplayName([MarshalAs(UnmanagedType.LPWStr)] out string pRetVal);
        [PreserveSig] int SetDisplayName([MarshalAs(UnmanagedType.LPWStr)] string value, IntPtr eventContext);
        [PreserveSig] int GetIconPath([MarshalAs(UnmanagedType.LPWStr)] out string pRetVal);
        [PreserveSig] int SetIconPath([MarshalAs(UnmanagedType.LPWStr)] string value, IntPtr eventContext);
        [PreserveSig] int GetGroupingParam(out Guid pRetVal);
        [PreserveSig] int SetGroupingParam(IntPtr overrideGuid, IntPtr eventContext);
        [PreserveSig] int RegisterAudioSessionNotification(IntPtr newNotifications);
        [PreserveSig] int UnregisterAudioSessionNotification(IntPtr newNotifications);
    }

    /// <summary>
    /// IAudioSessionControl2. The first nine slots are IAudioSessionControl's, so GetProcessId is the
    /// twelfth slot. IsSystemSoundsSession follows the HRESULT convention rather than returning a
    /// bool: S_OK (0) means it IS the system-sounds session, S_FALSE (1) means it is not.
    /// </summary>
    [ComImport]
    [Guid("BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IAudioSessionControl2
    {
        // --- IAudioSessionControl ---
        [PreserveSig] int GetState(out int pRetVal);
        [PreserveSig] int GetDisplayName([MarshalAs(UnmanagedType.LPWStr)] out string pRetVal);
        [PreserveSig] int SetDisplayName([MarshalAs(UnmanagedType.LPWStr)] string value, IntPtr eventContext);
        [PreserveSig] int GetIconPath([MarshalAs(UnmanagedType.LPWStr)] out string pRetVal);
        [PreserveSig] int SetIconPath([MarshalAs(UnmanagedType.LPWStr)] string value, IntPtr eventContext);
        [PreserveSig] int GetGroupingParam(out Guid pRetVal);
        [PreserveSig] int SetGroupingParam(IntPtr overrideGuid, IntPtr eventContext);
        [PreserveSig] int RegisterAudioSessionNotification(IntPtr newNotifications);
        [PreserveSig] int UnregisterAudioSessionNotification(IntPtr newNotifications);

        // --- IAudioSessionControl2 ---
        [PreserveSig] int GetSessionIdentifier([MarshalAs(UnmanagedType.LPWStr)] out string pRetVal);
        [PreserveSig] int GetSessionInstanceIdentifier([MarshalAs(UnmanagedType.LPWStr)] out string pRetVal);
        [PreserveSig] int GetProcessId(out uint pRetVal);
        [PreserveSig] int IsSystemSoundsSession();
        [PreserveSig] int SetDuckingPreference([MarshalAs(UnmanagedType.Bool)] bool optOut);
    }
}
