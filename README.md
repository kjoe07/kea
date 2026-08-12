# ISC Kea DHCP + Stork Agent + Grafana Alloy + Webmin Docker Image

A lightweight, multi-service Docker container running **ISC Kea DHCP**, **ISC Stork Agent** (for DHCP monitoring & management), **Grafana Alloy** (telemetry and log shipping), and **Webmin** on Debian 13 (Trixie).

---

## 🗂️ Required Host Directories (Mounts)

Create the necessary persistent directories on your host before launching:

```bash
mkdir -p /mnt/user/appdata/kea-primary/alloy
mkdir -p /mnt/user/appdata/kea-primary/logs
mkdir -p /mnt/user/appdata/kea-primary/lib
mkdir -p /mnt/user/appdata/kea-primary/webmin

ere is the complete set of files to turn your kea-primary setup into a clean, reproducible multi-service container running ISC Kea DHCP, ISC Stork Agent, Grafana Alloy, and Webmin on Debian 13 (Trixie)—matching the exact structure used for your BIND 9 container.

1. Dockerfile
Uses multi-stage building to pull the official isc-stork-agent package, installs Kea 2.6+ natively from Debian Trixie, installs Webmin and Grafana Alloy, and includes the default Webmin backup mechanism for seamless volume bootstrapping.

Dockerfile
# Stage 1: Download official Stork Agent Debian package from ISC Cloudsmith repo
FROM debian:trixie-slim AS stork-downloader

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    gnupg \
    && rm -rf /var/lib/apt/lists/*

RUN curl -1sLf 'https://dl.cloudsmith.io/public/isc/stork/setup.deb.sh' | bash
RUN apt-get update && apt-get download isc-stork-agent

# Stage 2: Final runtime container
FROM debian:trixie-slim

ENV DEBIAN_FRONTEND=noninteractive

# Install base utilities, ISC Kea DHCP (Natively 2.6+ on Debian 13 / Trixie)
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    gnupg \
    lsb-release \
    ca-certificates \
    procps \
    kea-dhcp4-server \
    kea-dhcp6-server \
    kea-dhcp-ddns-server \
    kea-ctrl-agent \
    kea-admin \
    && rm -rf /var/lib/apt/lists/*

# Install Webmin (Direct official package download)
RUN apt-get update && apt-get install -y --no-install-recommends \
    perl \
    libnet-ssleay-perl \
    openssl \
    libauthen-pam-perl \
    libio-pty-perl \
    shared-mime-info \
    && curl -fsSL -o /tmp/webmin.deb https://www.webmin.com/download/deb/webmin-current.deb \
    && dpkg -i /tmp/webmin.deb || apt-get install -f -y \
    && rm -f /tmp/webmin.deb \
    && rm -rf /var/lib/apt/lists/*

# Back up fresh default Webmin config before any volumes are mounted over /etc/webmin
RUN cp -r /etc/webmin /etc/webmin.default

# Install Grafana Alloy
RUN mkdir -p /etc/apt/keyrings/ && \
    curl -fsSL https://apt.grafana.com/gpg.key | gpg --dearmor -o /etc/apt/keyrings/grafana.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" > /etc/apt/sources.list.d/grafana.list && \
    apt-get update && apt-get install -y --no-install-recommends alloy && \
    rm -rf /var/lib/apt/lists/*

# Copy and install Stork Agent from Stage 1
COPY --from=stork-downloader /*.deb /tmp/
RUN dpkg -i /tmp/*.deb || apt-get install -f -y && rm -f /tmp/*.deb

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Declare standard volume paths
VOLUME ["/etc/kea", "/var/log/kea", "/var/lib/kea", "/etc/alloy", "/etc/webmin"]

# Exposed Ports:
# 67/udp (DHCPv4), 68/udp (DHCPv4 Client), 546/udp & 547/udp (DHCPv6)
# 8000/tcp (Kea Control Agent / Stork Hook), 8080/tcp (Stork Agent)
# 10000/tcp (Webmin), 12345/tcp (Grafana Alloy)
EXPOSE 67/udp 68/udp 546/udp 547/udp 8000/tcp 8080/tcp 10000/tcp 12345/tcp

ENTRYPOINT ["/entrypoint.sh"]
2. entrypoint.sh
Handles automatic initialization of /etc/webmin on first boot, disables Webmin SSL for HTTP reverse proxying via SWAG, configures trusted proxy referers, and manages starting all background services.

Bash
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
3. .github/workflows/docker-build.yml
This GitHub Action builds the container on pull requests (to catch errors before merging) and publishes to GHCR on merge to main.

YAML
name: Build and Push Kea Container Image

on:
  push:
    branches:
      - main
  pull_request:
    branches:
      - main
  workflow_dispatch:

permissions:
  contents: read
  packages: write

env:
  NODE_OPTIONS: "--use-system-ca"

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Repository
        uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to GitHub Container Registry
        if: github.event_name != 'pull_request'
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Downcase Repository Name for GHCR
        id: string
        run: |
          echo "repo=${GITHUB_REPOSITORY,,}" >> $GITHUB_OUTPUT

      - name: Extract metadata (tags, labels)
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ghcr.io/${{ steps.string.outputs.repo }}
          tags: |
            type=raw,value=latest,enable=${{ github.ref == 'refs/heads/main' }}
            type=ref,event=pr

      - name: Build and Push Docker Image
        uses: docker/build-push-action@v6
        with:
          context: .
          push: ${{ github.event_name != 'pull_request' }}
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
4. Updated README.md
Markdown
# ISC Kea DHCP + Stork Agent + Grafana Alloy + Webmin Docker Image

A lightweight, multi-service Docker container running **ISC Kea DHCP**, **ISC Stork Agent** (for DHCP monitoring & management), **Grafana Alloy** (telemetry and log shipping), and **Webmin** on Debian 13 (Trixie).

---

## 🗂️ Required Host Directories (Mounts)

Create the necessary persistent directories on your host before launching:

```bash
mkdir -p /mnt/user/appdata/kea-primary/alloy
mkdir -p /mnt/user/appdata/kea-primary/logs
mkdir -p /mnt/user/appdata/kea-primary/lib
mkdir -p /mnt/user/appdata/kea-primary/webmin```

###Volume Mount Breakdown
|Host |Path	|Container Path	|Mode	|Description
| ----|-----|---------------|-------|------------|
|/mnt/user/appdata/kea-primary	|/etc/kea	|rw	|Configuration directory (kea-dhcp4.conf, kea-ctrl-agent.conf).|
|/mnt/user/appdata/kea-primary/logs	|/var/log/kea	|rw	|Kea server operational logs.|
|/mnt/user/appdata/kea-primary/lib	|/var/lib/kea	|rw	|Active lease database and runtime state.|
|/mnt/user/appdata/kea-primary/alloy	|/etc/alloy	|rw	|Grafana Alloy configuration directory (config.alloy).|
|/mnt/user/appdata/kea-primary/webmin	|/etc/webmin	|rw	|Persistent Webmin users, credentials, and settings.|

### 🔌 Exposed Network Ports
|Port	|Protocol	|Service	|Purpose|
|-------|-----------|-----------|-------|
|67 / 68	|UDP	|Kea DHCPv4	DHCP Lease Requests & Discovery|
|8000	|TCP	|Kea Ctrl Agent	Rest API / Stork Server connection|
|8080	|TCP	|Stork Agent	Stork Agent monitoring endpoint|
|10000	|TCP	|Webmin	Web Administration UI|
|12345	|TCP	|Grafana Alloy	Alloy Telemetry endpoint|

### ⚙️ Environment Variables
|Variable	|Example |Value	|Description|
|-----------|--------|------|-----------|
|STORK_AGENT_HOST	| x.x.x.x	|IP address assigned to this container.|
|STORK_AGENT_SERVER_URL	| http://x.x.x.x:8080	URL of central Stork Server instance.|
|TZ	|America/New_York	| Container timezone setting.|

### 🚀 Execution Commands
Unraid / CLI Run Command
`Bash
docker run -d \
  --name='kea-primary' \
  --net='br0' \
  --ip='x.x.x.x' \
  --pids-limit 2048 \
  -e TZ="America/New_York" \
  -e HOST_OS="Unraid" \
  -e HOST_HOSTNAME="dell" \
  -e HOST_CONTAINERNAME="kea-primary" \
  -e STORK_AGENT_HOST='x.x.x.x' \
  -e STORK_AGENT_SERVER_URL='[http://x.x.x.x:8080](http://x.x.x.x:8080)' \
  -l net.unraid.docker.managed=dockerman \
  -l net.unraid.docker.icon='[https://www.isc.org/images/isclogos/kea-logo-cmyk-circle.png](https://www.isc.org/images/isclogos/kea-logo-cmyk-circle.png)' \
  -v '/mnt/user/appdata/kea-primary':'/etc/kea':'rw' \
  -v '/mnt/user/appdata/kea-primary/logs':'/var/log/kea':'rw' \
  -v '/mnt/user/appdata/kea-primary/lib':'/var/lib/kea':'rw' \
  -v '/mnt/user/appdata/kea-primary/alloy':'/etc/alloy':'rw' \
  -v '/mnt/user/appdata/kea-primary/webmin':'/etc/webmin':'rw' \
  --cap-add=NET_ADMIN \
  --cap-add=NET_RAW \
  ghcr.io/kjoe07/kea-alloy-stork-webmin:latest`

🔒 Webmin Initial Password Setup
To set the root account password for Webmin after first startup:

`Bash
 docker exec -it kea-primary /usr/share/webmin/changepass.pl /etc/webmin root your_secure_password`
