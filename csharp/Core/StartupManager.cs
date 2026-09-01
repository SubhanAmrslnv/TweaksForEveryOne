using System;
using System.IO;

namespace WindowTweaks.Core;

/// <summary>
/// "Start with Windows", implemented as a shortcut in the user's own Startup folder.
///
/// Deliberately NOT an HKLM Run key or a scheduled task: those need admin, and the app itself
/// needs none. The installer writes an identical shortcut, so the two agree on the path and
/// either can remove it.
///
/// The shortcut is created through WScript.Shell over late-bound COM, which avoids taking a
/// dependency on the Windows Script Host interop assembly for a single call.
/// </summary>
internal static class StartupManager
{
    private const string ShortcutName = "WindowTweaks.lnk";

    private static string ShortcutPath =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Startup), ShortcutName);

    public static bool IsEnabled()
    {
        try
        {
            return File.Exists(ShortcutPath);
        }
        catch
        {
            return false;
        }
    }

    public static void SetEnabled(bool enabled)
    {
        if (enabled) Create();
        else Remove();
    }

    private static void Create()
    {
        try
        {
            string? exePath = Environment.ProcessPath;
            if (string.IsNullOrEmpty(exePath) || !File.Exists(exePath)) return;

            Type? shellType = Type.GetTypeFromProgID("WScript.Shell");
            if (shellType == null) return;

            object? shell = Activator.CreateInstance(shellType);
            if (shell == null) return;

            object? shortcut = shellType.InvokeMember("CreateShortcut",
                System.Reflection.BindingFlags.InvokeMethod, null, shell, new object[] { ShortcutPath });
            if (shortcut == null) return;

            Type shortcutType = shortcut.GetType();
            SetProperty(shortcutType, shortcut, "TargetPath", exePath);
            SetProperty(shortcutType, shortcut, "WorkingDirectory", Path.GetDirectoryName(exePath) ?? string.Empty);
            SetProperty(shortcutType, shortcut, "Description", "Window Tweaks");
            shortcutType.InvokeMember("Save", System.Reflection.BindingFlags.InvokeMethod, null, shortcut, null);
        }
        catch
        {
            // A failed shortcut write is reported by IsEnabled() coming back false; it is not
            // worth an exception on a settings toggle.
        }
    }

    private static void Remove()
    {
        try
        {
            string path = ShortcutPath;
            if (File.Exists(path)) File.Delete(path);
        }
        catch
        {
        }
    }

    private static void SetProperty(Type type, object instance, string name, string value)
    {
        type.InvokeMember(name, System.Reflection.BindingFlags.SetProperty, null, instance, new object[] { value });
    }
}
