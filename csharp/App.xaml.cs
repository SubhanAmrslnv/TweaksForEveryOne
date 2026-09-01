using System.Windows;
using WindowTweaks.Core;
using WindowTweaks.Features;

namespace WindowTweaks;

public partial class App : System.Windows.Application
{
    private SystemTrayManager? _systemTrayManager;
    private HotkeyManager? _hotkeyManager;
    private MainWindow? _settingsWindow;
    
    private readonly FocusModeFeature _focusModeFeature = new();
    private readonly AlwaysOnTopFeature _alwaysOnTopFeature = new();
    private readonly MagneticSnappingFeature _magneticSnappingFeature = new();
    private readonly PositionMemoryFeature _positionMemoryFeature = new();
    private readonly BreathingFeature _breathingFeature = new();
    private readonly RollUpFeature _rollUpFeature = new();
    private readonly TrayMinimizeFeature _trayMinimizeFeature = new();
    private readonly BossKeyFeature _bossKeyFeature = new();
    private readonly ChangeTransparencyFeature _changeTransparencyFeature = new();
    private readonly CenterWindowFeature _centerWindowFeature = new();
    private readonly CycleWindowSizeFeature _cycleWindowSizeFeature = new();
    private readonly NextMonitorFeature _nextMonitorFeature = new();
    private readonly TileWindowFeature _tileWindowFeature = new();
    private readonly MaximizeRestoreFeature _maximizeRestoreFeature = new();
    private readonly UndoLayoutFeature _undoLayoutFeature = new();
    private readonly ResetTransparencyFeature _resetTransparencyFeature = new();
    private readonly HotCornersFeature _hotCornersFeature = new();
    private readonly InfiniteWrapFeature _infiniteWrapFeature = new();
    private readonly MultiMonitorDimmerFeature _multiMonitorDimmerFeature = new();
    private readonly SmartTaskbarFeature _smartTaskbarFeature = new();
    private readonly MagneticGroupsFeature _magneticGroupsFeature = new();
    private readonly GrabPanFeature _grabPanFeature = new();
    private RestoreAllFeature _restoreAllFeature;
    private StealthPanicTrigger _stealthPanicTrigger;

    private const uint VK_O = 0x4F;
    private const uint VK_F = 0x46;
    private const uint VK_W = 0x57;
    private const uint VK_S = 0x53;
    private const uint VK_M = 0x4D;
    private const uint VK_E = 0x45;
    private const uint VK_R = 0x52;
    private const uint VK_H = 0x48;
    private const uint VK_ESCAPE = 0x1B;
    private const uint VK_K = 0x4B;
    private const uint VK_U = 0x55;
    private const uint VK_N = 0x4E;
    private const uint VK_Z = 0x5A;
    private const uint VK_X = 0x58;
    private const uint VK_Y = 0x59;
    private const uint VK_C = 0x43;
    private const uint VK_I = 0x49;
    private const uint VK_D = 0x44;
    private const uint VK_T = 0x54;
    private const uint VK_J = 0x4A;
    private const uint VK_SPACE = 0x20;

    private const uint VK_NUMPAD0 = 0x60;
    private const uint VK_NUMPAD1 = 0x61;
    private const uint VK_NUMPAD2 = 0x62;
    private const uint VK_NUMPAD3 = 0x63;
    private const uint VK_NUMPAD4 = 0x64;
    private const uint VK_NUMPAD5 = 0x65;
    private const uint VK_NUMPAD6 = 0x66;
    private const uint VK_NUMPAD7 = 0x67;
    private const uint VK_NUMPAD8 = 0x68;
    private const uint VK_NUMPAD9 = 0x69;
    
    private const uint VK_UP = 0x26;
    private const uint VK_DOWN = 0x28;

    private const uint VK_F5 = 0x74;
    private const uint VK_F6 = 0x75;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        _restoreAllFeature = new RestoreAllFeature(_rollUpFeature, _trayMinimizeFeature);
        _stealthPanicTrigger = new StealthPanicTrigger(() => 
        {
            Dispatcher.Invoke(() => _bossKeyFeature.Toggle());
        });

        // 1. Initialize UI Managers
        _systemTrayManager = new SystemTrayManager(ShowSettingsWindow, ReloadApp, Shutdown);
        _hotkeyManager = new HotkeyManager();

        // 2. Register Hotkeys (Shift + Alt + Key)
        uint modifiers = NativeMethods.MOD_ALT | NativeMethods.MOD_SHIFT;
        
