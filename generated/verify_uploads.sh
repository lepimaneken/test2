#!/bin/bash
echo "[🔍] Verifying files are accessible at https://domenca.vercel.app/generated..."
echo ""

files=(
    "payload.enc"
    "decoy.pdf"
    "payloads/stage1.bat"
    "payloads/stage2.ps1"
    "payloads/stage3.ps1"
    "index.html"
)

for file in "${files[@]}"; do
    url="https://domenca.vercel.app/generated/$file"
    status=$(curl -o /dev/null -s -w "%{http_code}" --head "$url")
    if [ "$status" = "200" ] || [ "$status" = "302" ]; then
        echo -e "  [✓] $file - OK"
    else
        echo -e "  [✗] $file - HTTP $status"
    fi
done
echo ""
echo "Run this on Windows VM: https://domenca.vercel.app/generated/payloads/stage1.bat"
