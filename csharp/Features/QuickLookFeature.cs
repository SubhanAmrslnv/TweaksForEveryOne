using System;
using System.IO;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using System.Text;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

public class QuickLookFeature : IDisposable
{
    private QuickLookWindow? _window;
    private DispatcherTimer? _monitorTimer;

    public void Toggle()
    {
        if (_window != null)
        {
            CloseQuickLook();
            return;
        }

        IntPtr hwnd = NativeMethods.GetForegroundWindow();
        StringBuilder sbCls = new StringBuilder(256);
        NativeMethods.GetClassName(hwnd, sbCls, sbCls.Capacity);

        if (sbCls.ToString() != "CabinetWClass")
            return;

        string path = GetSelectedExplorerFile(hwnd);
        if (string.IsNullOrEmpty(path) || !File.Exists(path))
            return;

        string ext = Path.GetExtension(path).ToLowerInvariant().TrimStart('.');
        if (!Regex.IsMatch(ext, @"^(png|jpg|jpeg|gif|bmp|txt|md|ini|ahk|csv|log|json|xml|ps1|bat|cmd)$"))
            return;

        _window = new QuickLookWindow(path, ext);
        _window.Closed += (s, e) =>
        {
            _window = null;
            _monitorTimer?.Stop();
        };

        _window.Show();

        _monitorTimer = new DispatcherTimer();
        _monitorTimer.Interval = TimeSpan.FromMilliseconds(100);
        _monitorTimer.Tick += CheckFocus;
        _monitorTimer.Start();
    }

    private string GetSelectedExplorerFile(IntPtr hwnd)
    {
        try
        {
            Type shellType = Type.GetTypeFromProgID("Shell.Application")!;
            dynamic shell = Activator.CreateInstance(shellType)!;
            foreach (dynamic window in shell.Windows())
            {
                if ((IntPtr)window.HWND == hwnd)
                {
                    dynamic sel = window.Document.SelectedItems();
                    if (sel.Count > 0)
                    {
                        return sel.Item(0).Path;
                    }
                }
            }
        }
        catch { }
        return string.Empty;
    }

    private void CheckFocus(object? sender, EventArgs e)
    {
        if (_window == null)
        {
            _monitorTimer?.Stop();
            return;
        }

        IntPtr hwnd = NativeMethods.GetForegroundWindow();
        StringBuilder sbCls = new StringBuilder(256);
        NativeMethods.GetClassName(hwnd, sbCls, sbCls.Capacity);
        string cls = sbCls.ToString();

        IntPtr myHwnd = new System.Windows.Interop.WindowInteropHelper(_window).Handle;

        if (hwnd != myHwnd && cls != "CabinetWClass")
        {
            CloseQuickLook();
        }
    }

    private void CloseQuickLook()
    {
        _window?.Close();
        _window = null;
        _monitorTimer?.Stop();
    }

    public void Dispose()
    {
        CloseQuickLook();
    }

    private class QuickLookWindow : Window
    {
        public QuickLookWindow(string path, string ext)
        {
            this.WindowStyle = WindowStyle.None;
            this.Topmost = true;
            this.Background = new SolidColorBrush(System.Windows.Media.Color.FromRgb(17, 17, 17));
            this.ShowInTaskbar = false;
            this.WindowStartupLocation = WindowStartupLocation.CenterScreen;
            this.SizeToContent = SizeToContent.WidthAndHeight;

            Border border = new Border
            {
                BorderBrush = System.Windows.Media.Brushes.Gray,
                BorderThickness = new Thickness(1),
                Padding = new Thickness(20)
            };

            if (Regex.IsMatch(ext, @"^(png|jpg|jpeg|gif|bmp)$"))
            {
                try
                {
                    System.Windows.Controls.Image img = new System.Windows.Controls.Image();
                    BitmapImage bmp = new BitmapImage();
                    bmp.BeginInit();
                    bmp.CacheOption = BitmapCacheOption.OnLoad;
                    bmp.UriSource = new Uri(path);
                    bmp.EndInit();
                    img.Source = bmp;
                    img.Stretch = Stretch.Uniform;
                    img.MaxWidth = SystemParameters.PrimaryScreenWidth * 0.8;
                    img.MaxHeight = SystemParameters.PrimaryScreenHeight * 0.8;
                    border.Child = img;
                }
                catch
                {
                    this.Close();
                }
            }
            else
            {
                try
                {
                    string content = "";
                    using (StreamReader sr = new StreamReader(path))
                    {
                        char[] buffer = new char[4096];
                        int bytesRead = sr.ReadBlock(buffer, 0, 4096);
                        content = new string(buffer, 0, bytesRead);
                    }

                    System.Windows.Controls.TextBox textBox = new System.Windows.Controls.TextBox
                    {
                        Text = content,
                        Width = 600,
                        Height = 400,
                        IsReadOnly = true,
                        Background = System.Windows.Media.Brushes.Transparent,
                        Foreground = System.Windows.Media.Brushes.White,
                        BorderThickness = new Thickness(0),
                        TextWrapping = TextWrapping.Wrap,
                        VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
                        FontFamily = new System.Windows.Media.FontFamily("Consolas")
                    };
                    border.Child = textBox;
                }
                catch
                {
                    this.Close();
                }
            }

            this.Content = border;
        }
    }
}
