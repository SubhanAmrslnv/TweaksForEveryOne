using System;
using System.Collections.Generic;

namespace WindowTweaks.Core;

/// <summary>
/// The ONLY place allowed to write a foreign window's opacity.
///
/// Opacity on a foreign window is COMPOSED, never absolute. Several unrelated features can want
/// to dim the same window at once, so each keeping its own absolute value makes the result
/// last-writer-wins: set a window to 50% with Shift+Alt+Wheel, then let breathing or ghosting
/// touch it, and the user's 50% is silently gone the moment that feature restores "opaque".
///
/// One record per window holds a BASE the user chose times any number of named modifier LAYERS:
///     final = base * product(layers)
///
/// ONE OWNER PER LAYER NAME. The language cannot enforce it, so the list lives here:
///     "breathe" -> BreathingFeature
///     "ghost"   -> ProximityGhostFeature
///     "drag"    -> DragParallaxFeature
/// Two owners of one name reproduce the oscillation this class exists to prevent, inside a
/// single layer, where it is much harder to see.
///
/// Thread-safety matters: ProximityGhostFeature drives its loop on a background Task while
/// breathing runs on a DispatcherTimer and the transparency wheel runs on a mouse hook, so all
/// three can arrive concurrently. Every public method takes the lock.
/// </summary>
internal static class AlphaCompositor
{
    public const string LayerBreathe = "breathe";
    public const string LayerGhost = "ghost";
    public const string LayerDrag = "drag";

    /// <summary>Never let a window become effectively invisible - the user could not click it to recover.</summary>
    public const byte MinAlpha = 25;

    private sealed class Record
    {
        public byte Base = 255;
        public readonly Dictionary<string, double> Layers = new();

        /// <summary>
        /// True only when WE added WS_EX_LAYERED. We strip it again only in that case: an app that
        /// set the style itself may rely on it, and toggling it underneath such a window causes
        /// visible black flicker.
        /// </summary>
        public bool AddedLayered;

        public int LastCommitted = -1;
    }

    private static readonly object Gate = new();
    private static readonly Dictionary<IntPtr, Record> Records = new();

    /// <summary>The opacity the user chose directly (the transparency wheel, and nothing else).</summary>
    public static void SetBase(IntPtr hwnd, byte alpha)
    {
        if (!IsUsable(hwnd)) return;
        lock (Gate)
        {
            Record r = GetOrAdd(hwnd);
            r.Base = alpha < MinAlpha ? MinAlpha : alpha;
            Commit(hwnd, r);
        }
    }

    /// <summary>
    /// The user's chosen opacity, independent of any ambient effect currently dimming the window.
    /// This is what the transparency wheel must step from - reading the window back with
    /// GetLayeredWindowAttributes returns whatever breathing or ghosting last wrote instead.
    /// </summary>
    public static byte GetBase(IntPtr hwnd)
    {
        lock (Gate)
        {
            return Records.TryGetValue(hwnd, out Record? r) ? r.Base : (byte)255;
        }
    }

    /// <summary>Install or update one named modifier layer. factor is 0.0 - 1.0.</summary>
    public static void SetLayer(IntPtr hwnd, string layer, double factor)
    {
        if (!IsUsable(hwnd)) return;
        if (factor < 0.0) factor = 0.0;
        if (factor > 1.0) factor = 1.0;

        lock (Gate)
        {
            Record r = GetOrAdd(hwnd);
            if (r.Layers.TryGetValue(layer, out double existing) && Math.Abs(existing - factor) < 0.0005)
                return;
            r.Layers[layer] = factor;
            Commit(hwnd, r);
        }
    }

    /// <summary>Remove one layer. Cannot touch the base or any other layer.</summary>
    public static void ClearLayer(IntPtr hwnd, string layer)
    {
        lock (Gate)
        {
            if (!Records.TryGetValue(hwnd, out Record? r)) return;
            if (!r.Layers.Remove(layer)) return;
            Commit(hwnd, r);
        }
    }

