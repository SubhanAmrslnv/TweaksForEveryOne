using System;
using System.Globalization;
using System.Net.Http;
using System.Text.Json;
using System.Threading.Tasks;

namespace WindowTweaks.Core;

/// <summary>
/// Current conditions for the taskbar clock, from open-meteo.com.
///
/// THIS IS THE ONLY CODE IN THE APPLICATION THAT TOUCHES THE NETWORK, and it is deliberately inert
/// unless the user has both switched weather on AND typed a city. Out of the box the clock shows time
/// and date and the process makes no outbound connection at all. That matters for more than privacy:
/// an unsigned binary that installs input hooks AND phones out is scored much more harshly by
/// antivirus heuristics than one that does not (see docs/ANTIVIRUS.md). Keep the early return.
///
/// Why open-meteo and not wttr.in: measured during the earlier implementation, wttr.in answers HTTP
/// 200 with its HTML landing page instead of an error status whenever it will not serve a reading -
/// it did that for one city while answering another in plain text, did it for a bare format request,
/// and did it for everything after roughly twenty requests in a few minutes. A success status
/// carrying the wrong content type is far worse to code against than an honest failure. open-meteo
/// returns real JSON and needs no API key.
///
/// Two requests, not one per tick: the city is geocoded ONCE and the coordinates are cached for as
/// long as the setting holds, so the steady state is one request per refresh interval.
/// </summary>
internal static class WeatherService
{
    public const string LocationKey = "clock.location";
    public const string UnitsKey = "clock.units"; // "metric" or "imperial"

    private const int NormalIntervalMinutes = 15;
    private const int MaxBackoffMinutes = 15;

    /// <summary>One reading. Every field is optional except the temperature.</summary>
    public sealed class Reading
    {
        public double TemperatureC { get; init; }
        public double WindSpeed { get; init; }
        public int WeatherCode { get; init; }
        public bool Metric { get; init; }

        public string Glyph => GlyphForCode(WeatherCode);
        public string Condition => ConditionForCode(WeatherCode);

        public string TemperatureText =>
            Math.Round(TemperatureC).ToString("0", CultureInfo.InvariantCulture) + (Metric ? "°C" : "°F");

        public string WindText =>
            Math.Round(WindSpeed).ToString("0", CultureInfo.InvariantCulture) + (Metric ? " km/h" : " mph");
    }

    // A single HttpClient for the process. Creating one per request exhausts sockets under load, and
    // a short timeout matters because this runs behind a UI timer.
    private static readonly HttpClient Http = CreateClient();

    private static HttpClient CreateClient()
    {
        HttpClient c = new() { Timeout = TimeSpan.FromSeconds(8) };
        // Identify ourselves honestly. An anonymous or spoofed user agent is both rude to a free
        // service and the sort of thing that gets traffic scored as suspicious.
        c.DefaultRequestHeaders.UserAgent.ParseAdd("WindowTweaks/1.0 (taskbar clock)");
        return c;
    }

    private static string _geocodedFor = string.Empty;
    private static double _lat;
    private static double _lon;
    private static bool _haveCoords;

    private static DateTime _nextAttempt = DateTime.MinValue;
    private static int _failures;

    public static Reading? Current { get; private set; }

    /// <summary>True once a reading has ever arrived, so the UI can show a placeholder until then.</summary>
    public static bool HasReading => Current != null;

    public static string Location => SettingsStore.GetString(LocationKey, string.Empty).Trim();

    public static bool Metric =>
        !string.Equals(SettingsStore.GetString(UnitsKey, "metric"), "imperial", StringComparison.OrdinalIgnoreCase);

    /// <summary>
    /// Fetch if it is time to. Returns immediately - and makes no request whatsoever - when weather
    /// is off or no city is set. Safe to call from a UI timer; nothing here blocks.
    /// </summary>
    public static void Poll(bool weatherEnabled)
    {
        if (!weatherEnabled)
        {
            Current = null;
            return;
        }

        string city = Location;
        if (city.Length == 0)
        {
            Current = null;
            return;
        }

        if (DateTime.UtcNow < _nextAttempt) return;

        // Claim the slot before starting, so a slow request cannot be launched twice.
        _nextAttempt = DateTime.UtcNow.AddMinutes(1);

        _ = FetchAsync(city);
    }

    /// <summary>Drop cached coordinates, e.g. after the city setting changed.</summary>
    public static void InvalidateLocation()
    {
        _haveCoords = false;
        _geocodedFor = string.Empty;
        Current = null;
        _failures = 0;
        _nextAttempt = DateTime.MinValue;
    }

