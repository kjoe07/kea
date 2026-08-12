#!/bin/bash
set -e

# Default to allowing all referers (*) if the user didn't specify WEBMIN_REFERERS in Unraid
WEBMIN_REFERERS="${WEBMIN_REFERERS:-*}"

# --- WEBMIN INITIALIZATION ---
if [ ! -f /etc/webmin/miniserv.conf ]; then
    echo "[Entrypoint] Initializing Webmin configuration..."
    cp -r /etc/webmin.default/* /etc/webmin/
    
    # Disable Webmin internal SSL (ssl=0) for HTTP reverse proxying via SWAG/Nginx
    sed -i 's/ssl=1/ssl=0/g' /etc/webmin/miniserv.conf
    
    # Trust reverse proxy host headers
    if ! grep -q "trust_unknown_referers=1" /etc/webmin/miniserv.conf; then
        echo "trust_unknown_referers=1" >> /etc/webmin/miniserv.conf
    fi
    
    # Set allowed referers
    if grep -q "^referers=" /etc/webmin/config; then
        sed -i "s/^referers=.*/referers=${WEBMIN_REFERERS}/g" /etc/webmin/config
    else
        echo "referers=${WEBMIN_REFERERS}" >> /etc/webmin/config
    fi
else
    echo "[Entrypoint] Existing Webmin configuration detected."
    
    if ! grep -q "trust_unknown_referers=1" /etc/webmin/miniserv.conf; then
        echo "trust_unknown_referers=1" >> /etc/webmin/miniserv.conf
    fi

    # Dynamically update referers in existing mounted /etc/webmin/config on start
    if grep -q "^referers=" /etc/webmin/config; then
        sed -i "s/^referers=.*/referers=${WEBMIN_REFERERS}/g" /etc/webmin/config
    else
        echo "referers=${WEBMIN_REFERERS}" >> /etc/webmin/config
    fi
fi

# Create required PID, lockfile, and logging directories if missing
mkdir -p /run/kea /var/log/kea /var/lib/kea

# --- START SERVICES ---
echo "Starting Webmin..."
service webmin start

echo "Starting Grafana Alloy..."
/usr/bin/alloy run /etc/alloy/config.alloy &

echo "Starting Stork Agent..."
/usr/bin/stork-agent &

echo "Starting Kea Control Agent..."
kea-ctrl-agent -c /etc/kea/kea-ctrl-agent.conf &

# Check if DDNS configuration exists before starting kea-dhcp-ddns
if [ -f /etc/kea/kea-dhcp-ddns.conf ]; then
    echo "Starting Kea DHCP-DDNS Server..."
    kea-dhcp-ddns -c /etc/kea/kea-dhcp-ddns.conf &
else
    echo "[Notice] /etc/kea/kea-dhcp-ddns.conf not found. Skipping Kea DHCP-DDNS startup."
fi

echo "Starting Kea DHCPv4 Server..."
exec kea-dhcp4 -c /etc/kea/kea-dhcp4.conf