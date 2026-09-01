using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

public class PositionMemoryFeature : IDisposable
{
    private bool _isEnabled = false;
    private IntPtr _hook = IntPtr.Zero;
    private NativeMethods.WinEventDelegate _procDelegate;
    private Dictionary<string, WindowRect> _positions = new();
    private string _settingsPath;

    public bool IsEnabled => _isEnabled;

    public struct WindowRect
    {
        public int X { get; set; }
        public int Y { get; set; }
        public int W { get; set; }
        public int H { get; set; }
    }

    public PositionMemoryFeature()
    {
        _procDelegate = new NativeMethods.WinEventDelegate(WinEventProc);
        
        string appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        string folder = Path.Combine(appData, "WindowTweaks");
        Directory.CreateDirectory(folder);
        _settingsPath = Path.Combine(folder, "window-positions.json");
        LoadPositions();
    }

    private void LoadPositions()
    {
        if (File.Exists(_settingsPath))
        {
            try
            {
                string json = File.ReadAllText(_settingsPath);
                var loaded = JsonSerializer.Deserialize<Dictionary<string, WindowRect>>(json);
                if (loaded != null) _positions = loaded;
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"Failed to load positions: {ex.Message}");
            }
        }
    }

    private void SavePositions()
    {
        try
        {
            string json = JsonSerializer.Serialize(_positions, new JsonSerializerOptions { WriteIndented = true });
            File.WriteAllText(_settingsPath, json);
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Failed to save positions: {ex.Message}");
        }
    }

    public void Toggle()
    {
        _isEnabled = !_isEnabled;
        if (_isEnabled)
        {
            // EVENT_SYSTEM_MOVESIZEEND (0x000B) for saving, EVENT_OBJECT_SHOW (0x8002) for restoring
            _hook = NativeMethods.SetWinEventHook(
                NativeMethods.EVENT_SYSTEM_MOVESIZEEND,
                NativeMethods.EVENT_OBJECT_SHOW,
                IntPtr.Zero,
                _procDelegate,
                0, 0,
                NativeMethods.WINEVENT_OUTOFCONTEXT);
            Debug.WriteLine("Position Memory: Enabled");
        }
        else
        {
            if (_hook != IntPtr.Zero)
            {
                NativeMethods.UnhookWinEvent(_hook);
                _hook = IntPtr.Zero;
            }
            Debug.WriteLine("Position Memory: Disabled");
        }
    }

    private void WinEventProc(IntPtr hWinEventHook, uint eventType, IntPtr hwnd, int idObject, int idChild, uint dwEventThread, uint dwmsEventTime)
    {
        // 0 means it's a window (OBJID_WINDOW)
        if (idObject != 0 || idChild != 0) return;

        if (eventType == NativeMethods.EVENT_SYSTEM_MOVESIZEEND)
        {
            RememberPosition(hwnd);
        }
        else if (eventType == NativeMethods.EVENT_OBJECT_SHOW)
        {
            RestorePosition(hwnd);
        }
    }

    private string GetWindowKey(IntPtr hwnd)
    {
        // 1. Invisible windows
        if (!NativeMethods.IsWindowVisible(hwnd)) return null;

        // 2. Cannot be owned
        if (NativeMethods.GetWindow(hwnd, NativeMethods.GW_OWNER) != IntPtr.Zero) return null;

        // 3. Process check
        NativeMethods.GetWindowThreadProcessId(hwnd, out uint pid);
        if (pid == 0 || pid == Process.GetCurrentProcess().Id) return null;

        // 4. Style checks
        uint style = NativeMethods.GetWindowLong(hwnd, NativeMethods.GWL_STYLE);
        uint exStyle = NativeMethods.GetWindowLong(hwnd, NativeMethods.GWL_EXSTYLE);

        const uint WS_THICKFRAME = 0x00040000;
        const uint WS_MAXIMIZEBOX = 0x00010000;
        const uint WS_EX_TOOLWINDOW = 0x00000080;
        const uint WS_EX_TOPMOST = 0x00000008;

        if ((exStyle & WS_EX_TOOLWINDOW) == WS_EX_TOOLWINDOW) return null;
        if ((style & WS_THICKFRAME) == 0) return null;

        // Class Name
        StringBuilder sbClass = new StringBuilder(256);
        NativeMethods.GetClassName(hwnd, sbClass, sbClass.Capacity);
        string cls = sbClass.ToString();

        if (cls == "Shell_TrayWnd" || cls == "Progman" || cls == "WorkerW") return null;

        // Exe Name and PiP check
        string exe = "";
        try
        {
            using Process proc = Process.GetProcessById((int)pid);
            exe = proc.ProcessName;
        }
        catch { return null; }

        // PiP checks (WS_EX_TOPMOST but no WS_MAXIMIZEBOX, specific browsers)
        if ((exStyle & WS_EX_TOPMOST) == WS_EX_TOPMOST && (style & WS_MAXIMIZEBOX) == 0)
        {
            string exeLower = exe.ToLowerInvariant();
            if (exeLower == "chrome" || exeLower == "msedge" || exeLower == "firefox" || exeLower == "brave" || exeLower == "opera" || exeLower == "vivaldi")
            {
                return null;
            }
        }

        // Title PiP check
        StringBuilder sbTitle = new StringBuilder(256);
        NativeMethods.GetWindowText(hwnd, sbTitle, sbTitle.Capacity);
        string title = sbTitle.ToString();

        if (System.Text.RegularExpressions.Regex.IsMatch(title, @"^(Picture.?in.?Picture|PiP|Картинка в картинке|Resim içinde resim|Şəkil içində şəkil)$", System.Text.RegularExpressions.RegexOptions.IgnoreCase))
        {
            return null;
        }

        return $"{exe}:{cls}";
    }

    private void RememberPosition(IntPtr hwnd)
    {
        string key = GetWindowKey(hwnd);
        if (key == null) return;

        if (NativeMethods.GetWindowRect(hwnd, out NativeMethods.RECT winRect))
        {
            int w = winRect.Right - winRect.Left;
            int h = winRect.Bottom - winRect.Top;
            
            if (w <= 0 || h <= 0) return;

            _positions[key] = new WindowRect { X = winRect.Left, Y = winRect.Top, W = w, H = h };
            SavePositions(); // Ideally this is debounced, but this works for now
        }
    }

    private void RestorePosition(IntPtr hwnd)
    {
        string key = GetWindowKey(hwnd);
        if (key == null) return;

        if (_positions.TryGetValue(key, out WindowRect rect))
        {
            // Restore it!
            NativeMethods.SetWindowPos(hwnd, IntPtr.Zero, rect.X, rect.Y, rect.W, rect.H, NativeMethods.SWP_NOACTIVATE);
        }
    }

    public void Dispose()
    {
        if (_hook != IntPtr.Zero)
        {
            NativeMethods.UnhookWinEvent(_hook);
            _hook = IntPtr.Zero;
        }
    }
}
