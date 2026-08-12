
Markdown
# ISC Kea DHCP + Stork Agent + Grafana Alloy + Webmin Docker Image

A lightweight, multi-service Docker container running **ISC Kea DHCP**, **ISC Stork Agent** (for DHCP monitoring & management), **Grafana Alloy** (telemetry and log shipping), and **Webmin** on Debian.

---

## 🗂️ Required Host Directories (Mounts)

Create the necessary persistent directories on your host before launching:

```bash
mkdir -p /mnt/user/appdata/kea-primary/alloy
mkdir -p /mnt/user/appdata/kea-primary/logs
mkdir -p /mnt/user/appdata/kea-primary/lib
mkdir -p /mnt/user/appdata/kea-primary/webmin```

Volume Mount Breakdown
| Host Path	| Container Path | Mode | Description |
| --- | --- | ---| --- | --- |
| /mnt/user/appdata/kea-primary	| /etc/kea | rw | Configuration directory (kea-dhcp4.conf, kea-ctrl-agent.conf).|
| /mnt/user/appdata/kea-primary/logs	| /var/log/kea	| rw | Kea server operational logs.|
| /mnt/user/appdata/kea-primary/lib	| /var/lib/kea	| rw | Active lease database and runtime state.|
| /mnt/user/appdata/kea-primary/alloy	| /etc/alloy	| rw | Grafana Alloy configuration directory (config.alloy).|
| /mnt/user/appdata/kea-primary/webmin	| /etc/webmin	| rw | Persistent Webmin users, credentials, and settings.|

 🔌 Exposed Network Ports
| Port	| Protocol	| Service | Purpose |
| --- | --- | --- | --- |
| 67 / 68 | UDP	| Kea DHCPv4 | DHCP Lease Requests & Discovery |
| 8000 |TCP	| Kea Ctrl Agent | Rest API / Stork Server connection |
| 8080 | TCP | Stork Agent | Stork Agent monitoring endpoint|
| 10000 |TCP |Webmin | Web Administration UI |
| 12345 |TCP |Grafana Alloy | Alloy Telemetry endpoint|

### ⚙️ Environment Variables
| Variable | Example | Value | Description |
| --- | --- | --- | --- |
| STORK_AGENT_HOST | x.x.x.x | IP address assigned to this container. |
| STORK_AGENT_SERVER_URL | http://x.x.x.x:8080 | URL of central Stork Server instance. |
| TZ	| America/New_York | Container timezone setting. |

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
