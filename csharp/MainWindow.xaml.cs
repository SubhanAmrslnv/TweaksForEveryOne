using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using WindowTweaks.Core;
// WPF and WinForms are both referenced, so these names need pinning under ImplicitUsings.
using CheckBox = System.Windows.Controls.CheckBox;
using HorizontalAlignment = System.Windows.HorizontalAlignment;
using Orientation = System.Windows.Controls.Orientation;
using TextBox = System.Windows.Controls.TextBox;

namespace WindowTweaks;

/// <summary>
/// The settings window, built from FeatureRegistry.
///
/// It used to be a mock: every page was a list of hardcoded checkboxes with literal check states,
/// wired to nothing. Ticking one changed no feature and no value was ever read back, and in places
/// it offered switches for features that had no off switch at all.
///
/// Now every row IS its feature. There is no Save button, because there is nothing to save: a switch
/// applies immediately through FeatureRegistry, which persists it. That also means the window has to
/// listen for changes made elsewhere - a hotkey or Game Mode can flip a feature while this window is
/// open, and the switch has to follow.
/// </summary>
public partial class MainWindow : Window
{
    private const string TuningPage = "Tuning";

    private readonly Dictionary<string, CheckBox> _switches = new();

    /// <summary>
    /// Set while we are writing a switch's state FROM the registry, so the Checked handler does not
    /// turn a refresh into a user action and bounce it back.
    /// </summary>
    private bool _suppressEvents;

    public MainWindow()
    {
        InitializeComponent();

        SettingsPathText.Text = SettingsStore.FilePath;

        BuildSidebar();
        FeatureRegistry.Changed += OnFeatureChanged;
        Closed += (_, _) => FeatureRegistry.Changed -= OnFeatureChanged;

        UpdateStatus();
    }

    private void BuildSidebar()
    {
        foreach (string page in FeatureRegistry.Pages())
        {
            SidebarList.Items.Add(new ListBoxItem { Content = page, Tag = page });
        }
        SidebarList.Items.Add(new ListBoxItem { Content = TuningPage, Tag = TuningPage });

        if (SidebarList.Items.Count > 0) SidebarList.SelectedIndex = 0;
    }

    private void SidebarList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (SidebarList.SelectedItem is not ListBoxItem item) return;

