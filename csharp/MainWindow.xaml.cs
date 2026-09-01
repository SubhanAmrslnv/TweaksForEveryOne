using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using WindowTweaks.Core;
// WPF and WinForms are both referenced, so these names need pinning under ImplicitUsings.
using Brush = System.Windows.Media.Brush;
using CheckBox = System.Windows.Controls.CheckBox;
using ComboBox = System.Windows.Controls.ComboBox;
using HorizontalAlignment = System.Windows.HorizontalAlignment;
using Panel = System.Windows.Controls.Panel;
using TextBox = System.Windows.Controls.TextBox;

namespace WindowTweaks;

/// <summary>
/// The settings window. Every row is GENERATED from a registry - FeatureRegistry for the switches,
/// TuningRegistry for the numbers, strings and choices - so adding a setting is a one-line change
/// there and no change at all here.
///
/// It used to be a mock: hardcoded checkboxes with literal check states, wired to nothing. Now a
/// switch applies immediately through FeatureRegistry, which persists it, so there is no Save button
/// and nothing to save. That also means the window has to LISTEN for changes made elsewhere, because
/// a hotkey or Game Mode can flip a feature while it is open.
/// </summary>
public partial class MainWindow : Window
{
    private readonly Dictionary<string, CheckBox> _switches = new();

    /// <summary>
    /// One commit action per editable text field, replayed when the page changes or the window
    /// closes.
    ///
    /// Text fields deliberately write on LostFocus rather than per keystroke, but WPF does not
    /// reliably raise LostFocus when a window is closed while a TextBox still has focus - so typing
    /// a city and closing the window discarded the edit, silently, with the field still showing it.
    /// Every commit is idempotent (the store ignores an unchanged value), so replaying them all
    /// costs nothing. The list is cleared as each page is torn down; keeping closures over TextBoxes
    /// that no longer exist would write their stale values back over a newer edit.
    /// </summary>
    private readonly List<Action> _pendingCommits = new();

    /// <summary>
    /// Set while a control's state is being written FROM the model, so its change handler does not
    /// mistake a refresh for a user action and bounce it back.
    /// </summary>
    private bool _suppressEvents;

    public MainWindow()
    {
        InitializeComponent();

        SubtitleText.Text = "Settings apply instantly";
        SettingsPathText.Text = SettingsStore.FilePath;

        BuildSidebar();
        FeatureRegistry.Changed += OnFeatureChanged;
        Closed += (_, _) => FeatureRegistry.Changed -= OnFeatureChanged;
        Closing += (_, _) => CommitPendingEdits();

        UpdateStatus();
    }

    private void BuildSidebar()
    {
        // Pages come from the feature registry, plus any page that carries only tuning rows.
        List<string> pages = FeatureRegistry.Pages().ToList();
        foreach (TuningDescriptor d in TuningRegistry.Items)
        {
            if (!pages.Contains(d.Page, StringComparer.OrdinalIgnoreCase)) pages.Add(d.Page);
        }

        foreach (string page in pages)
        {
            SidebarList.Items.Add(new ListBoxItem { Content = page, Tag = page });
        }

        if (SidebarList.Items.Count > 0) SidebarList.SelectedIndex = 0;
    }

    private void SidebarList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (SidebarList.SelectedItem is not ListBoxItem item) return;

        string page = item.Tag?.ToString() ?? string.Empty;

        // Commit, then DROP, the outgoing page's field commits before building the new one.
        CommitPendingEdits();
        _pendingCommits.Clear();
        _switches.Clear();

