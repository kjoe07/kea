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