    /// <summary>Teardown: return the window to opaque and drop its record.</summary>
    public static void Reset(IntPtr hwnd)
    {
        lock (Gate)
        {
            if (!Records.TryGetValue(hwnd, out Record? r)) return;
            r.Base = 255;
            r.Layers.Clear();
            Commit(hwnd, r);
            Records.Remove(hwnd);
        }
    }

    /// <summary>Teardown only - app exit and the panic path.</summary>
    public static void ResetAll()
    {
        IntPtr[] keys;
        lock (Gate)
        {
            keys = new IntPtr[Records.Count];
            Records.Keys.CopyTo(keys, 0);
        }
        foreach (IntPtr h in keys) Reset(h);
    }

    /// <summary>Forget a window without touching it - for one that has already been destroyed.</summary>
    public static void Forget(IntPtr hwnd)
    {
        lock (Gate)
        {
            Records.Remove(hwnd);
        }
    }

    /// <summary>Drop records for windows that no longer exist. Cheap; call from any slow poll.</summary>
    public static void Sweep()
    {
        lock (Gate)
        {
            if (Records.Count == 0) return;

            List<IntPtr>? dead = null;
            foreach (IntPtr h in Records.Keys)
            {
                if (!NativeMethods.IsWindow(h)) (dead ??= new List<IntPtr>()).Add(h);
            }
            if (dead == null) return;
            foreach (IntPtr h in dead) Records.Remove(h);
        }
    }

    private static Record GetOrAdd(IntPtr hwnd)
    {
        if (Records.TryGetValue(hwnd, out Record? r)) return r;
        r = new Record();
        Records[hwnd] = r;
        return r;
    }

    private static bool IsUsable(IntPtr hwnd)
    {
        return hwnd != IntPtr.Zero && NativeMethods.IsWindow(hwnd);
    }

    /// <summary>Caller must hold Gate.</summary>
    private static void Commit(IntPtr hwnd, Record r)
    {
        if (!IsUsable(hwnd))
        {
            Records.Remove(hwnd);
            return;
        }

        double factor = 1.0;
        foreach (double f in r.Layers.Values) factor *= f;

        // A record is STRUCTURALLY neutral when the user chose opaque and no layer is installed.
        // Only then may the layered style come off - never merely because the arithmetic rounded
        // up to 255, or a ghosted window would flicker between layered and not many times a
        // second while the cursor rests near it.
        bool neutral = r.Base == 255 && r.Layers.Count == 0;

        int alpha = (int)Math.Round(r.Base * factor);
        if (alpha > 255) alpha = 255;
        if (alpha < MinAlpha) alpha = MinAlpha;

        try
        {
            uint exStyle = NativeMethods.GetWindowLong(hwnd, NativeMethods.GWL_EXSTYLE);
            bool isLayered = (exStyle & NativeMethods.WS_EX_LAYERED) != 0;

            if (neutral)
            {
                if (isLayered) NativeMethods.SetLayeredWindowAttributes(hwnd, 0, 255, NativeMethods.LWA_ALPHA);

                if (r.AddedLayered && isLayered)
                {
                    NativeMethods.SetWindowLong(hwnd, NativeMethods.GWL_EXSTYLE, exStyle & ~NativeMethods.WS_EX_LAYERED);
                    r.AddedLayered = false;
                }
                r.LastCommitted = 255;
                return;
            }

            if (!isLayered)
            {
                // Never make a foreign window layered speculatively - it forces a redirection
                // surface. We are past that check here: something actually wants it dimmed.
                NativeMethods.SetWindowLong(hwnd, NativeMethods.GWL_EXSTYLE, exStyle | NativeMethods.WS_EX_LAYERED);
                r.AddedLayered = true;
                r.LastCommitted = -1;
            }

            // Skip a write that would not change a pixel.
            if (r.LastCommitted == alpha) return;

            NativeMethods.SetLayeredWindowAttributes(hwnd, 0, (byte)alpha, NativeMethods.LWA_ALPHA);
            r.LastCommitted = alpha;
        }
        catch
        {
            // A window can die between the IsWindow check and here. Never throw out of a hook,
            // a timer callback or a background loop.
        }
    }
}
