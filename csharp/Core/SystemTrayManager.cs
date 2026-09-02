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
            Icon = AppIcon.Tray,
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

    /// <summary>
    /// A transient tray notification. This is the app's only channel for telling the user something
    /// went wrong - there is no log file - so it is used for the two failures a user cannot
    /// otherwise diagnose: a hotkey another program already owns, and DragFullWindows being off.
    /// </summary>
    public void ShowBalloon(string title, string message, int timeoutMs = 8000)
    {
        try
        {
            _notifyIcon.BalloonTipTitle = title;
            _notifyIcon.BalloonTipText = message;
            _notifyIcon.ShowBalloonTip(timeoutMs);
        }
        catch
        {
            // Notifications can be suppressed by policy or Focus Assist. Never escalate.
        }
    }

    public void Dispose()
    {
        _notifyIcon.Visible = false;
        _notifyIcon.Dispose();
    }
}
