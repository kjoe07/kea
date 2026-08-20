#!/bin/bash
set -e

# Display version at startup
echo "[Entrypoint] Starting Kea-Stork Container Version ${BUILD_VERSION:-1.1}"

# Default environment variables (can be overridden in Unraid Docker template)
WEBMIN_REFERERS="${WEBMIN_REFERERS:-*}"
STORK_AGENT_HOST="${STORK_AGENT_HOST:-0.0.0.0}"
STORK_AGENT_PORT="${STORK_AGENT_PORT:-8081}"
STORK_AGENT_SERVER_URL="${STORK_AGENT_SERVER_URL:-http://192.168.0.240:8080}"
PROMETHEUS_EXPORTER_ADDR="${PROMETHEUS_EXPORTER_ADDR:-0.0.0.0}"

# --- WEBMIN INITIALIZATION ---
if [ ! -f /etc/webmin/miniserv.conf ]; then
    echo "[Entrypoint] Initializing Webmin configuration..."
    cp -r /etc/webmin.default/* /etc/webmin/
    
    # Disable Webmin internal SSL for HTTP reverse proxying via SWAG/Nginx
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

    if grep -q "^referers=" /etc/webmin/config; then
        sed -i "s/^referers=.*/referers=${WEBMIN_REFERERS}/g" /etc/webmin/config
    else
        echo "referers=${WEBMIN_REFERERS}" >> /etc/webmin/config
    fi
fi

# --- CREATE RUNTIME & LOG DIRECTORIES ---
# /run is a tmpfs mount inside memory and must be recreated on boot
mkdir -p /var/run/kea /var/log/kea /var/lib/kea /etc/kea/logs /usr/lib/stork-agent/hooks
# Fix Kea 2.6 socket permissions requirement
chmod 750 /var/run/kea

# Create log files if they don't exist so tail doesn't fail
touch /var/log/kea/kea-dhcp4.log /var/log/kea/stork-agent.log

# --- START BACKGROUND SERVICES ---

echo "Starting Webmin..."
service webmin start

echo "Starting Grafana Alloy..."
/usr/bin/alloy run /etc/alloy/config.alloy >> /var/log/kea/alloy.log 2>&1 &

if [ -f /etc/kea/kea-dhcp-ddns.conf ]; then
    echo "Starting Kea DHCP-DDNS Server..."
    /usr/sbin/kea-dhcp-ddns -c /etc/kea/kea-dhcp-ddns.conf >> /var/log/kea/kea-ddns.log 2>&1 &
fi

echo "Starting Kea DHCPv4 Server..."
/usr/sbin/kea-dhcp4 -c /etc/kea/kea-dhcp4.conf >> /var/log/kea/kea-dhcp4.log 2>&1 &

# Pause 3 seconds so kea-dhcp4 and kea-ctrl-agent create their sockets in /run/kea
sleep 3

echo "Starting Stork Agent..."
/usr/bin/stork-agent \
  --host "${STORK_AGENT_HOST}" \
  --port "${STORK_AGENT_PORT}" \
  --server-url "${STORK_AGENT_SERVER_URL}" \
  --prometheus-kea-exporter-address="${PROMETHEUS_EXPORTER_ADDR}" >> /var/log/kea/stork-agent.log 2> /var/log/kea/stork-agent.err &

# --- KEEP CONTAINER ALIVE & OUTPUT LOGS ---
echo "All services started successfully (v${BUILD_VERSION:-1.1})."
exec tail -f /var/log/kea/kea-dhcp4.log /var/log/kea/stork-agent.log