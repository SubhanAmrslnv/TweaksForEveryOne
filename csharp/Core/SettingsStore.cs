using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text.Json;

namespace WindowTweaks.Core;

/// <summary>
/// The one place settings are read and written: %APPDATA%\WindowTweaks\settings.json.
///
/// Writes are DEBOUNCED. Toggling a feature happens on an input path (a hotkey, a checkbox), and
/// a synchronous file write there costs milliseconds on the same thread that runs every timer and
/// hook in the process. Set() only marks the store dirty; a 700 ms one-shot does the write.
/// Flush() forces it, and app exit calls Flush() because there is no idle on the way out.
///
/// Nothing here throws. A corrupt or unreadable file means "use defaults", never a crash on
/// startup - the caller always supplies the default alongside the key.
/// </summary>
internal static class SettingsStore
{
    private const int DebounceMs = 700;

    private static readonly object Gate = new();
    private static readonly Dictionary<string, string> Values = new(StringComparer.OrdinalIgnoreCase);

    private static System.Threading.Timer? _debounce;
    private static bool _dirty;
    private static bool _loaded;

    /// <summary>
    /// While true, Set() updates memory but never marks the store dirty. Game Mode switches ~40
    /// features off in memory; persisting that overlay would write the user's whole configuration
    /// as "off" and there would be nothing left to restore it from on the next launch.
    /// </summary>
    public static bool SuppressPersistence { get; set; }

    public static string FilePath
    {
        get
        {
            string dir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                "WindowTweaks");
            return Path.Combine(dir, "settings.json");
        }
    }

    public static void Load()
    {
        lock (Gate)
        {
            if (_loaded) return;
            _loaded = true;

            try
            {
                string path = FilePath;
                if (!File.Exists(path)) return;

                string json = File.ReadAllText(path);
                if (string.IsNullOrWhiteSpace(json)) return;

                Dictionary<string, string>? loaded =
                    JsonSerializer.Deserialize<Dictionary<string, string>>(json);
                if (loaded == null) return;

                foreach (KeyValuePair<string, string> kv in loaded) Values[kv.Key] = kv.Value;
            }
            catch
            {
                // Unreadable or corrupt: carry on with defaults rather than failing to start.
            }
        }
    }

    public static bool GetBool(string key, bool fallback)
    {
        string? raw = Get(key);
        if (raw == null) return fallback;
        if (bool.TryParse(raw, out bool b)) return b;
        if (int.TryParse(raw, NumberStyles.Integer, CultureInfo.InvariantCulture, out int i)) return i != 0;
        return fallback;
    }

    public static int GetInt(string key, int fallback, int lo = int.MinValue, int hi = int.MaxValue)
    {
        string? raw = Get(key);
        if (raw == null || !int.TryParse(raw, NumberStyles.Integer, CultureInfo.InvariantCulture, out int v))
            return Clamp(fallback, lo, hi);
        return Clamp(v, lo, hi);
    }

    public static double GetDouble(string key, double fallback, double lo = double.MinValue, double hi = double.MaxValue)
    {
        string? raw = Get(key);
        if (raw == null || !double.TryParse(raw, NumberStyles.Float, CultureInfo.InvariantCulture, out double v))
            return Math.Clamp(fallback, lo, hi);
        return Math.Clamp(v, lo, hi);
    }

    public static string GetString(string key, string fallback)
    {
        string? raw = Get(key);
        return raw ?? fallback;
    }

    public static void SetString(string key, string value)
    {
        Set(key, value ?? string.Empty);
    }

    public static void SetBool(string key, bool value)
    {
        Set(key, value ? "true" : "false");
    }

    public static void SetInt(string key, int value)
    {
        Set(key, value.ToString(CultureInfo.InvariantCulture));
    }

    public static void SetDouble(string key, double value)
    {
        Set(key, value.ToString("R", CultureInfo.InvariantCulture));
    }

    private static string? Get(string key)
    {
        Load();
        lock (Gate)
        {
            return Values.TryGetValue(key, out string? v) ? v : null;
        }
    }

    private static void Set(string key, string value)
    {
        Load();
        lock (Gate)
        {
            if (Values.TryGetValue(key, out string? existing) && existing == value) return;
            Values[key] = value;

            if (SuppressPersistence) return;

            _dirty = true;
            _debounce ??= new System.Threading.Timer(_ => Flush(), null, System.Threading.Timeout.Infinite, System.Threading.Timeout.Infinite);
            _debounce.Change(DebounceMs, System.Threading.Timeout.Infinite);
        }
    }

    /// <summary>Write now if anything is pending. Safe to call from any thread, and from exit.</summary>
    public static void Flush()
    {
        string json;
        lock (Gate)
        {
            if (!_dirty) return;
            _dirty = false;
            try
            {
                json = JsonSerializer.Serialize(Values, new JsonSerializerOptions { WriteIndented = true });
            }
            catch
            {
                return;
            }
        }

        try
        {
            string path = FilePath;
            string? dir = Path.GetDirectoryName(path);
            if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);

            // Write to a temp file and move over the target, so a kill mid-write cannot leave a
            // truncated settings file behind.
            string tmp = path + ".tmp";
            File.WriteAllText(tmp, json);
            File.Move(tmp, path, overwrite: true);
        }
        catch
        {
            // Disk full, permissions, a locked file: losing a settings write is not worth a crash.
        }
    }

    private static int Clamp(int v, int lo, int hi)
    {
        return v < lo ? lo : (v > hi ? hi : v);
    }
}
