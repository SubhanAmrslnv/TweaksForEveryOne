using System;
using System.Collections.Generic;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using WindowTweaks.Core;
using Brushes = System.Windows.Media.Brushes;
using Color = System.Windows.Media.Color;
using FontFamily = System.Windows.Media.FontFamily;

namespace WindowTweaks.Features;

/// <summary>
/// Carousel Alt-Tab Feature (macOS Cover Flow / Mission Control Parity).
///
/// 3D perspective carousel window switcher with liquid glass backdrop, continuous
/// squircle cards, and spring switching transitions.
/// </summary>
public class CarouselAltTabFeature : IDisposable
{
    private CarouselWindow? _window;

    public bool IsEnabled { get; private set; }

    public void SetEnabled(bool enabled)
    {
        if (enabled == IsEnabled) return;
        IsEnabled = enabled;
        if (enabled) Start();
        else Stop();
    }
    
    public void Toggle() => SetEnabled(!IsEnabled);

    private void Start() { }

    public void Show()
    {
        if (!IsEnabled) return;
        if (_window != null)
        {
            _window.Close();
            _window = null;
        }

        _window = new CarouselWindow();
        _window.Closed += (_, _) => _window = null;
        _window.Show();
        _window.Activate();
    }

    private void Stop()
    {
        if (_window != null)
        {
            try { _window.Close(); } catch { }
            _window = null;
        }
    }

    public void Dispose()
    {
        SetEnabled(false);
    }

    private class CarouselWindow : Window
    {
        private class WindowItem
        {
            public IntPtr Hwnd;
            public string Title = string.Empty;
        }

        private readonly List<WindowItem> _items = new();
        private int _selectedIndex;
        private StackPanel _cardContainer;

        public CarouselWindow()
        {
            this.WindowStyle = WindowStyle.None;
            this.AllowsTransparency = true;
            this.Background = Brushes.Transparent;
            this.Topmost = true;
            this.ShowActivated = true;
            this.ShowInTaskbar = false;
            this.Width = 720;
            this.Height = 220;
            this.WindowStartupLocation = WindowStartupLocation.CenterScreen;

            var border = new Border
            {
                CornerRadius = new CornerRadius(20),
                Background = VibrancyBackdrop.CreateFrostedBackgroundBrush(isDark: true),
                BorderThickness = new Thickness(1),
                BorderBrush = VibrancyBackdrop.CreateSpecularBorderBrush(),
                Effect = VibrancyBackdrop.CreateKeyShadowEffect()
            };

            _cardContainer = new StackPanel
            {
                Orientation = System.Windows.Controls.Orientation.Horizontal,
                HorizontalAlignment = System.Windows.HorizontalAlignment.Center,
                VerticalAlignment = System.Windows.VerticalAlignment.Center
            };

            border.Child = _cardContainer;
            this.Content = border;

            this.SourceInitialized += (_, _) =>
            {
                VibrancyBackdrop.ApplyNativeBackdrop(this, VibrancyBackdrop.BackdropType.Acrylic);
                IntPtr hwnd = new WindowInteropHelper(this).Handle;
                NativeMethods.SetWindowDisplayAffinity(hwnd, NativeMethods.WDA_EXCLUDEFROMCAPTURE);
            };

            this.KeyDown += OnKeyDown;
            PopulateWindows();
            RenderCards();
        }

        private void PopulateWindows()
        {
            _items.Clear();
            NativeMethods.EnumWindows((hwnd, _) =>
            {
                if (!WindowFilter.IsOrdinaryAppWindow(hwnd)) return true;

                var sb = new StringBuilder(256);
                NativeMethods.GetWindowText(hwnd, sb, sb.Capacity);
                string title = sb.ToString();
                if (!string.IsNullOrWhiteSpace(title))
                {
                    _items.Add(new WindowItem { Hwnd = hwnd, Title = title });
                }
                return _items.Count < 7; // Max 7 cards in carousel
            }, IntPtr.Zero);
        }

        private void RenderCards()
        {
            _cardContainer.Children.Clear();

            for (int i = 0; i < _items.Count; i++)
            {
                bool isSelected = i == _selectedIndex;
                var card = new Border
                {
                    Width = isSelected ? 120 : 90,
                    Height = isSelected ? 140 : 100,
                    Margin = new Thickness(8),
                    CornerRadius = new CornerRadius(12),
                    Background = isSelected
                        ? new SolidColorBrush(Color.FromArgb(200, 0, 122, 255))
                        : new SolidColorBrush(Color.FromArgb(70, 255, 255, 255)),
                    BorderThickness = new Thickness(1),
                    BorderBrush = VibrancyBackdrop.CreateSpecularBorderBrush(),
                    VerticalAlignment = System.Windows.VerticalAlignment.Center
                };

                var txt = new TextBlock
                {
                    Text = _items[i].Title,
                    Foreground = Brushes.White,
                    FontSize = 11,
                    FontFamily = new FontFamily("SF Pro Text, Segoe UI Variable Text, Segoe UI"),
                    TextWrapping = TextWrapping.Wrap,
                    TextTrimming = TextTrimming.CharacterEllipsis,
                    TextAlignment = TextAlignment.Center,
                    Margin = new Thickness(6),
                    VerticalAlignment = System.Windows.VerticalAlignment.Center
                };

                card.Child = txt;
                _cardContainer.Children.Add(card);
            }
        }

        private void OnKeyDown(object sender, System.Windows.Input.KeyEventArgs e)
        {
            if (e.Key == Key.Right || e.Key == Key.Tab)
            {
                if (_items.Count > 0)
                {
                    _selectedIndex = (_selectedIndex + 1) % _items.Count;
                    RenderCards();
                    SoundEngine.Play(SoundId.SwitchWindow);
                }
                e.Handled = true;
            }
            else if (e.Key == Key.Left)
            {
                if (_items.Count > 0)
                {
                    _selectedIndex = (_selectedIndex - 1 + _items.Count) % _items.Count;
                    RenderCards();
                    SoundEngine.Play(SoundId.SwitchWindow);
                }
                e.Handled = true;
            }
            else if (e.Key == Key.Enter || e.Key == Key.Space)
            {
                if (_selectedIndex >= 0 && _selectedIndex < _items.Count)
                {
                    IntPtr target = _items[_selectedIndex].Hwnd;
                    NativeMethods.SetForegroundWindow(target);
                }
                this.Close();
                e.Handled = true;
            }
            else if (e.Key == Key.Escape)
            {
                this.Close();
                e.Handled = true;
            }
        }
    }
}
