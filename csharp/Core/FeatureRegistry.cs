using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;

namespace WindowTweaks.Core;

/// <summary>
/// One entry per user-switchable behaviour. This is the single source of truth for whether a
/// feature is on, and it is what the settings window renders from - so a checkbox, a tray item
/// and a hotkey all go through the same place and cannot drift apart.
/// </summary>
internal sealed class FeatureDescriptor
{
    public required string Key { get; init; }
    public required string Title { get; init; }
    public required string Description { get; init; }
    public required string Page { get; init; }
    public string? Group { get; init; }
    public string? Hotkey { get; init; }
    public bool DefaultEnabled { get; init; }

    /// <summary>
    /// Called when the state actually changes, to start or stop the feature's hooks and timers.
    /// Null for a feature that is purely a GATE - a hotkey command that consults IsEnabled before
    /// acting and owns no background state (plain paste, gravity close, quick folder jump).
    /// </summary>
    public Action<bool>? Apply { get; init; }

    /// <summary>Set when the feature cannot be reached because its hotkey failed to register.</summary>
    public bool HotkeyUnavailable { get; internal set; }

    internal bool Enabled { get; set; }
}

/// <summary>
/// The registry owns the enabled state rather than each feature, because only four of the feature
/// classes expose one and their Toggle() methods flip a private field. Every path that changes a
/// feature's state goes through here, so the registry's view stays authoritative.
/// </summary>
internal static class FeatureRegistry
{
    private static readonly List<FeatureDescriptor> All = new();
    private static readonly Dictionary<string, FeatureDescriptor> ByKey = new(StringComparer.OrdinalIgnoreCase);

    /// <summary>Raised after any state change, so an open settings window can refresh.</summary>
    public static event Action<FeatureDescriptor>? Changed;

    public static ReadOnlyCollection<FeatureDescriptor> Items => All.AsReadOnly();

    public static void Register(FeatureDescriptor descriptor)
    {
        if (ByKey.ContainsKey(descriptor.Key))
            throw new InvalidOperationException("Duplicate feature key: " + descriptor.Key);

        All.Add(descriptor);
        ByKey[descriptor.Key] = descriptor;
    }

    /// <summary>
    /// Read every registered feature's stored value and apply it. Called once at startup, after
    /// all features are registered.
    /// </summary>
    public static void ApplyStoredState()
    {
        foreach (FeatureDescriptor d in All)
        {
            bool want = SettingsStore.GetBool(d.Key, d.DefaultEnabled);
            d.Enabled = want;

            if (d.Apply == null || !want) continue;

            try
            {
                d.Apply(true);
            }
            catch (Exception ex)
            {
                // One feature failing to start must not take the whole app down with it.
                System.Diagnostics.Debug.WriteLine($"Feature '{d.Key}' failed to start: {ex.Message}");
                d.Enabled = false;
            }
        }
    }

    public static bool IsEnabled(string key)
    {
        return ByKey.TryGetValue(key, out FeatureDescriptor? d) && d.Enabled;
    }

    public static FeatureDescriptor? Find(string key)
    {
        return ByKey.TryGetValue(key, out FeatureDescriptor? d) ? d : null;
    }

    public static IEnumerable<string> Pages()
    {
        HashSet<string> seen = new();
        foreach (FeatureDescriptor d in All)
        {
            if (seen.Add(d.Page)) yield return d.Page;
        }
    }

    public static IEnumerable<FeatureDescriptor> ForPage(string page)
    {
        foreach (FeatureDescriptor d in All)
        {
            if (string.Equals(d.Page, page, StringComparison.OrdinalIgnoreCase)) yield return d;
        }
    }

    public static void Toggle(string key)
    {
        if (ByKey.TryGetValue(key, out FeatureDescriptor? d)) Set(key, !d.Enabled);
    }

    /// <param name="persist">
    /// False for an in-memory overlay such as Game Mode, which must never reach settings.json.
    /// </param>
    public static void Set(string key, bool enabled, bool persist = true)
    {
        if (!ByKey.TryGetValue(key, out FeatureDescriptor? d)) return;
        if (d.Enabled == enabled) return;

        d.Enabled = enabled;

        if (d.Apply != null)
        {
            try
            {
                d.Apply(enabled);
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"Feature '{key}' failed to {(enabled ? "start" : "stop")}: {ex.Message}");
            }
        }

        if (persist) SettingsStore.SetBool(key, enabled);

        Changed?.Invoke(d);
    }

    /// <summary>
    /// Stop everything that is running, without touching stored state. Used on exit so a feature
    /// cannot leave an overlay on screen or a foreign window modified.
    /// </summary>
    public static void StopAll()
    {
        foreach (FeatureDescriptor d in All)
        {
            if (d.Apply == null || !d.Enabled) continue;
            try
            {
                d.Apply(false);
            }
            catch
            {
                // Best effort on the way out.
            }
        }
    }
}
