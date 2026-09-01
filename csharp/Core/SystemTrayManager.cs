using System;
using System.Windows.Forms;
using Application = System.Windows.Application;

namespace WindowTweaks.Core;

public class SystemTrayManager : IDisposable
{
    private readonly NotifyIcon _notifyIcon;

    public SystemTrayManager(Action onSettingsClicked, Action onRestartClicked, Action onExitClicked)
    {
        _notifyIcon = new NotifyIcon
        {
            Icon = System.Drawing.SystemIcons.Application,
            Visible = true,
            Text = "TweaksForEveryOne (.NET)"
        };

        var contextMenu = new ContextMenuStrip();
        
        var settingsItem = new ToolStripMenuItem("Settings");
        settingsItem.Click += (s, args) => onSettingsClicked();
        
        var restartItem = new ToolStripMenuItem("Restart");
        restartItem.Click += (s, args) => onRestartClicked();

        var exitItem = new ToolStripMenuItem("Exit");
        exitItem.Click += (s, args) => onExitClicked();

        contextMenu.Items.Add(settingsItem);
        contextMenu.Items.Add(new ToolStripSeparator());
        contextMenu.Items.Add(restartItem);
        contextMenu.Items.Add(exitItem);
        
        _notifyIcon.ContextMenuStrip = contextMenu;
    }

    public void Dispose()
    {
        _notifyIcon.Visible = false;
        _notifyIcon.Dispose();
    }
}
