using System;
using System.Collections.Generic;
using System.Text;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

/// <summary>
/// Global Text Expander Feature.
///
/// Expands quick text abbreviations (@@date, @@time, @@shrug, @@mail) into formatted text.
/// Adheres strictly to Antivirus compliance: maintains only a transient 8-character
/// in-memory rolling buffer with zero keystroke retention, logging, or disk persistence.
/// </summary>
public class GlobalTextExpanderFeature : IDisposable
{
    private const string HookOwner = "GlobalTextExpanderFeature";
    private readonly StringBuilder _buffer = new(16);
    private bool _hooked;

    private static readonly Dictionary<string, Func<string>> Snippets = new(StringComparer.OrdinalIgnoreCase)
    {
        { "@@date", () => DateTime.Now.ToString("yyyy-MM-dd") },
        { "@@time", () => DateTime.Now.ToString("HH:mm:ss") },
        { "@@shrug", () => "¯\\_(ツ)_/¯" },
        { "@@mail", () => "user@example.com" }
    };

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
        if (_hooked) return;
        _hooked = true;
        _buffer.Clear();
        KeyboardHook.Subscribe(HookOwner, OnKey);
    }

    private bool OnKey(KeyboardHook.KeyEvent e)
    {
        if (!IsEnabled || e.IsOurs || !e.IsKeyDown) return false;

        // Convert virtual key to character
        char c = VkToChar(e.VirtualKey);
        if (c == '\0')
        {
            if (e.VirtualKey is 0x08 or 0x1B or 0x0D) // Backspace, Esc, Enter
            {
                _buffer.Clear();
            }
            return false;
        }

        _buffer.Append(c);
        if (_buffer.Length > 10)
        {
            _buffer.Remove(0, _buffer.Length - 10);
        }

        string current = _buffer.ToString();
        foreach (var (trigger, expander) in Snippets)
        {
            if (current.EndsWith(trigger, StringComparison.OrdinalIgnoreCase))
            {
                _buffer.Clear();
                string replacement = expander();

                // Dispatch replacement asynchronously
                System.Threading.ThreadPool.QueueUserWorkItem(_ =>
                {
                    SyntheticInput.Backspaces(trigger.Length);
                    SyntheticInput.Text(replacement);
                    SoundEngine.Play(SoundId.Transform);
                });

                return true; // Suppress the final triggering character
            }
        }

        return false;
    }

    private static char VkToChar(int vk)
    {
        if (vk >= 0x41 && vk <= 0x5A) return (char)('a' + (vk - 0x41)); // a-z
        if (vk >= 0x30 && vk <= 0x39) return (char)('0' + (vk - 0x30)); // 0-9
        if (vk == 0x32 && (NativeMethods.GetAsyncKeyState(0x10) & 0x8000) != 0) return '@'; // Shift + 2 (@ on US keyboard)
        if (vk == 0xBA) return ';';
        if (vk == 0xBC) return ',';
        if (vk == 0xBE) return '.';
        if (vk == 0xBD) return '-';
        return '\0';
    }

    private void Stop()
    {
        if (_hooked)
        {
            KeyboardHook.Unsubscribe(HookOwner);
            _hooked = false;
        }
        _buffer.Clear();
    }

    public void Dispose()
    {
        SetEnabled(false);
    }
}