        string page = item.Tag?.ToString() ?? string.Empty;
        MainContent.Content = page == TuningPage ? BuildTuningPage() : BuildFeaturePage(page);
    }

    // -----------------------------------------------------------------------------------------
    // Feature pages
    // -----------------------------------------------------------------------------------------

    private UIElement BuildFeaturePage(string page)
    {
        StackPanel panel = new();

        panel.Children.Add(new TextBlock { Text = page, Style = (Style)FindResource("HeaderStyle") });
        panel.Children.Add(new TextBlock
        {
            Text = "Changes apply immediately and are remembered.",
            Style = (Style)FindResource("DescriptionStyle")
        });

        string? lastGroup = null;

        foreach (FeatureDescriptor d in FeatureRegistry.ForPage(page))
        {
            if (d.Group != null && d.Group != lastGroup)
            {
                lastGroup = d.Group;
                panel.Children.Add(new TextBlock
                {
                    Text = d.Group.ToUpperInvariant(),
                    Style = (Style)FindResource("SubHeaderStyle")
                });
            }

            panel.Children.Add(BuildRow(d));
        }

        return panel;
    }

    private UIElement BuildRow(FeatureDescriptor d)
    {
        StackPanel row = new() { Margin = new Thickness(0, 0, 0, 14) };

        CheckBox toggle = new()
        {
            Content = d.Title,
            Style = (Style)FindResource("ToggleSwitchStyle"),
            IsChecked = FeatureRegistry.IsEnabled(d.Key),
            Tag = d.Key
        };

        toggle.Checked += OnSwitchChanged;
        toggle.Unchecked += OnSwitchChanged;

        // A rebuilt page replaces its controls, so the map must not keep the old ones.
        _switches[d.Key] = toggle;

        row.Children.Add(toggle);
        row.Children.Add(new TextBlock { Text = d.Description, Style = (Style)FindResource("DescriptionStyle") });

        if (!string.IsNullOrEmpty(d.Hotkey))
        {
            row.Children.Add(new TextBlock { Text = d.Hotkey, Style = (Style)FindResource("HotkeyStyle") });
        }

        if (d.HotkeyUnavailable)
        {
            row.Children.Add(new TextBlock
            {
                Text = "Another program already owns this shortcut, so it will not fire.",
                Style = (Style)FindResource("WarningStyle")
            });
        }

        return row;
    }

    private void OnSwitchChanged(object sender, RoutedEventArgs e)
    {
        if (_suppressEvents) return;
        if (sender is not CheckBox cb || cb.Tag is not string key) return;

        FeatureRegistry.Set(key, cb.IsChecked == true);
        UpdateStatus();
    }

    /// <summary>A feature changed somewhere else - a hotkey, or Game Mode. Follow it.</summary>
    private void OnFeatureChanged(FeatureDescriptor d)
    {
        Dispatcher.Invoke(() =>
        {
            if (_switches.TryGetValue(d.Key, out CheckBox? cb))
            {
                _suppressEvents = true;
                try
                {
                    cb.IsChecked = FeatureRegistry.IsEnabled(d.Key);
                }
                finally
                {
                    _suppressEvents = false;
                }
            }
            UpdateStatus();
        });
    }

    /// <summary>Re-read every switch on the current page. Called by App when Game Mode flips.</summary>
    public void RefreshAll()
    {
        Dispatcher.Invoke(() =>
        {
            _suppressEvents = true;
            try
            {
                foreach (KeyValuePair<string, CheckBox> kv in _switches)
                {
                    kv.Value.IsChecked = FeatureRegistry.IsEnabled(kv.Key);
                }
            }
            finally
            {
                _suppressEvents = false;
            }
            UpdateStatus();
        });
    }

    private void UpdateStatus()
    {
        int total = FeatureRegistry.Items.Count;
        int on = FeatureRegistry.Items.Count(d => FeatureRegistry.IsEnabled(d.Key));
        EnabledCountText.Text = $"{on} of {total} features enabled.";
    }

    /// <summary>Called by App while Game Mode is on, so the window explains why switches moved.</summary>
    public void SetGameModeNotice(bool active)
    {
        GameModeText.Visibility = active ? Visibility.Visible : Visibility.Collapsed;
        GameModeText.Text = active
            ? "Game Mode is on. Features are suspended in memory only - your saved settings are untouched."
            : string.Empty;
    }

    // -----------------------------------------------------------------------------------------
    // Tuning page
    // -----------------------------------------------------------------------------------------

    private UIElement BuildTuningPage()
    {
        StackPanel panel = new();

        panel.Children.Add(new TextBlock { Text = "Tuning", Style = (Style)FindResource("HeaderStyle") });
        panel.Children.Add(new TextBlock
        {
            Text = "Numbers behind the effects. Each is checked when you leave the field, not while you type.",
            Style = (Style)FindResource("DescriptionStyle")
        });

        panel.Children.Add(new TextBlock
        {
            Text = "PARALLAX DRAGGING",
            Style = (Style)FindResource("SubHeaderStyle")
        });

        panel.Children.Add(NumberRow(
            "Start fading at", "parallax.fromSpeed", 250, 0, 5000, "px/s",
            "Below this drag speed nothing fades at all. A deliberate, slow drag stays solid."));

        panel.Children.Add(NumberRow(
            "Fully faded at", "parallax.fullSpeed", 2200, 100, 20000, "px/s",
            "The speed at which the window reaches the minimum opacity below."));

        panel.Children.Add(NumberRow(
            "Minimum opacity", "parallax.minOpacity", 55, 10, 100, "%",
            "How transparent a fast-moving window gets. The ramp is named by both ends so that " +
            "\"invisible at a normal drag speed\" is a number you can see, not a hidden gain."));

        panel.Children.Add(new TextBlock
        {
            Text = "TASKBAR CLOCK",
            Style = (Style)FindResource("SubHeaderStyle")
        });

        panel.Children.Add(TextRow(
            "City", WeatherService.LocationKey, "",
            "The city the clock's weather is for, e.g. Baku. Leave this empty and the app makes no "
            + "network request at all - weather is the only feature that connects to the internet. "
            + "Switch \"Clock weather\" on under Screen & Shell as well."));

        panel.Children.Add(TextRow(
            "Time format", "clock.timeFormat", "HH:mm:ss",
            "Standard .NET format string. HH is 24-hour, hh is 12-hour."));

        panel.Children.Add(TextRow(
            "Date format", "clock.dateFormat", "dd.MM.yyyy",
            "Standard .NET format string. Use dd:MM:yyyy if you want colons as separators."));

        panel.Children.Add(NumberRow(
            "Gap from tray", "clock.gap", 12, 0, 400, "px",
            "Distance between the block and the tray element it sits left of."));

        return panel;
    }

    /// <summary>
    /// A free-text setting. Written on LostFocus for the same reason the numeric fields are: a city
    /// name is typed a letter at a time, and saving (and geocoding) every keystroke would fire a
    /// network request per character.
    /// </summary>
    private UIElement TextRow(string label, string key, string fallback, string help)
    {
        StackPanel row = new() { Margin = new Thickness(0, 10, 0, 16) };
        StackPanel line = new() { Orientation = Orientation.Horizontal };

        line.Children.Add(new TextBlock
        {
            Text = label,
            FontSize = 14,
            Width = 190,
            VerticalAlignment = VerticalAlignment.Center
        });

        TextBox box = new()
        {
            Width = 220,
            FontSize = 14,
            Padding = new Thickness(6, 4, 6, 4),
            Text = SettingsStore.GetString(key, fallback)
        };

        box.LostFocus += (_, _) =>
        {
            string value = box.Text.Trim();
            string previous = SettingsStore.GetString(key, fallback);
            if (value == previous) return;

            SettingsStore.SetString(key, value);

            // A changed city invalidates the cached coordinates, or the clock would keep showing
            // the weather for wherever it looked up first.
            if (key == WeatherService.LocationKey) WeatherService.InvalidateLocation();
        };

        line.Children.Add(box);
        row.Children.Add(line);
        row.Children.Add(new TextBlock { Text = help, Style = (Style)FindResource("DescriptionStyle") });

        return row;
    }

    private UIElement NumberRow(string label, string key, int fallback, int lo, int hi, string unit, string help)
    {
        StackPanel row = new() { Margin = new Thickness(0, 10, 0, 16) };

        StackPanel line = new() { Orientation = Orientation.Horizontal };

        line.Children.Add(new TextBlock
        {
            Text = label,
            FontSize = 14,
            Width = 190,
            VerticalAlignment = VerticalAlignment.Center
        });

        TextBox box = new()
        {
            Width = 90,
            FontSize = 14,
            Padding = new Thickness(6, 4, 6, 4),
            Text = SettingsStore.GetInt(key, fallback, lo, hi).ToString(CultureInfo.InvariantCulture),
            Tag = key,
            HorizontalContentAlignment = HorizontalAlignment.Right
        };

        // Validate on LostFocus, never on every keystroke: correcting 3 to 100 while somebody is
        // halfway through typing 300 fights the user for control of the field.
        box.LostFocus += (_, _) =>
        {
            int value = int.TryParse(box.Text.Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out int parsed)
                ? Math.Clamp(parsed, lo, hi)
                : fallback;

            box.Text = value.ToString(CultureInfo.InvariantCulture);
            SettingsStore.SetInt(key, value);
        };

        line.Children.Add(box);
        line.Children.Add(new TextBlock
        {
            Text = " " + unit,
            FontSize = 13,
            Foreground = System.Windows.Media.Brushes.Gray,
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(6, 0, 0, 0)
        });

        row.Children.Add(line);
        row.Children.Add(new TextBlock
        {
            Text = $"{help}  (allowed: {lo}-{hi})",
            Style = (Style)FindResource("DescriptionStyle")
        });

        return row;
    }
}
