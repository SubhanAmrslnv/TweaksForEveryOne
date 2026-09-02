using System;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Media;
using WindowTweaks.Core;
using Application = System.Windows.Application;
using Clipboard = System.Windows.Clipboard;

// WPF and WinForms are both referenced, so Color is ambiguous under ImplicitUsings.
using Color = System.Windows.Media.Color;

namespace WindowTweaks.Features;

/// <summary>
/// Ctrl+Alt+C rewrites the selected text as camelCase, in place.
///
/// HOW IT WORKS, and why it has to work this way: there is no API for "read the selection in whatever
/// application happens to be focused". The only universal channel is the clipboard, so the sequence
/// is copy, transform, paste - and everything awkward in this file comes from that being an
/// inherently racy conversation with another process.
///
/// FOUR CORRECTNESS PROBLEMS THE FIRST VERSION HAD:
///
///   1. IT LEFT THE MODIFIERS PHYSICALLY DOWN. It swallowed the C but the user was still holding
///      Ctrl and Alt, so the synthetic Ctrl+C it then sent arrived as Ctrl+Alt+C - which many
///      applications treat as something else entirely, and which re-entered this same handler. The
///      modifiers are now released before anything is injected.
///
///   2. IT COMPARED AGAINST THE OLD CLIPBOARD TEXT TO DECIDE WHETHER THE COPY WORKED. Copying text
///      identical to what was already on the clipboard therefore looked like a failed copy and did
///      nothing. The clipboard's SEQUENCE NUMBER answers the real question - "did a copy happen" -
///      and it does so without inspecting anyone's clipboard content.
///
///   3. IT DID NOT PUT THE CLIPBOARD BACK. A formatting command should not cost the user whatever
///      they had copied.
///
///   4. IT TRACKED CTRL AND ALT FROM THE HOOK, so a modifier release missed while the hook was not
///      installed left the feature convinced Ctrl was held forever - after which a bare C triggered
///      it. State is read from the OS instead.
/// </summary>
public class TextFormatFeature : IDisposable
{
    private const string HookOwner = nameof(TextFormatFeature);

    private const ushort VK_CONTROL = 0x11;
    private const ushort VK_MENU = 0x12;
    private const ushort VK_SHIFT = 0x10;
    private const ushort VK_C = 0x43;
    private const ushort VK_V = 0x56;

    private readonly ClipboardOsdFeature _osd;

    /// <summary>
    /// One transformation at a time. The chord is swallowed, but auto-repeat still delivers a
    /// key-down every 32 ms while it is held, and two of these running at once would each fight the
    /// other for the clipboard.
    /// </summary>
    private volatile bool _running;

    public bool IsEnabled { get; private set; }

    public TextFormatFeature(ClipboardOsdFeature osd)
    {
        _osd = osd;
    }

    public void SetEnabled(bool enabled)
    {
        if (enabled == IsEnabled) return;
        IsEnabled = enabled;

        if (enabled) KeyboardHook.Subscribe(HookOwner, OnKey);
        else KeyboardHook.Unsubscribe(HookOwner);
    }

    public void Toggle() => SetEnabled(!IsEnabled);

    private bool OnKey(KeyboardHook.KeyEvent e)
    {
        if (!e.IsKeyDown || e.IsInjected) return false;
        if (e.VirtualKey != VK_C) return false;

        bool ctrl = (NativeMethods.GetAsyncKeyState(VK_CONTROL) & 0x8000) != 0;
        bool alt = (NativeMethods.GetAsyncKeyState(VK_MENU) & 0x8000) != 0;
        if (!ctrl || !alt) return false;

        if (_running) return true;
        _running = true;

        // Release what the user is holding BEFORE anything is injected. Without this the synthetic
        // Ctrl+C below arrives as Ctrl+Alt+C, because Alt is still physically down.
        SyntheticInput.ReleaseKey(VK_MENU);
        SyntheticInput.ReleaseKey(VK_SHIFT);
        SyntheticInput.ReleaseKey(VK_CONTROL);

        _ = Run();

        // Swallowed: Ctrl+Alt+C is this feature's chord, and letting it through as well would put a
        // stray character or an application shortcut in the middle of the edit.
        return true;
    }

