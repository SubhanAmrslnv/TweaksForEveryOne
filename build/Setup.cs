// Window Tweaks - single-file installer.
//
// Every file the program needs is embedded as a manifest resource, so this one
// .exe is the whole distribution. Build it with build\Build-Installer.bat.
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
        bool installing;

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
                      + "Run scripts\\Restore-Windows-Tuning.bat to undo it at any time.";
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

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            if (installing)
            {
                e.Cancel = true;
                return;
            }
            base.OnFormClosing(e);
        }

        void Say(string line)
        {
            if (IsDisposed) return;
            if (InvokeRequired)
            {
                try
                {
                    if (!IsDisposed && IsHandleCreated)
                        BeginInvoke(new Action<string>(Say), new object[] { line });
                }
                catch { }
                return;
            }
            log.AppendText(line + Environment.NewLine);
            log.SelectionStart = log.TextLength;
            log.ScrollToCaret();
        }

        void OnInstall(object sender, EventArgs e)
        {
            if (installing) return;
            installing = true;
            btnInstall.Enabled = false;
            btnClose.Enabled = false;
            chkAutoStart.Enabled = false;
            chkTuning.Enabled = false;
            log.Clear();

            bool autoStart = chkAutoStart.Checked;
            bool tuning = chkTuning.Checked;

            System.Threading.ThreadPool.QueueUserWorkItem(delegate
            {
                Installer inst = new Installer(new Action<string>(Say));
                bool ok = inst.Run(autoStart, tuning);
                if (!IsDisposed && IsHandleCreated)
                {
                    try
                    {
                        BeginInvoke(new Action<bool>(OnInstallComplete), new object[] { ok });
                    }
                    catch { }
                }
            });
        }

        void OnInstallComplete(bool ok)
        {
            if (IsDisposed) return;
            installing = false;
            btnClose.Enabled = true;

            if (ok)
            {
                Say("");
                Say("Done. Press Shift+Alt+W for settings.");
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
                Log(ApplyBaselineSettings(dest)
                    ? "      Applied the packaged baseline settings"
                    : "      Kept your existing settings.ini");

                Log("[4/5] Creating shortcuts");
                string target = Path.Combine(dest, "WindowTweaks.ahk");
                string targetArg = "\"" + target + "\"";
                string icoPath = Path.Combine(dest, "WindowTweaks.ico");
                string programsDir = Environment.GetFolderPath(Environment.SpecialFolder.Programs);
                MakeShortcut(Path.Combine(programsDir, "Window Tweaks.lnk"),
                             ahk, targetArg, dest, "Window Tweaks", icoPath);
                string spUi = Path.Combine(dest, "StealthPanicUI.ahk");
                string spIni = Path.Combine(dest, "StealthPanic.ini");
                MakeShortcut(Path.Combine(programsDir, "Stealth Panic Mode Settings.lnk"),
                             ahk, "\"" + spUi + "\" \"" + spIni + "\"", dest, "Stealth Panic Mode Settings", null);
                MakeShortcut(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),
                                          "Window Tweaks.lnk"), ahk, targetArg, dest, "Window Tweaks", icoPath);
                string startup = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Startup),
                                              "Window Tweaks.lnk");
                if (autoStart)
                {
                    MakeShortcut(startup, ahk, targetArg, dest, "Window Tweaks", icoPath);
                    Log("      Start Menu, Desktop, Startup");
                }
                else
                {
                    if (File.Exists(startup)) File.Delete(startup);
                    Log("      Start Menu, Desktop (no autostart)");
                }

                Log("[5/5] Windows settings");
                if (tuning)
                {
                    string script = Path.Combine(dest, "scripts\\Apply-Windows-Tuning.bat");
                    if (!File.Exists(script))
                    {
                        Log("      The packaged Windows tuning script is missing.");
                        return false;
                    }
                    int exitCode = RunTuning(script);
                    if (exitCode != 0)
                    {
                        Log("      Windows tuning failed (exit " + exitCode + ").");
                        Log("      Run scripts\\Restore-Windows-Tuning.bat to undo any changes made.");
                        return false;
                    }
                    Log("      Applied the animation and Explorer tuning");
                }
                else
                {
                    Log("      Skipped Windows tuning");
                }

                using (Process started = Process.Start(new ProcessStartInfo(ahk, targetArg) { WorkingDirectory = dest })) { }
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
                // Visible on purpose: a setup that runs winget/PowerShell in a
                // hidden window is the dropper shape endpoint security flags, and
                // the user should see what is being installed or changed.
                psi.CreateNoWindow = false;
                using (Process p = Process.Start(psi))
                {
                    if (p == null) return false;
                    if (!p.WaitForExit(300000)) return false;
                    return p.ExitCode == 0;
                }
            }
            catch { return false; }
        }

        static int StopRunning()
        {
            int n = 0;
            try
            {
                using (var searcher = new System.Management.ManagementObjectSearcher("SELECT ProcessId, CommandLine FROM Win32_Process WHERE Name LIKE 'AutoHotkey%'"))
                using (var results = searcher.Get())
                {
                    foreach (System.Management.ManagementObject obj in results)
                    {
                        using (obj)
                        {
                            string cmd = obj["CommandLine"] as string;
                            if (cmd != null && (cmd.Contains("WindowTweaks.ahk") || cmd.Contains("StealthPanicUI.ahk")))
                            {
                                try
                                {
                                    // Ask first, force only as a fallback - the same
                                    // order as Install.bat. Kill() skips the program's
                                    // exit handler, which is what writes pending
                                    // settings and hands back every window it changed.
                                    int pid = Convert.ToInt32(obj["ProcessId"]);
                                    using (Process p = Process.GetProcessById(pid))
                                    {
                                        RunVisible("taskkill.exe", "/PID " + pid);
                                        if (!p.WaitForExit(5000)) p.Kill();
                                        n++;
                                    }
                                }
                                catch { }
                            }
                        }
                    }
                }
            }
            catch { }
            return n;
        }

        static void RunVisible(string exe, string args)
        {
            try
            {
                ProcessStartInfo psi = new ProcessStartInfo(exe, args);
                psi.UseShellExecute = false;
                psi.CreateNoWindow = false;   // visible, like every child this setup runs (docs\SECURITY.md)
                using (Process p = Process.Start(psi))
                {
                    if (p != null) p.WaitForExit(5000);
                }
            }
            catch { }
        }

        // Settings precedence, the same rule as Install.bat: an existing
        // settings.ini is the user's and is never touched; only a folder with
        // none gets the packaged baseline. Idempotent by construction.
        static bool ApplyBaselineSettings(string dest)
        {
            string target = Path.Combine(dest, "settings.ini");
            if (File.Exists(target)) return false;
            Assembly asm = Assembly.GetExecutingAssembly();
            using (Stream s = asm.GetManifestResourceStream("base.settings.ini"))
            {
                if (s == null) return false;
                using (FileStream fs = new FileStream(target, FileMode.CreateNew, FileAccess.Write))
                {
                    s.CopyTo(fs);
                }
            }
            return true;
        }

        // ---- embedded files -------------------------------------------------
        // Resource names look like "res.WindowTweaks.ahk" or
        // "res.scripts_Apply-Windows-Tuning.bat"; the underscore marks a
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
        static void MakeShortcut(string linkPath, string exe, string arguments, string workDir, string description, string iconPath)
        {
            Type shellType = Type.GetTypeFromProgID("WScript.Shell");
            object shell = Activator.CreateInstance(shellType);
            object link = shellType.InvokeMember("CreateShortcut",
                BindingFlags.InvokeMethod, null, shell, new object[] { linkPath });
            Type lt = link.GetType();
            lt.InvokeMember("TargetPath", BindingFlags.SetProperty, null, link, new object[] { exe });
            lt.InvokeMember("Arguments", BindingFlags.SetProperty, null, link, new object[] { arguments });
            lt.InvokeMember("WorkingDirectory", BindingFlags.SetProperty, null, link, new object[] { workDir });
            lt.InvokeMember("Description", BindingFlags.SetProperty, null, link, new object[] { description });
            if (!string.IsNullOrEmpty(iconPath) && File.Exists(iconPath))
                lt.InvokeMember("IconLocation", BindingFlags.SetProperty, null, link, new object[] { iconPath + ",0" });
            lt.InvokeMember("Save", BindingFlags.InvokeMethod, null, link, null);
        }

        static int RunTuning(string script)
        {
            // Delayed expansion supplies the path after cmd's command parsing.
            ProcessStartInfo psi = new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, "cmd.exe"),
                "/d /s /v:on /c \"\"!WINDOW_TWEAKS_TUNING_SCRIPT!\" -Animations -Explorer\"");
            psi.WorkingDirectory = Path.GetDirectoryName(script);
            psi.UseShellExecute = false;
            psi.EnvironmentVariables["WINDOW_TWEAKS_TUNING_SCRIPT"] = script;
            using (Process p = Process.Start(psi))
            {
                if (p == null) throw new InvalidOperationException("Could not start the Windows tuning script.");
                p.WaitForExit();
                return p.ExitCode;
            }
        }
    }
}
