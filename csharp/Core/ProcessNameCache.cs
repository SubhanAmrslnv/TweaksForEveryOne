using System;
using System.Collections.Generic;
using System.Text;

namespace WindowTweaks.Core;

/// <summary>
/// The exe name behind a window handle, cached by process id.
///
/// This exists because naming a process is the one expensive step in an eligibility test that is
/// otherwise made of ~0.3 us style getters. The previous route - Process.GetProcessById(...).ProcessName
/// inside PositionMemoryFeature - allocates a managed Process object per call, reads more than the
/// image name to get it, and throws outright against an elevated process. QueryFullProcessImageName
/// on a PROCESS_QUERY_LIMITED_INFORMATION handle does none of those things.
///
/// NEGATIVE RESULTS ARE CACHED TOO, as "". A protected process (an anti-cheat service, a Defender
/// component) or one that has already exited will fail every time, and a feature polling five times a
/// second would otherwise re-probe it forever.
///
/// Trim() drops everything rather than validating entries: Windows recycles process ids and there is
/// no cheap way to notice. It is called from App's 60 s housekeeping timer, so staleness is bounded at
/// a minute and the worst consequence is one window breathing when it should not have.
/// </summary>
internal static class ProcessNameCache
{
    private static readonly object Gate = new();
    private static readonly Dictionary<uint, string> Names = new();

    /// <summary>
    /// Reused per thread rather than per call. A lock guards the dictionary but not this: the buffer
    /// is filled and read inside one call, and a [ThreadStatic] one stays correct for the background
    /// callers this helper is meant to serve (ProximityGhostFeature drives its loop off a Task).
    /// </summary>
    [ThreadStatic]
    private static StringBuilder? _scratch;

    /// <summary>Lower-case exe name without ".exe", or "" when it cannot be determined.</summary>
    public static string ForWindow(IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero) return string.Empty;
        NativeMethods.GetWindowThreadProcessId(hwnd, out uint pid);
        return ForPid(pid);
    }

    /// <summary>Lower-case exe name without ".exe", or "" when it cannot be determined.</summary>
    public static string ForPid(uint pid)
    {
        if (pid == 0) return string.Empty;

        lock (Gate)
        {
            if (Names.TryGetValue(pid, out string? cached)) return cached;
        }

        string name = Query(pid);

        lock (Gate)
        {
            Names[pid] = name;
        }

        return name;
    }

    /// <summary>
    /// Drop every entry. Called from App's 60 s housekeeping timer, because process ids are reused.
    /// </summary>
    public static void Trim()
    {
        lock (Gate)
        {
            Names.Clear();
        }
    }

    private static string Query(uint pid)
    {
        IntPtr handle = IntPtr.Zero;
        try
        {
            handle = NativeMethods.OpenProcess(NativeMethods.PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
            if (handle == IntPtr.Zero) return string.Empty;

            StringBuilder sb = _scratch ??= new StringBuilder(260);
            sb.Clear();
            sb.EnsureCapacity(260);

            int size = sb.Capacity;
            if (!NativeMethods.QueryFullProcessImageName(handle, 0, sb, ref size)) return string.Empty;

            // Lower-cased once, here, so that every comparison afterwards can be Ordinal.
            string path = sb.ToString(0, Math.Min(size, sb.Length));
            int slash = path.LastIndexOf('\\');
            string file = slash >= 0 ? path.Substring(slash + 1) : path;

            if (file.EndsWith(".exe", StringComparison.OrdinalIgnoreCase))
                file = file.Substring(0, file.Length - 4);

            return file.ToLowerInvariant();
        }
        catch
        {
            // A name we cannot read is not an error worth surfacing - the callers all treat "" as
            // "no information" and fall back to their previous behaviour.
            return string.Empty;
        }
        finally
        {
            if (handle != IntPtr.Zero) NativeMethods.CloseHandle(handle);
        }
    }
}