    private async Task Run()
    {
        string? saved = null;

        // Set the moment the synthetic Ctrl+C succeeds. From then on the user's own clipboard has
        // been overwritten with the selection, so EVERY exit path owes them a restore - including
        // the ones that decide there is nothing to do. Returning early without restoring silently
        // cost the user whatever they had copied, which is a worse outcome than the feature simply
        // not working.
        bool clipboardTaken = false;

        try
        {
            uint before = NativeMethods.GetClipboardSequenceNumber();

            saved = await ReadClipboard().ConfigureAwait(false);

            // Ctrl+C into the focused application. Modifiers are already released, so this is a
            // clean two-key chord.
            SyntheticInput.Chord(VK_C, VK_CONTROL);

            // Wait for the copy to land. Polling the sequence number rather than sleeping a fixed
            // 100 ms: a large selection in a slow application takes longer than that, and a small
            // one in a fast one takes far less.
            if (!await WaitForClipboardChange(before, 600).ConfigureAwait(false))
            {
                // Nothing was selected, or the application does not support copying. Do nothing at
                // all rather than pasting the previous clipboard over the cursor - and nothing was
                // taken, so there is nothing to put back either.
                return;
            }

            clipboardTaken = true;

            string? selected = await ReadClipboard().ConfigureAwait(false);
            if (string.IsNullOrWhiteSpace(selected)) return;

            string transformed = ToCamelCase(selected);
            if (transformed.Length == 0 || transformed == selected) return;

            if (!await WriteClipboard(transformed).ConfigureAwait(false)) return;

            // A short settle before pasting: the clipboard owner change has to be seen by the target
            // application, which learns about it from a window message.
            await Task.Delay(40).ConfigureAwait(false);

            SyntheticInput.Chord(VK_V, VK_CONTROL);

            _osd.Announce("camelCase", SoundId.Transform, Color.FromRgb(0xB8, 0xE9, 0xD0));

            // The paste has to have happened before the clipboard is put back, hence the wait.
            await Task.Delay(140).ConfigureAwait(false);
        }
        catch
        {
            // Another process can own the clipboard, and every call here can fail because of it.
            // A failed transformation must leave the user's text alone, not raise a dialog.
        }
        finally
        {
            try
            {
                if (clipboardTaken && saved != null) await WriteClipboard(saved).ConfigureAwait(false);
            }
            catch
            {
            }

            _running = false;
        }
    }

    private static async Task<bool> WaitForClipboardChange(uint before, int timeoutMs)
    {
        for (int waited = 0; waited < timeoutMs; waited += 20)
        {
            await Task.Delay(20).ConfigureAwait(false);
            if (NativeMethods.GetClipboardSequenceNumber() != before) return true;
        }

        return false;
    }

    /// <summary>
    /// The clipboard is a single-threaded-apartment affair and WPF's wrapper insists on the UI
    /// thread, so every access hops there. These are a handful of calls per gesture, not per frame.
    /// </summary>
    private static async Task<string?> ReadClipboard()
    {
        Application? app = Application.Current;
        if (app == null) return null;

        string? text = null;

        await app.Dispatcher.InvokeAsync(() =>
        {
            try
            {
                text = Clipboard.ContainsText() ? Clipboard.GetText() : null;
            }
            catch
            {
                text = null;
            }
        });

        return text;
    }

    private static async Task<bool> WriteClipboard(string text)
    {
        Application? app = Application.Current;
        if (app == null) return false;

        bool ok = false;

        await app.Dispatcher.InvokeAsync(() =>
        {
            try
            {
                Clipboard.SetText(text);
                ok = true;
            }
            catch
            {
                ok = false;
            }
        });

        return ok;
    }

    /// <summary>
    /// Splits on anything that is not a letter or a digit, lower-cases the first word and
    /// capitalises the rest. "user first name", "user_first_name" and "User-First-Name" all become
    /// "userFirstName".
    ///
    /// A WORD'S TAIL IS LOWER-CASED ONLY IF THE WHOLE WORD IS UPPER-CASE. That distinction is the
    /// difference between two wrong answers. Lower-casing every tail turns the deliberate acronym in
    /// "userID" into "userId"; keeping every tail as typed turns "USER NAME" - which is exactly the
    /// shape of text someone reaches for this command with - into "uSERNAME". Judging it per word
    /// gives "userName" and "userID" from the same rule.
    /// </summary>
    internal static string ToCamelCase(string text)
    {
        if (string.IsNullOrWhiteSpace(text)) return string.Empty;

        StringBuilder result = new(text.Length);
        StringBuilder word = new(16);
        bool anyWordEmitted = false;

        void FlushWord()
        {
            if (word.Length == 0) return;

            bool allUpper = true;
            for (int i = 0; i < word.Length; i++)
            {
                if (char.IsLower(word[i]))
                {
                    allUpper = false;
                    break;
                }
            }

            for (int i = 0; i < word.Length; i++)
            {
                char c = word[i];

                if (i == 0)
                {
                    // The very first word of the whole string is lower, every later one is capital.
                    result.Append(anyWordEmitted ? char.ToUpperInvariant(c) : char.ToLowerInvariant(c));
                    continue;
                }

                result.Append(allUpper ? char.ToLowerInvariant(c) : c);
            }

            anyWordEmitted = true;
            word.Clear();
        }

        foreach (char c in text)
        {
            if (char.IsLetterOrDigit(c))
            {
                word.Append(c);
                continue;
            }

            // The separator itself is dropped, and it ends the current word.
            FlushWord();
        }

        FlushWord();

        return result.ToString();
    }

    public void Dispose()
    {
        SetEnabled(false);
    }
}
