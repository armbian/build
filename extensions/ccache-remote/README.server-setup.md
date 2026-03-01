# ccache-remote: Server Setup Guide

## Redis Server

1. Install packages:
   ```bash
   apt install redis-server avahi-daemon avahi-utils
   ```

2. Configure Redis — merge the settings from `misc/redis/redis-ccache.conf` into
   `/etc/redis/redis.conf`, or add an `include` directive at the end of your
   existing config (`include /etc/redis/redis-ccache.conf`), then restart:
   ```bash
   sudo systemctl restart redis-server
   ```

   **Authentication (recommended).** Set a password in the config file — either via
   `requirepass` (Redis < 6) or ACL user entry (Redis 6+). See comments in
   `misc/redis/redis-ccache.conf` for both methods. Generate a URL-safe password:
   ```bash
   openssl rand -hex 24
   ```
   **Important:** Do not use `openssl rand -base64` — base64 passwords contain
   `/`, `+`, and `=` which break URL parsing in `redis://` connection strings.
   On the build host, pass the password in the Redis URL:
   ```bash
   ./compile.sh ENABLE_EXTENSIONS=ccache-remote \
     CCACHE_REMOTE_STORAGE="redis://default:YOUR_PASSWORD@192.168.1.65:6379" BOARD=...
   ```

   **No authentication (trusted network only).** If all machines are on a fully
   isolated private network and access control is not needed, remove `requirepass`,
   set `nopass` in the ACL user entry, and set `protected-mode no`. See comments
   in `misc/redis/redis-ccache.conf`. No password is needed in the URL:
   ```bash
   ./compile.sh ENABLE_EXTENSIONS=ccache-remote \
     CCACHE_REMOTE_STORAGE="redis://192.168.1.65:6379" BOARD=...
   ```

   For advanced security (TLS, ACL, rename-command), see:
   https://redis.io/docs/latest/operate/oss_and_stack/management/security/

3. Publish DNS-SD service — copy `misc/avahi/ccache-redis.service` to `/etc/avahi/services/`:
   ```bash
   cp misc/avahi/ccache-redis.service /etc/avahi/services/
   ```
   Avahi will pick it up automatically. Clients running `avahi-browse -rpt _ccache._tcp`
   will discover the Redis service.

   Or use a systemd unit that ties the announcement to `redis-server` lifetime
   (stops advertising when Redis is down):
   ```bash
   cp misc/systemd/ccache-avahi-redis.service /etc/systemd/system/
   systemctl enable --now ccache-avahi-redis
   ```

   Alternatively, publish legacy mDNS hostname:
   ```bash
   avahi-publish-address -R ccache.local <SERVER_IP>
   ```
   Or as a systemd service (`/etc/systemd/system/ccache-hostname.service`):
   ```ini
   [Unit]
   Description=Publish ccache.local hostname via Avahi
   After=avahi-daemon.service redis-server.service
   BindsTo=redis-server.service
   [Service]
   Type=simple
   ExecStart=/usr/bin/avahi-publish-address -R ccache.local <SERVER_IP>
   Restart=on-failure
   [Install]
   WantedBy=redis-server.service
   ```

## HTTP/WebDAV Server (nginx)

1. Install nginx with WebDAV support:
   ```bash
   apt install nginx-extras avahi-daemon avahi-utils
   ```

2. Copy `misc/nginx/ccache-webdav.conf` to `/etc/nginx/sites-available/ccache-webdav`,
   then enable and prepare storage:
   ```bash
   cp misc/nginx/ccache-webdav.conf /etc/nginx/sites-available/ccache-webdav
   ln -s /etc/nginx/sites-available/ccache-webdav /etc/nginx/sites-enabled/
   mkdir -p /var/cache/ccache-webdav/ccache
   chown -R www-data:www-data /var/cache/ccache-webdav
   systemctl reload nginx
   ```

3. Verify:
   ```bash
   curl -X PUT -d "test" http://localhost:8088/ccache/test.txt
   curl http://localhost:8088/ccache/test.txt
   ```

   **WARNING:** No authentication configured.
   Use ONLY in a fully trusted private network.

4. Publish DNS-SD service — copy `misc/avahi/ccache-webdav.service` to `/etc/avahi/services/`:
   ```bash
   cp misc/avahi/ccache-webdav.service /etc/avahi/services/
   ```

   Or use a systemd unit that ties the announcement to `nginx` lifetime:
   ```bash
   cp misc/systemd/ccache-avahi-webdav.service /etc/systemd/system/
   systemctl enable --now ccache-avahi-webdav
   ```

## DNS SRV Records (for remote/hosted servers)

Set `CCACHE_REMOTE_DOMAIN` on the client, then create DNS records.

Redis backend:
```text
_ccache._tcp.example.com.  SRV  0 0 6379 ccache.example.com.
_ccache._tcp.example.com.  TXT  "type=redis"
```

HTTP/WebDAV backend:
```text
_ccache._tcp.example.com.  SRV  0 0 8088 ccache.example.com.
_ccache._tcp.example.com.  TXT  "type=http" "path=/ccache/"
```

## Client Requirements for mDNS

Install one of the following for `.local` hostname resolution:

- **libnss-resolve** (systemd-resolved):
  ```bash
  apt install libnss-resolve
  ```
  `/etc/nsswitch.conf`: `hosts: files resolve [!UNAVAIL=return] dns myhostname`

- **libnss-mdns** (standalone):
  ```bash
  apt install libnss-mdns
  ```
  `/etc/nsswitch.conf`: `hosts: files mdns4_minimal [NOTFOUND=return] dns myhostname`
