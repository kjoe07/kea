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

# Default Environment Variables matching your supervisor flags
ENV WEBMIN_REFERERS="*" \
    STORK_AGENT_HOST="192.168.0.239" \
    STORK_AGENT_PORT="8081" \
    STORK_AGENT_SERVER_URL="http://192.168.0.240:8080" \
    PROMETHEUS_EXPORTER_ADDR="0.0.0.0"

# Unraid Docker UI Annotations
LABEL net.unraid.docker.managed="dockerman" \
      net.unraid.docker.webui="https://[IP]:[PORT:10000]" \
      net.unraid.docker.icon="https://www.isc.org/images/isclogos/kea-logo-cmyk-circle.png"

# Install Kea DHCP & core tooling
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    gnupg \
    lsb-release \
    ca-certificates \
    procps \
    kea-dhcp4-server \
    kea-dhcp-ddns-server \
    kea-ctrl-agent \
    kea-admin \
    && rm -rf /var/lib/apt/lists/*

# Install Webmin
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

RUN cp -r /etc/webmin /etc/webmin.default

# Install Grafana Alloy
RUN mkdir -p /etc/apt/keyrings/ && \
    curl -fsSL https://apt.grafana.com/gpg.key | gpg --dearmor -o /etc/apt/keyrings/grafana.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" > /etc/apt/sources.list.d/grafana.list && \
    apt-get update && apt-get install -y --no-install-recommends alloy && \
    rm -rf /var/lib/apt/lists/*

# Copy and install Stork Agent
COPY --from=stork-downloader /*.deb /tmp/
RUN dpkg -i /tmp/*.deb || apt-get install -f -y && rm -f /tmp/*.deb

# Pre-create standard runtime/log directories
RUN mkdir -p /run/kea /var/run/kea /var/log/kea /var/lib/kea /etc/kea/logs /usr/lib/stork-agent/hooks

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Declare volume mount points corresponding to your Unraid Appdata paths:
# /etc/kea     -> /mnt/user/appdata/kea-primary
# /var/log/kea -> /mnt/user/appdata/kea-primary/logs
# /var/lib/kea -> /mnt/user/appdata/kea-primary/lib
# /etc/alloy   -> /mnt/user/appdata/kea-primary/alloy
# /etc/webmin  -> /mnt/user/appdata/kea-primary/webmin
VOLUME ["/etc/kea", "/var/log/kea", "/var/lib/kea", "/etc/alloy", "/etc/webmin"]

EXPOSE 67/udp 68/udp 546/udp 547/udp 8000/tcp 8081/tcp 10000/tcp 12345/tcp 9547/tcp

ENTRYPOINT ["/entrypoint.sh"]