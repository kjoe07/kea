#!/bin/bash
set -e

# --- WEBMIN INITIALIZATION ---
if [ ! -f /etc/webmin/miniserv.conf ]; then
    echo "[Entrypoint] Initializing Webmin configuration..."
    cp -r /etc/webmin.default/* /etc/webmin/
    
    # Disable Webmin internal SSL (ssl=0) for HTTP reverse proxying via SWAG
    sed -i 's/ssl=1/ssl=0/g' /etc/webmin/miniserv.conf
    
    # Trust reverse proxy host headers and disable referer blocking
    if ! grep -q "trust_unknown_referers=1" /etc/webmin/miniserv.conf; then
        echo "trust_unknown_referers=1" >> /etc/webmin/miniserv.conf
    fi
    
    if ! grep -q "referers=" /etc/webmin/config; then
        echo "referers=master.kjoe.org slave.kjoe.org" >> /etc/webmin/config
    fi
else
    echo "[Entrypoint] Existing Webmin configuration detected."
    if ! grep -q "trust_unknown_referers=1" /etc/webmin/miniserv.conf; then
        echo "trust_unknown_referers=1" >> /etc/webmin/miniserv.conf
    fi
fi

# Create logging directory if missing
mkdir -p /var/log/kea /var/lib/kea

# --- START SERVICES ---
echo "Starting Webmin..."
service webmin start

echo "Starting Grafana Alloy..."
/usr/bin/alloy run /etc/alloy/config.alloy &

echo "Starting Stork Agent..."
/usr/bin/stork-agent &

echo "Starting Kea Control Agent..."
kea-ctrl-agent -c /etc/kea/kea-ctrl-agent.conf &

echo "Starting Kea DHCPv4 Server..."
exec kea-dhcp4 -c /etc/kea/kea-dhcp4.conf