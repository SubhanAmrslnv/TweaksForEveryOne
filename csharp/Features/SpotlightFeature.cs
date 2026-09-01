using System;
using System.Data;
using System.Diagnostics;
using System.IO;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

public class SpotlightFeature : IDisposable
{
    private SpotlightWindow? _window;

    public void Toggle()
    {
        if (_window != null)
        {
            _window.Close();
            _window = null;
            return;
        }

        _window = new SpotlightWindow();
        _window.Closed += (s, e) => _window = null;
        _window.Show();
        _window.Activate();
    }

    public bool IsActive => _window != null && _window.IsActive;

    public void Dispose()
    {
        if (_window != null)
        {
            _window.Close();
            _window = null;
        }
    }

    private class SpotlightWindow : Window
    {
        private System.Windows.Controls.TextBox _inputBox;
        private TextBlock _resultText;

        public SpotlightWindow()
        {
            this.WindowStyle = WindowStyle.None;
            this.AllowsTransparency = true;
            this.Background = new SolidColorBrush(System.Windows.Media.Color.FromArgb(240, 32, 32, 32));
            this.Topmost = true;
            this.ShowInTaskbar = false;
            this.Width = 640;
            this.Height = 140;
            this.WindowStartupLocation = WindowStartupLocation.CenterScreen;

            // Rounded corners using a Border
            Border border = new Border
            {
                CornerRadius = new CornerRadius(20),
                Background = System.Windows.Media.Brushes.Transparent
            };

            Grid grid = new Grid();
            grid.Margin = new Thickness(20);
            grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(55) });
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

            _inputBox = new System.Windows.Controls.TextBox
            {
                Background = System.Windows.Media.Brushes.Transparent,
                Foreground = System.Windows.Media.Brushes.White,
                BorderThickness = new Thickness(0),
                FontSize = 24,
                FontFamily = new System.Windows.Media.FontFamily("Segoe UI"),
                CaretBrush = System.Windows.Media.Brushes.White,
                VerticalAlignment = VerticalAlignment.Top
            };
            _inputBox.TextChanged += OnTextChanged;
            _inputBox.PreviewKeyDown += OnPreviewKeyDown;

            _resultText = new TextBlock
            {
                Foreground = new SolidColorBrush(System.Windows.Media.Color.FromRgb(170, 170, 170)),
                FontSize = 14,
                FontFamily = new System.Windows.Media.FontFamily("Segoe UI"),
                Text = "Type to search, calculate, or run...",
                Margin = new Thickness(0, 10, 0, 0)
            };

            Grid.SetRow(_inputBox, 0);
            Grid.SetRow(_resultText, 1);

            grid.Children.Add(_inputBox);
            grid.Children.Add(_resultText);

            border.Child = grid;
            this.Content = border;

            this.Loaded += (s, e) =>
            {
                // Align top third of the screen instead of exact center
                var workArea = SystemParameters.WorkArea;
                this.Top = workArea.Top + (workArea.Height - this.Height) / 3;
                _inputBox.Focus();
            };
        }

        private void OnTextChanged(object sender, TextChangedEventArgs e)
        {
            string text = _inputBox.Text.Trim();
            if (string.IsNullOrEmpty(text))
            {
                _resultText.Text = "Type to search, calculate, or run...";
                return;
            }

            if (Regex.IsMatch(text, @"^[\d\+\-\*\/\.\(\)\s]+$") && Regex.IsMatch(text, @"\d"))
            {
                try
                {
                    var dt = new DataTable();
                    var ans = dt.Compute(text, "");
                    if (ans != null && ans != DBNull.Value)
                    {
                        _resultText.Text = "= " + ans.ToString();
                        return;
                    }
                }
                catch { }
            }

            if (File.Exists(text) || Directory.Exists(text))
            {
                _resultText.Text = "Open path: " + text;
                return;
            }

            _resultText.Text = "Run: " + text;
        }

        private void OnPreviewKeyDown(object sender, System.Windows.Input.KeyEventArgs e)
        {
            if (e.Key == Key.Escape)
            {
                this.Close();
                e.Handled = true;
            }
            else if (e.Key == Key.Enter)
            {
                Execute();
                e.Handled = true;
            }
        }

        private void Execute()
        {
            string text = _inputBox.Text.Trim();
            if (string.IsNullOrEmpty(text)) return;

            string resText = _resultText.Text;

            if (resText.StartsWith("= "))
            {
                System.Windows.Clipboard.SetText(resText.Substring(2));
                this.Close();
                return;
            }

            this.Close();

            try
            {
                Process.Start(new ProcessStartInfo
                {
                    FileName = text,
                    UseShellExecute = true
                });
            }
            catch
            {
                string q = Uri.EscapeDataString(text);
                try
                {
                    Process.Start(new ProcessStartInfo
                    {
                        FileName = "https://www.google.com/search?q=" + q,
                        UseShellExecute = true
                    });
                }
                catch { }
            }
        }
    }
}
