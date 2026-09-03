using System;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

public class BlackHoleMinimizeFeature : IDisposable
{
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
    private void Stop() { }

    public void Dispose()
    {
        SetEnabled(false);
    }
}
