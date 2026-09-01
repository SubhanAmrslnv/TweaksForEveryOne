using System;
using System.Threading.Tasks;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

public class RestoreAllFeature
{
    private readonly RollUpFeature _rollUpFeature;
    private readonly TrayMinimizeFeature _trayMinimizeFeature;

    public RestoreAllFeature(RollUpFeature rollUpFeature, TrayMinimizeFeature trayMinimizeFeature)
    {
        _rollUpFeature = rollUpFeature;
        _trayMinimizeFeature = trayMinimizeFeature;
    }

    public async void Toggle()
    {
        int count = 0;
        
        // Restore tray-minimized windows
        count += _trayMinimizeFeature.RestoreAll();
        
        // Restore rolled-up windows
        count += await _rollUpFeature.RestoreAll();
        
        // If we restored anything, play sound / log it.
        // In the original AHK it plays a sound and shows a notification.
        // We'll just be happy they are restored!
    }
}