        _hotkeyManager.Register(modifiers, VK_O, _alwaysOnTopFeature.Toggle);
        _hotkeyManager.Register(modifiers, VK_F, _focusModeFeature.Toggle);
        _hotkeyManager.Register(modifiers, VK_W, ShowSettingsWindow);
        _hotkeyManager.Register(modifiers, VK_S, _magneticSnappingFeature.Toggle);
        _hotkeyManager.Register(modifiers, VK_M, _positionMemoryFeature.Toggle);
        _hotkeyManager.Register(modifiers, VK_E, _breathingFeature.Toggle);
        _hotkeyManager.Register(modifiers, VK_R, _rollUpFeature.Toggle);
        _hotkeyManager.Register(modifiers, VK_H, _trayMinimizeFeature.Toggle);
        _hotkeyManager.Register(modifiers, VK_ESCAPE, _bossKeyFeature.Toggle);
        _hotkeyManager.Register(modifiers, VK_K, _centerWindowFeature.Toggle);
        _hotkeyManager.Register(modifiers, VK_U, _cycleWindowSizeFeature.Toggle);
        _hotkeyManager.Register(modifiers, VK_N, _nextMonitorFeature.Toggle);
        _hotkeyManager.Register(modifiers, VK_Z, _undoLayoutFeature.Toggle);
        _hotkeyManager.Register(modifiers, VK_X, _resetTransparencyFeature.Toggle);
        _hotkeyManager.Register(modifiers, VK_Y, _restoreAllFeature.Toggle);
        _hotkeyManager.Register(modifiers, VK_C, _hotCornersFeature.Toggle);
        _hotkeyManager.Register(modifiers, VK_I, _infiniteWrapFeature.Toggle);
        _hotkeyManager.Register(modifiers, VK_D, _multiMonitorDimmerFeature.Toggle);
        _hotkeyManager.Register(modifiers, VK_T, _smartTaskbarFeature.Toggle);
        _hotkeyManager.Register(modifiers, VK_J, _magneticGroupsFeature.Toggle);
        _hotkeyManager.Register(modifiers, VK_SPACE, _grabPanFeature.Toggle);

        _hotkeyManager.Register(modifiers, VK_NUMPAD0, _maximizeRestoreFeature.Toggle);
        _hotkeyManager.Register(modifiers, VK_NUMPAD1, () => _tileWindowFeature.TileWindow(1));
        _hotkeyManager.Register(modifiers, VK_NUMPAD2, () => _tileWindowFeature.TileWindow(2));
        _hotkeyManager.Register(modifiers, VK_NUMPAD3, () => _tileWindowFeature.TileWindow(3));
        _hotkeyManager.Register(modifiers, VK_NUMPAD4, () => _tileWindowFeature.TileWindow(4));
        _hotkeyManager.Register(modifiers, VK_NUMPAD5, () => _tileWindowFeature.TileWindow(5));
        _hotkeyManager.Register(modifiers, VK_NUMPAD6, () => _tileWindowFeature.TileWindow(6));
        _hotkeyManager.Register(modifiers, VK_NUMPAD7, () => _tileWindowFeature.TileWindow(7));
        _hotkeyManager.Register(modifiers, VK_NUMPAD8, () => _tileWindowFeature.TileWindow(8));
        _hotkeyManager.Register(modifiers, VK_NUMPAD9, () => _tileWindowFeature.TileWindow(9));

        _hotkeyManager.Register(modifiers, VK_UP, () => _tileWindowFeature.TileWindow(8));
        _hotkeyManager.Register(modifiers, VK_DOWN, () => _tileWindowFeature.TileWindow(2));

        _hotkeyManager.Register(modifiers, VK_F5, ReloadApp);
        _hotkeyManager.Register(modifiers, VK_F6, Shutdown);
    }

    private void ReloadApp()
    {
        var exePath = System.Environment.ProcessPath;
        if (exePath != null)
        {
            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
            {
                FileName = exePath,
                UseShellExecute = true
            });
        }
        Shutdown();
    }

    private void ShowSettingsWindow()
    {
        if (_settingsWindow == null)
        {
            _settingsWindow = new MainWindow();
            _settingsWindow.Closed += (s, args) => _settingsWindow = null;
            _settingsWindow.Show();
        }
        else
        {
            if (_settingsWindow.WindowState == WindowState.Minimized)
                _settingsWindow.WindowState = WindowState.Normal;
            _settingsWindow.Activate();
        }
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _hotkeyManager?.Dispose();
        _systemTrayManager?.Dispose();
        _stealthPanicTrigger?.Dispose();
        _grabPanFeature?.Dispose();
        _magneticGroupsFeature?.Dispose();
        _smartTaskbarFeature?.Dispose();
        _multiMonitorDimmerFeature?.Dispose();
        _infiniteWrapFeature?.Dispose();
        _hotCornersFeature?.Dispose();
        
        base.OnExit(e);
    }
}