    private static async Task FetchAsync(string city)
    {
        try
        {
            if (!_haveCoords || !string.Equals(_geocodedFor, city, StringComparison.OrdinalIgnoreCase))
            {
                if (!await GeocodeAsync(city))
                {
                    Failed();
                    return;
                }
            }

            bool metric = Metric;
            string url =
                "https://api.open-meteo.com/v1/forecast" +
                "?latitude=" + _lat.ToString("0.####", CultureInfo.InvariantCulture) +
                "&longitude=" + _lon.ToString("0.####", CultureInfo.InvariantCulture) +
                "&current=temperature_2m,weather_code,wind_speed_10m" +
                "&temperature_unit=" + (metric ? "celsius" : "fahrenheit") +
                "&wind_speed_unit=" + (metric ? "kmh" : "mph");

            using HttpResponseMessage response = await Http.GetAsync(url);
            if (!response.IsSuccessStatusCode)
            {
                Failed();
                return;
            }

            string json = await response.Content.ReadAsStringAsync();

            using JsonDocument doc = JsonDocument.Parse(json);
            if (!doc.RootElement.TryGetProperty("current", out JsonElement current))
            {
                Failed();
                return;
            }

            // The temperature is the part that has to be there; the glyph and the wind are additive,
            // so a reply missing either still produces a usable reading.
            if (!current.TryGetProperty("temperature_2m", out JsonElement tempEl) ||
                !tempEl.TryGetDouble(out double temp))
            {
                Failed();
                return;
            }

            double wind = 0;
            if (current.TryGetProperty("wind_speed_10m", out JsonElement windEl))
                windEl.TryGetDouble(out wind);

            int code = -1;
            if (current.TryGetProperty("weather_code", out JsonElement codeEl))
                codeEl.TryGetInt32(out code);

            Current = new Reading
            {
                TemperatureC = temp,
                WindSpeed = wind,
                WeatherCode = code,
                Metric = metric
            };

            _failures = 0;
            _nextAttempt = DateTime.UtcNow.AddMinutes(NormalIntervalMinutes);
        }
        catch
        {
            // No network, DNS failure, malformed JSON, a service outage. A weather lookup failing is
            // never worth an exception reaching the user; the clock keeps showing time and date.
            Failed();
        }
    }

    private static async Task<bool> GeocodeAsync(string city)
    {
        string url = "https://geocoding-api.open-meteo.com/v1/search?count=1&language=en&format=json&name=" +
                     Uri.EscapeDataString(city);

        using HttpResponseMessage response = await Http.GetAsync(url);
        if (!response.IsSuccessStatusCode) return false;

        string json = await response.Content.ReadAsStringAsync();

        using JsonDocument doc = JsonDocument.Parse(json);
        if (!doc.RootElement.TryGetProperty("results", out JsonElement results) ||
            results.ValueKind != JsonValueKind.Array ||
            results.GetArrayLength() == 0)
        {
            // A city that does not resolve is a user typo, not a transient error. Stop retrying it
            // hard - the backoff below will keep the request rate low until they fix it.
            return false;
        }

        JsonElement first = results[0];
        if (!first.TryGetProperty("latitude", out JsonElement latEl) || !latEl.TryGetDouble(out double lat)) return false;
        if (!first.TryGetProperty("longitude", out JsonElement lonEl) || !lonEl.TryGetDouble(out double lon)) return false;

        _lat = lat;
        _lon = lon;
        _geocodedFor = city;
        _haveCoords = true;
        return true;
    }

    /// <summary>
    /// Back off on failure rather than retrying into a rate limit: each failure triples the wait,
    /// capped at 15 minutes.
    /// </summary>
    private static void Failed()
    {
        _failures++;
        int minutes = Math.Min(MaxBackoffMinutes, (int)Math.Pow(3, Math.Min(_failures, 3)));
        _nextAttempt = DateTime.UtcNow.AddMinutes(minutes);
    }

    /// <summary>
    /// WMO weather code to a single glyph.
    ///
    /// EVERY GLYPH HERE IS IN THE BASIC MULTILINGUAL PLANE, on purpose. The obvious weather emoji
    /// (U+1F324 sun-behind-cloud and friends) live in the astral plane and need Segoe UI Emoji;
    /// WPF does not render colour emoji, and a font fallback miss shows tofu boxes. These live in
    /// Segoe UI Symbol, which fallback finds reliably, and render as clean monochrome glyphs against
    /// the taskbar.
    /// </summary>
    private static string GlyphForCode(int code) => code switch
    {
        0 => "☀",                        // clear sky            sun
        1 or 2 => "⛅",                   // mainly/partly cloudy sun behind cloud
        3 => "☁",                        // overcast             cloud
        45 or 48 => "░",                 // fog                  light shade
        51 or 53 or 55 or 56 or 57 => "☂", // drizzle            umbrella
        61 or 63 or 65 or 66 or 67 => "☔", // rain               umbrella with rain
        71 or 73 or 75 or 77 => "❄",     // snow                 snowflake
        80 or 81 or 82 => "☔",           // rain showers         umbrella with rain
        85 or 86 => "❄",                 // snow showers         snowflake
        95 or 96 or 99 => "⛈",           // thunderstorm         thunder cloud and rain
        _ => "☁"
    };

    private static string ConditionForCode(int code) => code switch
    {
        0 => "Clear",
        1 => "Mainly clear",
        2 => "Partly cloudy",
        3 => "Overcast",
        45 or 48 => "Fog",
        51 or 53 or 55 => "Drizzle",
        56 or 57 => "Freezing drizzle",
        61 or 63 or 65 => "Rain",
        66 or 67 => "Freezing rain",
        71 or 73 or 75 or 77 => "Snow",
        80 or 81 or 82 => "Showers",
        85 or 86 => "Snow showers",
        95 => "Thunderstorm",
        96 or 99 => "Thunderstorm, hail",
        _ => ""
    };
}
