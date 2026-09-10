using System;
using Microsoft.Win32;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

/// <summary>
/// Snappy Taskbar Previews Feature (macOS Instant Dock Preview Parity).
///
/// Reduces taskbar thumbnail hover latency from the Windows default 400ms down to 60ms
/// via ExtendedUIHoverTime tuning, restoring default preferences on teardown.
/// </summary>
public class SnappyTaskbarPreviewsFeature : IDisposable
{
    private const string RegKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced";
    private const string ValueName = "ExtendedUIHoverTime";

    private object? _originalValue;
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

        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(RegKeyPath, writable: true);
            if (key != null)
            {
                _originalValue = key.GetValue(ValueName);
                key.SetValue(ValueName, 60, RegistryValueKind.DWord);
                _modified = true;
            }
        }
        catch
        {
            // Registry access failed (e.g. group policy restriction)
        }
    }

    private void Stop()
    {
        if (!_modified) return;

        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(RegKeyPath, writable: true);
            if (key != null)
            {
                if (_originalValue != null)
                {
                    key.SetValue(ValueName, _originalValue, RegistryValueKind.DWord);
                }
                else
                {
                    key.DeleteValue(ValueName, throwOnMissingValue: false);
                }
            }
        }
        catch
        {
        }

        _modified = false;
        _originalValue = null;
    }

    public void Dispose()
    {
        SetEnabled(false);
    }
}
