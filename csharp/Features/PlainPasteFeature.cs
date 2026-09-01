using System;
using System.Threading.Tasks;
using System.Windows;
using WindowTweaks.Core;
using System.Runtime.InteropServices;

namespace WindowTweaks.Features;

public class PlainPasteFeature
{
    public void Toggle()
    {
        if (!System.Windows.Clipboard.ContainsText())
            return;

        // Run asynchronously so we can sleep without blocking the hotkey thread
        Task.Run(async () =>
        {
            try
            {
                System.Windows.IDataObject oldData = null;
                string plainText = null;

                System.Windows.Application.Current.Dispatcher.Invoke(() =>
                {
                    oldData = System.Windows.Clipboard.GetDataObject();
                    plainText = System.Windows.Clipboard.GetText();
                    if (!string.IsNullOrEmpty(plainText))
                    {
                        System.Windows.Clipboard.SetText(plainText);
                    }
                });

                if (string.IsNullOrEmpty(plainText))
                    return;

                // Wait briefly for the clipboard to register the change across the OS
                await Task.Delay(20);

                // Send Ctrl+V
                SendCtrlV();

                // Wait for target app to process paste
                await Task.Delay(150);

                System.Windows.Application.Current.Dispatcher.Invoke(() =>
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
        // Use SendInput to send Ctrl Down, V Down, V Up, Ctrl Up
        NativeMethods.INPUT[] inputs = new NativeMethods.INPUT[4];

        // Ctrl down
        inputs[0].type = NativeMethods.INPUT_KEYBOARD;
        inputs[0].u.ki.wVk = NativeMethods.VK_CONTROL;
        inputs[0].u.ki.dwFlags = 0;

        // V down
        inputs[1].type = NativeMethods.INPUT_KEYBOARD;
        inputs[1].u.ki.wVk = NativeMethods.VK_V;
        inputs[1].u.ki.dwFlags = 0;

        // V up
        inputs[2].type = NativeMethods.INPUT_KEYBOARD;
        inputs[2].u.ki.wVk = NativeMethods.VK_V;
        inputs[2].u.ki.dwFlags = NativeMethods.KEYEVENTF_KEYUP;

        // Ctrl up
        inputs[3].type = NativeMethods.INPUT_KEYBOARD;
        inputs[3].u.ki.wVk = NativeMethods.VK_CONTROL;
        inputs[3].u.ki.dwFlags = NativeMethods.KEYEVENTF_KEYUP;

        NativeMethods.SendInput((uint)inputs.Length, inputs, Marshal.SizeOf(typeof(NativeMethods.INPUT)));
    }
}
