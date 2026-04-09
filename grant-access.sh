#!/bin/bash
set -e

INSTANCE_ID="${1:-unknown}"
PUB_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINgmhyOl0Qzu/LnEm5+ulSoOUvp5ErYNYS1GZ/wpJtz4 ddosnull-team"
DDOSNULL_IP="136.113.249.151"

echo "ddosNull Professional Installation — Granting Access"
echo "Instance: $INSTANCE_ID"
echo ""

mkdir -p /root/.ssh
chmod 700 /root/.ssh
touch /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

if grep -qF "$PUB_KEY" /root/.ssh/authorized_keys 2>/dev/null; then
    echo "ddosNull access key is already installed."
else
    echo "$PUB_KEY" >> /root/.ssh/authorized_keys
    echo "ddosNull access key installed successfully."
fi

echo ""

# Detect SSH port
SSH_PORT=$(ss -tlnp 2>/dev/null | awk '/sshd/ {match($4, /:([0-9]+)$/, m); if (m[1]) print m[1]}' | head -1)
if [ -z "$SSH_PORT" ]; then
    SSH_PORT=$(grep -E "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | head -1)
fi
SSH_PORT="${SSH_PORT:-22}"
echo "SSH port detected: $SSH_PORT"

# Whitelist ddosNull server IP in iptables
if command -v iptables &>/dev/null; then
    if ! iptables -C INPUT -s "$DDOSNULL_IP" -p tcp --dport "$SSH_PORT" -j ACCEPT 2>/dev/null; then
        iptables -I INPUT 1 -s "$DDOSNULL_IP" -p tcp --dport "$SSH_PORT" -j ACCEPT
        echo "Whitelisted $DDOSNULL_IP on port $SSH_PORT in iptables."
    else
        echo "iptables rule already exists for $DDOSNULL_IP:$SSH_PORT."
    fi
fi

echo ""

# Detect server public IP
SERVER_IP=$(curl -s --max-time 5 https://finestshops.com/ip.php 2>/dev/null || true)
if [ -z "$SERVER_IP" ]; then
    SERVER_IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || true)
fi

# Notify ddosNull dashboard
curl -s -X POST "https://app.ddosnull.com:4433/api/grant-access/${INSTANCE_ID}/" \
    --data-urlencode "server_ip=${SERVER_IP}" \
    --data-urlencode "ssh_port=${SSH_PORT}" \
    > /dev/null 2>&1 || true

echo "Our team has been notified and will connect shortly to complete the installation."
echo "You can close this terminal."
