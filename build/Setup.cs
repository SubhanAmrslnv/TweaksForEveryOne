// Window Tweaks - single-file installer.
//
// Every file the program needs is embedded as a manifest resource, so this one
// .exe is the whole distribution. Build it with build\Build-Installer.ps1.
//
// NOTE: this is compiled by the csc.exe that ships with the .NET Framework,
// which is a C# 5 compiler. No string interpolation ($".."), no expression
// bodied members, no null-conditional (?.). Keep it plain.

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Windows.Forms;

namespace WindowTweaksSetup
{
    static class Program
    {
        [STAThread]
        static void Main(string[] args)
        {
            bool silent = false;
            foreach (string a in args)
            {
                string s = a.ToLowerInvariant();
                if (s == "/s" || s == "/silent" || s == "-silent") silent = true;
            }

            if (silent)
            {
                Installer inst = new Installer(null);
                bool ok = inst.Run(true, false);
                if (!ok) Environment.ExitCode = 1;
                return;
            }

            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new SetupForm());
        }
    }

    // ---------------------------------------------------------------- UI ----
    public class SetupForm : Form
    {
        CheckBox chkAutoStart;
        CheckBox chkTuning;
        Button btnInstall;
        Button btnClose;
        TextBox log;
        Label heading;
        Label blurb;

        public SetupForm()
        {
            Text = "Window Tweaks - Setup";
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            MinimizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            ClientSize = new Size(560, 470);
            BackColor = Color.FromArgb(31, 31, 31);
            ForeColor = Color.White;
            Font = new Font("Segoe UI", 9f);

            heading = new Label();
            heading.Text = "Window Tweaks";
            heading.Font = new Font("Segoe UI", 16f, FontStyle.Bold);
            heading.ForeColor = Color.White;
            heading.SetBounds(24, 20, 400, 34);
            Controls.Add(heading);

            blurb = new Label();
            blurb.Text = "Magnetic window snapping, ice glide, always-on-top and position memory.\r\n"
                       + "Installs to your user profile. No admin rights, no system files.";
            blurb.ForeColor = Color.FromArgb(154, 154, 154);
            blurb.SetBounds(26, 58, 500, 40);
            Controls.Add(blurb);

            chkAutoStart = new CheckBox();
            chkAutoStart.Text = "Start automatically when I sign in";
            chkAutoStart.Checked = true;
            chkAutoStart.ForeColor = Color.White;
            chkAutoStart.SetBounds(26, 110, 480, 24);
            Controls.Add(chkAutoStart);

            chkTuning = new CheckBox();
            chkTuning.Text = "Also apply the Windows animation and Explorer tuning (reversible)";
            chkTuning.Checked = false;
            chkTuning.ForeColor = Color.White;
            chkTuning.SetBounds(26, 138, 500, 24);
            Controls.Add(chkTuning);

            Label note = new Label();
            note.Text = "The tuning writes to HKCU only and saves your original values first.\r\n"
                      + "Run scripts\\Restore-Windows-Tuning.ps1 to undo it at any time.";
            note.ForeColor = Color.FromArgb(154, 154, 154);
            note.SetBounds(46, 164, 490, 36);
            Controls.Add(note);

            log = new TextBox();
            log.Multiline = true;
            log.ReadOnly = true;
            log.ScrollBars = ScrollBars.Vertical;
            log.BackColor = Color.FromArgb(23, 23, 23);
            log.ForeColor = Color.FromArgb(200, 200, 200);
            log.BorderStyle = BorderStyle.FixedSingle;
            log.Font = new Font("Consolas", 8.5f);
            log.SetBounds(26, 210, 508, 190);
            log.Text = "Ready to install." + Environment.NewLine;
            Controls.Add(log);

            btnInstall = new Button();
            btnInstall.Text = "Install";
            btnInstall.SetBounds(330, 415, 100, 32);
            btnInstall.Click += new EventHandler(OnInstall);
            Controls.Add(btnInstall);

            btnClose = new Button();
            btnClose.Text = "Close";
            btnClose.SetBounds(438, 415, 96, 32);
            btnClose.Click += delegate { Close(); };
            Controls.Add(btnClose);

            AcceptButton = btnInstall;
        }

        void Say(string line)
        {
            log.AppendText(line + Environment.NewLine);
            log.SelectionStart = log.TextLength;
            log.ScrollToCaret();
            Application.DoEvents();
        }

        void OnInstall(object sender, EventArgs e)
        {
            btnInstall.Enabled = false;
            chkAutoStart.Enabled = false;
            chkTuning.Enabled = false;
            log.Clear();

            Installer inst = new Installer(new Action<string>(Say));
            bool ok = inst.Run(chkAutoStart.Checked, chkTuning.Checked);

            if (ok)
            {
                Say("");
                Say("Done. Press Win+Ctrl+W for settings.");
                btnClose.Text = "Finish";
            }
            else
            {
                Say("");
                Say("Install did not complete. See the messages above.");
                btnInstall.Enabled = true;
                chkAutoStart.Enabled = true;
                chkTuning.Enabled = true;
            }
        }
    }

    // --------------------------------------------------------- installer ----
    public class Installer
    {
        Action<string> say;

        public Installer(Action<string> logger)
        {
            say = logger;
        }

        void Log(string s)
        {
            if (say != null) say(s);
        }

        public bool Run(bool autoStart, bool tuning)
        {
            try
            {
                string dest = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "Window Tweaks");

                Log("[1/5] Looking for AutoHotkey v2");
                string ahk = FindAutoHotkey();
                if (ahk == null)
                {
                    Log("      Not installed - fetching it with winget (this can take a minute)");
                    if (!InstallAutoHotkey())
                    {
                        Log("      Could not install AutoHotkey automatically.");
                        Log("      Get it from https://www.autohotkey.com (v2) and run this again.");
                        return false;
                    }
                    ahk = FindAutoHotkey();
                    if (ahk == null)
                    {
                        Log("      Still not found after installing. Stopping.");
                        return false;
                    }
                }
                Log("      " + ahk);

                Log("[2/5] Stopping any running copy");
                int stopped = StopRunning();
                Log(stopped > 0 ? "      Stopped " + stopped : "      Nothing was running");
                System.Threading.Thread.Sleep(700);

                Log("[3/5] Installing to " + dest);
                int n = Extract(dest);
                Log("      Wrote " + n + " files");

                Log("[4/5] Creating shortcuts");
                string target = Path.Combine(dest, "WindowTweaks.ahk");
                MakeShortcut(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs),
                                          "Window Tweaks.lnk"), ahk, target, dest);
                MakeShortcut(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),
                                          "Window Tweaks.lnk"), ahk, target, dest);
                string startup = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Startup),
                                              "Window Tweaks.lnk");
                if (autoStart)
                {
                    MakeShortcut(startup, ahk, target, dest);
                    Log("      Start Menu, Desktop, Startup");
                }
                else
                {
                    if (File.Exists(startup)) File.Delete(startup);
                    Log("      Start Menu, Desktop (no autostart)");
                }

                Log("[5/5] Windows settings");
                EnsureDragFullWindows();
                if (tuning)
                {
                    string script = Path.Combine(dest, "scripts\\Apply-Windows-Tuning.ps1");
                    if (File.Exists(script))
                    {
                        RunPowerShell(script);
                        Log("      Applied the animation and Explorer tuning");
                    }
                }
                else
                {
                    Log("      Required setting checked; run scripts\\Apply-Windows-Tuning.ps1 for the rest");
                }

                Process.Start(new ProcessStartInfo(ahk, "\"" + target + "\"") { WorkingDirectory = dest });
                Log("      Started - look for the tray icon");
                return true;
            }
            catch (Exception ex)
            {
                Log("ERROR: " + ex.Message);
                return false;
            }
        }

        // ---- AutoHotkey -----------------------------------------------------
        static string FindAutoHotkey()
        {
            string lad = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            string pf = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
            string[] paths = new string[] {
                Path.Combine(lad, "Programs\\AutoHotkey\\v2\\AutoHotkey64.exe"),
                Path.Combine(pf,  "AutoHotkey\\v2\\AutoHotkey64.exe"),
                Path.Combine(lad, "Programs\\AutoHotkey\\v2\\AutoHotkey32.exe"),
                Path.Combine(pf,  "AutoHotkey\\v2\\AutoHotkey32.exe")
            };
            foreach (string p in paths) if (File.Exists(p)) return p;
            return null;
        }

        static bool InstallAutoHotkey()
        {
            try
            {
                ProcessStartInfo psi = new ProcessStartInfo("winget",
                    "install --id AutoHotkey.AutoHotkey --source winget " +
                    "--accept-package-agreements --accept-source-agreements --disable-interactivity");
                psi.UseShellExecute = false;
                psi.CreateNoWindow = true;
                Process p = Process.Start(psi);
                p.WaitForExit(300000);
                return true;
            }
            catch { return false; }
        }

        static int StopRunning()
        {
            int n = 0;
            try
            {
                using (var searcher = new System.Management.ManagementObjectSearcher("SELECT ProcessId, CommandLine FROM Win32_Process WHERE Name LIKE 'AutoHotkey%'"))
                {
                    foreach (System.Management.ManagementObject obj in searcher.Get())
                    {
                        string cmd = obj["CommandLine"] as string;
                        if (cmd != null && cmd.Contains("WindowTweaks.ahk"))
                        {
                            try
                            {
                                int pid = Convert.ToInt32(obj["ProcessId"]);
                                Process.GetProcessById(pid).Kill();
                                n++;
                            }
                            catch { }
                        }
                    }
                }
            }
            catch { }
            return n;
        }

        // ---- embedded files -------------------------------------------------
        // Resource names look like "res.WindowTweaks.ahk" or
        // "res.scripts_Apply-Windows-Tuning.ps1"; the underscore marks a
        // subfolder, since resource names can't carry a path separator.
        static int Extract(string dest)
        {
            Directory.CreateDirectory(dest);
            Assembly asm = Assembly.GetExecutingAssembly();
            int count = 0;

            foreach (string res in asm.GetManifestResourceNames())
            {
                if (!res.StartsWith("res.")) continue;
                string rel = res.Substring(4).Replace("_", "\\");
                string outPath = Path.Combine(dest, rel);
                string dir = Path.GetDirectoryName(outPath);
                if (!Directory.Exists(dir)) Directory.CreateDirectory(dir);

                using (Stream s = asm.GetManifestResourceStream(res))
                using (FileStream fs = new FileStream(outPath, FileMode.Create, FileAccess.Write))
                {
                    s.CopyTo(fs);
                }
                count++;
            }
            return count;
        }

        // ---- shortcuts (late-bound COM, no interop assembly needed) ---------
        static void MakeShortcut(string linkPath, string exe, string arg, string workDir)
        {
            Type shellType = Type.GetTypeFromProgID("WScript.Shell");
            object shell = Activator.CreateInstance(shellType);
            object link = shellType.InvokeMember("CreateShortcut",
                BindingFlags.InvokeMethod, null, shell, new object[] { linkPath });
            Type lt = link.GetType();
            lt.InvokeMember("TargetPath", BindingFlags.SetProperty, null, link, new object[] { exe });
            lt.InvokeMember("Arguments", BindingFlags.SetProperty, null, link, new object[] { "\"" + arg + "\"" });
            lt.InvokeMember("WorkingDirectory", BindingFlags.SetProperty, null, link, new object[] { workDir });
            lt.InvokeMember("Description", BindingFlags.SetProperty, null, link, new object[] { "Window Tweaks" });
            lt.InvokeMember("Save", BindingFlags.InvokeMethod, null, link, null);
        }

        [System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true)]
        static extern bool SystemParametersInfo(uint uiAction, uint uiParam, IntPtr pvParam, uint fWinIni);

        static void EnsureDragFullWindows()
        {
            try
            {
                Microsoft.Win32.RegistryKey k =
                    Microsoft.Win32.Registry.CurrentUser.OpenSubKey("Control Panel\\Desktop", true);
                if (k == null) return;
                object v = k.GetValue("DragFullWindows");
                if (v == null || v.ToString() != "1")
                {
                    string dest = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Window Tweaks Backup");
                    Directory.CreateDirectory(dest);
                    string backup = Path.Combine(dest, "drag-backup.txt");
                    if (!File.Exists(backup))
                        File.WriteAllText(backup, v == null ? "absent" : v.ToString());

                    k.SetValue("DragFullWindows", "1", Microsoft.Win32.RegistryValueKind.String);
                    SystemParametersInfo(0x0025, 1, IntPtr.Zero, 3);
                }
                k.Close();
            }
            catch { }
        }

        static void RunPowerShell(string script)
        {
            try
            {
                ProcessStartInfo psi = new ProcessStartInfo("powershell",
                    "-NoProfile -ExecutionPolicy Bypass -File \"" + script + "\"");
                psi.UseShellExecute = false;
                psi.CreateNoWindow = true;
                Process p = Process.Start(psi);
                p.WaitForExit(120000);
            }
            catch { }
        }
    }
}
