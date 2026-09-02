using System;
using System.Runtime.InteropServices;

namespace WindowTweaks.Core;

/// <summary>
/// The one place this app injects keys and mouse events, and the only place allowed to.
///
/// Everything sent from here is stamped with <see cref="NativeMethods.SyntheticTag"/> in
/// dwExtraInfo, which is what makes the shared hooks able to recognise the app's own output. That
/// matters for any feature that swallows an event and then replays it: the LLMHF_INJECTED flag alone
/// says only "somebody injected this", so a feature could not tell its own replay apart from input
/// from another tool, from an on-screen keyboard, or from a remote-desktop session.
///
/// The alternative that was here before was counting ("ignore the next two events"), and it is worth
/// recording why it failed: the count desynchronised as soon as any unrelated event arrived between
/// the injection and its arrival at the hook, after which grab and pan swallowed a real middle click
/// and the browser never saw it. That is the reported "middle click breaks opening and closing tabs".
///
/// NOTE ON THE ANTIVIRUS HEURISTIC. Synthetic input is one of the behaviours that gets this app
/// flagged (see docs/ANTIVIRUS.md). Keeping it in one small, obvious file with no key buffering
/// anywhere near it is deliberate.
/// </summary>
internal static class SyntheticInput
{
    private const uint KEYEVENTF_KEYUP = 0x0002;

    private static readonly int InputSize = Marshal.SizeOf(typeof(NativeMethods.INPUT));

    /// <summary>Press and release one key.</summary>
    public static void Tap(ushort virtualKey)
    {
        NativeMethods.INPUT[] inputs = new NativeMethods.INPUT[2];

        inputs[0].type = NativeMethods.INPUT_KEYBOARD;
        inputs[0].u.ki.wVk = virtualKey;
        inputs[0].u.ki.dwFlags = 0;
        inputs[0].u.ki.dwExtraInfo = NativeMethods.SyntheticTag;

        inputs[1].type = NativeMethods.INPUT_KEYBOARD;
        inputs[1].u.ki.wVk = virtualKey;
        inputs[1].u.ki.dwFlags = KEYEVENTF_KEYUP;
        inputs[1].u.ki.dwExtraInfo = NativeMethods.SyntheticTag;

        Send(inputs);
    }

    /// <summary>
    /// Presses <paramref name="modifiers"/>, taps <paramref name="virtualKey"/>, releases the
    /// modifiers in reverse order. One SendInput call, so nothing can interleave with it.
    /// </summary>
    public static void Chord(ushort virtualKey, params ushort[] modifiers)
    {
        int count = modifiers.Length * 2 + 2;
        NativeMethods.INPUT[] inputs = new NativeMethods.INPUT[count];
        int at = 0;

        foreach (ushort mod in modifiers)
        {
            inputs[at].type = NativeMethods.INPUT_KEYBOARD;
            inputs[at].u.ki.wVk = mod;
            inputs[at].u.ki.dwExtraInfo = NativeMethods.SyntheticTag;
            at++;
        }

        inputs[at].type = NativeMethods.INPUT_KEYBOARD;
        inputs[at].u.ki.wVk = virtualKey;
        inputs[at].u.ki.dwExtraInfo = NativeMethods.SyntheticTag;
        at++;

        inputs[at].type = NativeMethods.INPUT_KEYBOARD;
        inputs[at].u.ki.wVk = virtualKey;
        inputs[at].u.ki.dwFlags = KEYEVENTF_KEYUP;
        inputs[at].u.ki.dwExtraInfo = NativeMethods.SyntheticTag;
        at++;

        for (int i = modifiers.Length - 1; i >= 0; i--)
        {
            inputs[at].type = NativeMethods.INPUT_KEYBOARD;
            inputs[at].u.ki.wVk = modifiers[i];
            inputs[at].u.ki.dwFlags = KEYEVENTF_KEYUP;
            inputs[at].u.ki.dwExtraInfo = NativeMethods.SyntheticTag;
            at++;
        }

        Send(inputs);
    }

    /// <summary>Releases a key that may be physically held, so a chord cannot leave a modifier stuck.</summary>
    public static void ReleaseKey(ushort virtualKey)
    {
        NativeMethods.INPUT[] inputs = new NativeMethods.INPUT[1];

        inputs[0].type = NativeMethods.INPUT_KEYBOARD;
        inputs[0].u.ki.wVk = virtualKey;
        inputs[0].u.ki.dwFlags = KEYEVENTF_KEYUP;
        inputs[0].u.ki.dwExtraInfo = NativeMethods.SyntheticTag;

        Send(inputs);
    }

    /// <summary>A full middle-button click at the cursor's current position.</summary>
    public static void MiddleClick()
    {
        NativeMethods.mouse_event(NativeMethods.MOUSEEVENTF_MIDDLEDOWN, 0, 0, 0, NativeMethods.SyntheticTag);
        NativeMethods.mouse_event(NativeMethods.MOUSEEVENTF_MIDDLEUP, 0, 0, 0, NativeMethods.SyntheticTag);
    }

    /// <summary>Vertical wheel. <paramref name="delta"/> is in WHEEL_DELTA units of 120.</summary>
    public static void Wheel(int delta)
    {
        NativeMethods.mouse_event(NativeMethods.MOUSEEVENTF_WHEEL, 0, 0, unchecked((uint)delta), NativeMethods.SyntheticTag);
    }

    /// <summary>Horizontal wheel.</summary>
    public static void WheelHorizontal(int delta)
    {
        NativeMethods.mouse_event(NativeMethods.MOUSEEVENTF_HWHEEL, 0, 0, unchecked((uint)delta), NativeMethods.SyntheticTag);
    }

    private static void Send(NativeMethods.INPUT[] inputs)
    {
        try
        {
            NativeMethods.SendInput((uint)inputs.Length, inputs, InputSize);
        }
        catch
        {
            // SendInput fails against an elevated foreground window when this process is not
            // elevated. That is a documented limitation, not an error worth surfacing.
        }
    }
}