        MainContent.Content = BuildPage(page);
        AnimatePageIn();
    }

    /// <summary>A short fade and lift, so a page change reads as a transition rather than a flicker.</summary>
    private void AnimatePageIn()
    {
        ContentScroll.ScrollToTop();

        DoubleAnimation fade = new(0.0, 1.0, new Duration(TimeSpan.FromMilliseconds(220)))
        {
            EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut }
        };
        DoubleAnimation lift = new(10.0, 0.0, new Duration(TimeSpan.FromMilliseconds(260)))
        {
            EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut }
        };

        MainContent.BeginAnimation(OpacityProperty, fade);
        ContentShift.BeginAnimation(TranslateTransform.YProperty, lift);
    }

    // -----------------------------------------------------------------------------------------
    // Page construction
    // -----------------------------------------------------------------------------------------

    private UIElement BuildPage(string page)
    {
        StackPanel panel = new() { MaxWidth = 760, HorizontalAlignment = HorizontalAlignment.Left };

        panel.Children.Add(new TextBlock { Text = page, Style = (Style)FindResource("PageTitle") });
        panel.Children.Add(new TextBlock
        {
            Text = "Changes apply immediately and are remembered.",
            Style = (Style)FindResource("PageSubtitle")
        });

        // Features first, then the numbers that tune them. Each group gets its own rounded card.
        string? currentGroup = null;
        StackPanel? card = null;

        foreach (FeatureDescriptor d in FeatureRegistry.ForPage(page))
        {
            string group = d.Group ?? "Features";
            if (group != currentGroup)
            {
                currentGroup = group;
                panel.Children.Add(GroupLabel(group));
                card = NewCard(panel);
            }
            card!.Children.Add(FeatureRow(d));
        }

        currentGroup = null;
        card = null;

        foreach (TuningDescriptor t in TuningRegistry.ForPage(page))
        {
            if (t.Group != currentGroup)
            {
                currentGroup = t.Group;
                panel.Children.Add(GroupLabel(t.Group));
                card = NewCard(panel);
            }
            card!.Children.Add(TuningRow(t));
        }

        return panel;
    }

    private TextBlock GroupLabel(string text)
    {
        return new TextBlock { Text = text.ToUpperInvariant(), Style = (Style)FindResource("GroupLabel") };
    }

    /// <summary>Adds a rounded card to the page and returns the stack its rows go into.</summary>
    private StackPanel NewCard(Panel parent)
    {
        StackPanel inner = new();
        parent.Children.Add(new Border { Style = (Style)FindResource("CardStyle"), Child = inner });
        return inner;
    }

    /// <summary>The label-and-description block on the left of every row.</summary>
    private StackPanel Caption(string title, string description)
    {
        StackPanel text = new() { VerticalAlignment = VerticalAlignment.Center };
        text.Children.Add(new TextBlock { Text = title, Style = (Style)FindResource("RowTitle") });
        if (description.Length > 0)
            text.Children.Add(new TextBlock { Text = description, Style = (Style)FindResource("RowDescription") });
        return text;
    }

    /// <summary>A two-column row: caption on the left, control on the right.</summary>
    private static Grid NewRow(double controlWidth)
    {
        Grid row = new() { Margin = new Thickness(0, 14, 0, 14) };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition
        {
            Width = controlWidth > 0 ? new GridLength(controlWidth) : GridLength.Auto
        });
        return row;
    }

    private static void Place(Grid row, UIElement left, UIElement right)
    {
        Grid.SetColumn(left, 0);
        Grid.SetColumn(right, 1);
        row.Children.Add(left);
        row.Children.Add(right);
    }

    // -----------------------------------------------------------------------------------------
    // Feature rows
    // -----------------------------------------------------------------------------------------

    private UIElement FeatureRow(FeatureDescriptor d)
    {
        Grid row = NewRow(0);
        StackPanel text = Caption(d.Title, d.Description);

        if (!string.IsNullOrEmpty(d.Hotkey))
        {
            text.Children.Add(new Border
            {
                CornerRadius = new CornerRadius(6),
                Background = (Brush)FindResource("AccentSoft"),
                Padding = new Thickness(7, 3, 7, 3),
                HorizontalAlignment = HorizontalAlignment.Left,
                Margin = new Thickness(0, 8, 0, 0),
                Child = new TextBlock { Text = d.Hotkey, Style = (Style)FindResource("HotkeyChipText") }
            });
        }

        if (d.HotkeyUnavailable)
        {
            text.Children.Add(new TextBlock
            {
                Text = "Another program already owns this shortcut, so it will not fire.",
                Style = (Style)FindResource("WarningText")
            });
        }

        CheckBox toggle = new()
        {
            Style = (Style)FindResource("ToggleSwitchStyle"),
            IsChecked = FeatureRegistry.IsEnabled(d.Key),
            Tag = d.Key,
            Margin = new Thickness(24, 2, 0, 0),
            VerticalAlignment = VerticalAlignment.Top
        };
        toggle.Checked += OnSwitchChanged;
        toggle.Unchecked += OnSwitchChanged;
        _switches[d.Key] = toggle;

        Place(row, text, toggle);
        return row;
    }

    private void OnSwitchChanged(object sender, RoutedEventArgs e)
    {
        if (_suppressEvents) return;
        if (sender is not CheckBox cb || cb.Tag is not string key) return;

        FeatureRegistry.Set(key, cb.IsChecked == true);
        UpdateStatus();
    }

    // -----------------------------------------------------------------------------------------
    // Tuning rows
    // -----------------------------------------------------------------------------------------

    private UIElement TuningRow(TuningDescriptor d)
    {
        return d.Kind switch
        {
            TuningKind.Text => TextRow(d),
            TuningKind.Choice => ChoiceRow(d),
            _ => SliderRow(d)
        };
    }

    /// <summary>
    /// A slider with a live readout, rather than a text box, because every one of these has a real
    /// known range: dragging it cannot produce an invalid value, so there is nothing to validate and
    /// nothing to reject back at the user.
    /// </summary>
    private UIElement SliderRow(TuningDescriptor d)
    {
        Grid row = NewRow(220);
        StackPanel text = Caption(d.Title, d.Description);

        int current = TuningRegistry.Int(d.Key);

        TextBlock readout = new()
        {
            Style = (Style)FindResource("ValueReadout"),
            Text = TuningRegistry.Display(d, current)
        };

        int span = Math.Max(1, d.Max - d.Min);
        Slider slider = new()
        {
            Style = (Style)FindResource("TuneSliderStyle"),
            Minimum = d.Min,
            Maximum = d.Max,
            Value = current,
            TickFrequency = Math.Max(1, span / 100),
            SmallChange = Math.Max(1, span / 100),
            LargeChange = Math.Max(1, span / 10),
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(0, 4, 0, 0)
        };

        // The readout follows the thumb continuously and the store is written on the same change.
        // That is safe because SettingsStore debounces: dragging produces one file write when the
        // hand stops, not one per pixel.
        slider.ValueChanged += (_, _) =>
        {
            int value = (int)Math.Round(slider.Value);
            readout.Text = TuningRegistry.Display(d, value);
            if (_suppressEvents) return;
            TuningRegistry.SetInt(d.Key, value);
        };

        StackPanel right = new()
        {
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(24, 0, 0, 0)
        };
        right.Children.Add(readout);
        right.Children.Add(slider);

        Place(row, text, right);
        return row;
    }

    private UIElement TextRow(TuningDescriptor d)
    {
        Grid row = NewRow(220);
        StackPanel text = Caption(d.Title, d.Description);

        TextBox box = new()
        {
            Style = (Style)FindResource("FieldStyle"),
            Text = TuningRegistry.Text(d.Key),
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(24, 0, 0, 0)
        };

        void Commit()
        {
            string value = box.Text.Trim();
            if (value == TuningRegistry.Text(d.Key)) return;

            TuningRegistry.SetText(d.Key, value);

            // A changed city invalidates the cached coordinates, or the clock would keep showing the
            // weather for wherever it looked up first.
            if (d.Key == TuningRegistry.ClockLocation) WeatherService.InvalidateLocation();
        }

        // Committed on LostFocus, not per keystroke: a city is typed a letter at a time, and each
        // letter would otherwise be a geocoding request.
        box.LostFocus += (_, _) => Commit();
        _pendingCommits.Add(Commit);

        Place(row, text, box);
        return row;
    }

    private UIElement ChoiceRow(TuningDescriptor d)
    {
        Grid row = NewRow(220);
        StackPanel text = Caption(d.Title, d.Description);

        ComboBox combo = new()
        {
            Style = (Style)FindResource("ChoiceStyle"),
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(24, 0, 0, 0)
        };

        string stored = TuningRegistry.Choice(d.Key);
        for (int i = 0; i < d.Choices.Length; i++)
        {
            string label = i < d.ChoiceLabels.Length ? d.ChoiceLabels[i] : d.Choices[i];
            combo.Items.Add(new ComboBoxItem { Content = label, Tag = d.Choices[i] });
            if (string.Equals(d.Choices[i], stored, StringComparison.OrdinalIgnoreCase))
                combo.SelectedIndex = i;
        }

        combo.SelectionChanged += (_, _) =>
        {
            if (_suppressEvents) return;
            if (combo.SelectedItem is not ComboBoxItem chosen || chosen.Tag is not string value) return;

            TuningRegistry.SetText(d.Key, value);

            // Units are part of the weather request, so a change has to re-fetch rather than wait
            // out the fifteen-minute interval still showing the old unit.
            if (d.Key == TuningRegistry.ClockUnits) WeatherService.InvalidateLocation();
        };

        Place(row, text, combo);
        return row;
    }

    // -----------------------------------------------------------------------------------------
    // Following changes made elsewhere
    // -----------------------------------------------------------------------------------------

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
        EnabledCountText.Text = $"{on} of {total} features on";
    }

    /// <summary>Called by App while Game Mode is on, so the window explains why switches moved.</summary>
    public void SetGameModeNotice(bool active)
    {
        GameModeText.Visibility = active ? Visibility.Visible : Visibility.Collapsed;
        GameModeText.Text = active
            ? "Game Mode is on. Features are suspended in memory only - your saved settings are untouched."
            : string.Empty;
    }

    /// <summary>
    /// Replay every field's commit. Called on page change and on close, because LostFocus is not
    /// guaranteed to fire first. One bad field must not stop the others from being saved.
    /// </summary>
    private void CommitPendingEdits()
    {
        foreach (Action commit in _pendingCommits)
        {
            try
            {
                commit();
            }
            catch
            {
                // A field that cannot commit is not worth blocking the page change or the close.
            }
        }
    }
}
