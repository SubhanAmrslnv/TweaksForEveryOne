using System;
using System.Threading.Tasks;
using System.Windows;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

public class PlainPasteFeature
{
    public void Toggle()
    {
        // Run asynchronously so we can sleep without blocking the hotkey thread
        Task.Run(async () =>
        {
            try
            {
                System.Windows.IDataObject? oldData = null;
                string? plainText = null;

                var app = System.Windows.Application.Current;
                if (app == null) return;

                app.Dispatcher.Invoke(() =>
                {
                    try
                    {
                        if (System.Windows.Clipboard.ContainsText())
                        {
                            oldData = System.Windows.Clipboard.GetDataObject();
                            plainText = System.Windows.Clipboard.GetText();
                            if (!string.IsNullOrEmpty(plainText))
                            {
                                System.Windows.Clipboard.SetText(plainText);
                            }
                        }
                    }
                    catch { }
                });

                if (string.IsNullOrEmpty(plainText))
                    return;

                // Wait briefly for the clipboard to register the change across the OS
                await Task.Delay(20);

                // Send Ctrl+V (releases Alt first so Ctrl+Alt+V hotkey doesn't trigger Paste Special)
                SendCtrlV();

                // Wait for target app to process paste
                await Task.Delay(250);

                app.Dispatcher.Invoke(() =>
                {
                    if (oldData != null)
                    {
                        try
                        {
                            System.Windows.Clipboard.SetDataObject(oldData, false);
                        }
                        catch { }
                    }
                });
            }
            catch { }
        });
    }

    private void SendCtrlV()
    {
        SyntheticInput.ReleaseKey((ushort)NativeMethods.VK_MENU);
        SyntheticInput.Chord(NativeMethods.VK_V, NativeMethods.VK_CONTROL);
    }
}
