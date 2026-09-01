using System;
using System.Collections.Generic;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

/// <summary>
/// Game Mode (Shift+Alt+F12): switch off everything that would interfere with a full-screen game,
/// then put it all back exactly as it was.
///
/// THE SUPPRESSION IS AN IN-MEMORY OVERLAY AND MUST NEVER REACH settings.json. This is the whole
/// reason the class exists rather than the hotkey just calling eighteen toggles: a shutdown,
/// restart or reload while Game Mode was on would otherwise persist every one of those features as
/// "off" - the user's entire configuration, gone on the next launch, with nothing left to restore
/// it from.
///
/// Three defences, because one of them is not enough:
///   1. Every state change goes through FeatureRegistry.Set(..., persist: false).
///   2. SettingsStore.SuppressPersistence is held for the duration, so any OTHER writer that runs
///      while Game Mode is active also cannot record the overlay.
///   3. Settings are FLUSHED TO DISK BEFORE the first flag is touched. That covers the one case no
///      exit handler can - a power cut or a Stop-Process -Force mid-session.
/// </summary>
public class GameModeFeature
{
    private readonly Dictionary<string, bool> _suspended = new();

    public bool IsActive { get; private set; }

    /// <summary>Raised on enter/exit so the tray and the settings window can reflect it.</summary>
    public event Action<bool>? StateChanged;

    public void Toggle()
    {
        if (IsActive) Exit();
        else Enter();
    }

    public void Enter()
    {
        if (IsActive) return;

        // Get the real configuration on disk while it is still the real configuration.
        SettingsStore.Flush();

        _suspended.Clear();
        IsActive = true;
        SettingsStore.SuppressPersistence = true;

        try
        {
            foreach (string key in FeatureKeys.GameModeSuspends)
            {
                FeatureDescriptor? d = FeatureRegistry.Find(key);
                if (d == null) continue;

                _suspended[key] = FeatureRegistry.IsEnabled(key);
                FeatureRegistry.Set(key, false, persist: false);
            }
        }
        finally
        {
            StateChanged?.Invoke(true);
        }
    }

    public void Exit()
    {
        if (!IsActive) return;

        try
        {
            foreach (KeyValuePair<string, bool> kv in _suspended)
            {
                FeatureRegistry.Set(kv.Key, kv.Value, persist: false);
            }
        }
        finally
        {
            _suspended.Clear();
            IsActive = false;

            // Only now may anything be written again. Restoring first and lifting the suppression
            // second means the file can never observe the overlay.
            SettingsStore.SuppressPersistence = false;
            StateChanged?.Invoke(false);
        }
    }
}
