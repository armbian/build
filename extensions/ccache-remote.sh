# Extension: ccache-remote
# Enables ccache with remote Redis storage for sharing compilation cache across build hosts
#
# Documentation: https://ccache.dev/howto/redis-storage.html
# See also: https://ccache.dev/manual/4.10.html#config_remote_storage
#
# Usage:
#   # With Avahi/mDNS auto-discovery:
#   ./compile.sh ENABLE_EXTENSIONS=ccache-remote BOARD=...
#
#   # With explicit Redis server (no Avahi needed):
#   ./compile.sh ENABLE_EXTENSIONS=ccache-remote CCACHE_REMOTE_STORAGE="redis://192.168.1.65:6379" BOARD=...
#
#   # Disable local cache, use remote only (saves local disk space):
#   ./compile.sh ENABLE_EXTENSIONS=ccache-remote CCACHE_REMOTE_ONLY=yes BOARD=...
#
# Automatically sets USE_CCACHE=yes
#
# Supported ccache environment variables (passed through to builds):
# See: https://ccache.dev/manual/latest.html#_configuration_options
#   CCACHE_BASEDIR        - base directory for path normalization (enables cache sharing)
#   CCACHE_REMOTE_STORAGE - remote storage URL (redis://...)
#   CCACHE_REMOTE_ONLY    - use only remote storage, disable local cache
#   CCACHE_READONLY       - read-only mode, don't update cache
#   CCACHE_RECACHE        - don't use cached results, but update cache
#   CCACHE_RESHARE        - rewrite cache entries to remote storage
#   CCACHE_DISABLE        - disable ccache completely
#   CCACHE_MAXSIZE        - maximum cache size (e.g., "10G")
#   CCACHE_MAXFILES       - maximum number of files in cache
#   CCACHE_NAMESPACE      - cache namespace for isolation
#   CCACHE_SLOPPINESS     - comma-separated list of sloppiness options
#   CCACHE_UMASK          - umask for cache files
#   CCACHE_LOGFILE        - path to log file
#   CCACHE_DEBUGLEVEL     - debug level (1-2)
#   CCACHE_STATSLOG       - path to stats log file
#   CCACHE_PCH_EXTSUM     - include PCH extension in hash
#
# CCACHE_REMOTE_STORAGE format (ccache 4.4+):
#   redis://HOST[:PORT][|attribute=value...]
#   Common attributes:
#     connect-timeout=N   - connection timeout in milliseconds (default: 100)
#     operation-timeout=N - operation timeout in milliseconds (default: 10000)
#   Example: "redis://192.168.1.65:6379|connect-timeout=500"
#
# Avahi/mDNS auto-discovery:
#   This extension tries to resolve 'ccache.local' hostname via mDNS.
#   To publish this hostname on Redis server, run:
#     avahi-publish-address -R ccache.local <SERVER_IP>
#   Or create a systemd service (see below).
#
#   Server setup example:
#     1. Install: apt install redis-server avahi-daemon avahi-utils
#     2. Configure Redis (/etc/redis/redis.conf):
#          bind 0.0.0.0 ::
#          protected-mode no
#          maxmemory 4G
#          maxmemory-policy allkeys-lru
#        WARNING: This configuration is INSECURE - Redis is open without authentication.
#        Use ONLY in a fully trusted private network with no internet access.
#        For secure setup (password, TLS, ACL), see: https://redis.io/docs/management/security/
#     3. Publish hostname (replace IP_ADDRESS with actual IP):
#          avahi-publish-address -R ccache.local IP_ADDRESS
#        Or as systemd service /etc/systemd/system/ccache-hostname.service:
#          [Unit]
#          Description=Publish ccache.local hostname via Avahi
#          After=avahi-daemon.service redis-server.service
#          BindsTo=redis-server.service
#          [Service]
#          Type=simple
#          ExecStart=/usr/bin/avahi-publish-address -R ccache.local IP_ADDRESS
#          Restart=on-failure
#          [Install]
#          WantedBy=redis-server.service
#
#   Client requirements for mDNS resolution (one of):
#     - libnss-resolve (systemd-resolved NSS module):
#         apt install libnss-resolve
#         /etc/nsswitch.conf: hosts: files resolve [!UNAVAIL=return] dns myhostname
#     - libnss-mdns (standalone mDNS NSS module):
#         apt install libnss-mdns
#         /etc/nsswitch.conf: hosts: files mdns4_minimal [NOTFOUND=return] dns myhostname
#
# Fallback behavior:
#   If CCACHE_REMOTE_STORAGE is not set and ccache.local is not resolvable,
#   extension silently falls back to local ccache only.
#
# Cache sharing requirements:
#   For cache to be shared across multiple build hosts, the Armbian project
#   path must be identical on all machines (e.g., /home/build/armbian).
#   This is because ccache includes the working directory in the cache key.
#   Docker builds automatically use consistent paths (/armbian/...).

# Default Redis connection timeout in milliseconds (can be overridden by user)
# Note: Must be set before extension loads (e.g., via environment or command line)
declare -g -r CCACHE_REDIS_CONNECT_TIMEOUT="${CCACHE_REDIS_CONNECT_TIMEOUT:-500}"

# List of ccache environment variables to pass through to builds
declare -g -a CCACHE_PASSTHROUGH_VARS=(
	CCACHE_REDIS_CONNECT_TIMEOUT
	CCACHE_BASEDIR
	CCACHE_REMOTE_STORAGE
	CCACHE_REMOTE_ONLY
	CCACHE_READONLY
	CCACHE_RECACHE
	CCACHE_RESHARE
	CCACHE_DISABLE
	CCACHE_MAXSIZE
	CCACHE_MAXFILES
	CCACHE_NAMESPACE
	CCACHE_SLOPPINESS
	CCACHE_UMASK
	CCACHE_LOGFILE
	CCACHE_DEBUGLEVEL
	CCACHE_STATSLOG
	CCACHE_PCH_EXTSUM
)

# Query Redis stats (keys count and memory usage)
function get_redis_stats() {
	local ip="$1"
	local port="${2:-6379}"
	local stats=""

	if command -v redis-cli &>/dev/null; then
		local keys mem
		keys=$(timeout 2 redis-cli -h "$ip" -p "$port" DBSIZE 2>/dev/null | grep -oE '[0-9]+' || true)
		mem=$(timeout 2 redis-cli -h "$ip" -p "$port" INFO memory 2>/dev/null | grep "used_memory_human" | cut -d: -f2 | tr -d '[:space:]' || true)
		if [[ -n "$keys" ]]; then
			stats="keys=${keys:-0}, mem=${mem:-?}"
		fi
	else
		# Fallback: try netcat for basic connectivity check
		if nc -z -w 2 "$ip" "$port" 2>/dev/null; then
			stats="reachable (redis-cli not installed for detailed stats)"
		fi
	fi
	echo "$stats"
}

# This runs on the HOST just before Docker container is launched.
# Resolves 'ccache.local' via mDNS (requires Avahi on server publishing this hostname
# with: avahi-publish-address -R ccache.local <IP>) and passes the resolved IP
# to Docker container via CCACHE_REMOTE_STORAGE environment variable.
# mDNS resolution doesn't work inside Docker, so we must resolve on host.
function host_pre_docker_launch__setup_remote_ccache() {
	# If CCACHE_REMOTE_STORAGE not set, try to resolve ccache.local via mDNS
	if [[ -z "${CCACHE_REMOTE_STORAGE}" ]]; then
		local ccache_ip
		ccache_ip=$(getent hosts ccache.local 2>/dev/null | awk '{print $1; exit}' || true)

		if [[ -n "${ccache_ip}" ]]; then
			display_alert "Remote ccache discovered on host" "redis://${ccache_ip}:6379" "info"

			# Show Redis stats
			local stats
			stats=$(get_redis_stats "${ccache_ip}" 6379)
			if [[ -n "$stats" ]]; then
				display_alert "Remote ccache stats" "${stats}" "info"
			fi

			export CCACHE_REMOTE_STORAGE="redis://${ccache_ip}:6379|connect-timeout=${CCACHE_REDIS_CONNECT_TIMEOUT}"
		else
			display_alert "Remote ccache not found on host" "ccache.local not resolvable via mDNS" "debug"
		fi
	else
		display_alert "Remote ccache pre-configured" "${CCACHE_REMOTE_STORAGE}" "info"
	fi

	# Pass all set CCACHE_* variables to Docker
	local var val
	for var in "${CCACHE_PASSTHROUGH_VARS[@]}"; do
		val="${!var}"
		if [[ -n "${val}" ]]; then
			DOCKER_EXTRA_ARGS+=("--env" "${var}=${val}")
			display_alert "Docker env" "${var}=${val}" "debug"
		fi
	done
}

# Hook: Show ccache remote storage statistics after each compilation (kernel, uboot)
function ccache_post_compilation__show_remote_stats() {
	if [[ -n "${CCACHE_REMOTE_STORAGE}" ]]; then
		local stats_output pct
		local read_hit read_miss write error
		stats_output=$(ccache --print-stats 2>&1 || true)
		read_hit=$(ccache_get_stat "$stats_output" "remote_storage_read_hit")
		read_miss=$(ccache_get_stat "$stats_output" "remote_storage_read_miss")
		write=$(ccache_get_stat "$stats_output" "remote_storage_write")
		error=$(ccache_get_stat "$stats_output" "remote_storage_error")
		pct=$(ccache_hit_pct "$read_hit" "$read_miss")
		display_alert "Remote ccache result" "hit=${read_hit} miss=${read_miss} write=${write} err=${error} (${pct}%)" "info"
	fi
}

# This runs inside Docker (or native build) during configuration
function extension_prepare_config__setup_remote_ccache() {
	# Enable ccache
	declare -g USE_CCACHE=yes

	# If CCACHE_REMOTE_STORAGE was passed from host (via Docker env), it's already set
	if [[ -n "${CCACHE_REMOTE_STORAGE}" ]]; then
		display_alert "Remote ccache configured" "$(mask_storage_url "${CCACHE_REMOTE_STORAGE}")" "info"
		return 0
	fi

	# For native (non-Docker) builds, try to resolve here
	local ccache_ip
	ccache_ip=$(getent hosts ccache.local 2>/dev/null | awk '{print $1; exit}')

	if [[ -n "${ccache_ip}" ]]; then
		export CCACHE_REMOTE_STORAGE="redis://${ccache_ip}:6379|connect-timeout=${CCACHE_REDIS_CONNECT_TIMEOUT}"
		display_alert "Remote ccache discovered" "$(mask_storage_url "${CCACHE_REMOTE_STORAGE}")" "info"
	else
		if [[ "${CCACHE_REMOTE_ONLY}" == "yes" ]]; then
			display_alert "Remote ccache not available" "CCACHE_REMOTE_ONLY=yes but no remote found, ccache will be ineffective" "wrn"
		else
			display_alert "Remote ccache not available" "using local cache only" "debug"
		fi
	fi

	return 0
}

# This hook runs right before kernel make - add ccache env vars to make environment.
# Required because kernel build uses 'env -i' which clears all environment variables.
function kernel_make_config__add_ccache_remote_storage() {
	local var val
	for var in "${CCACHE_PASSTHROUGH_VARS[@]}"; do
		val="${!var}"
		if [[ -n "${val}" ]]; then
			common_make_envs+=("${var}=${val@Q}")
			display_alert "Kernel make: ${var}" "${val}" "debug"
		fi
	done
}

# This hook runs right before u-boot make - add ccache env vars to make environment.
# Required because u-boot build uses 'env -i' which clears all environment variables.
function uboot_make_config__add_ccache_remote_storage() {
	local var val
	for var in "${CCACHE_PASSTHROUGH_VARS[@]}"; do
		val="${!var}"
		if [[ -n "${val}" ]]; then
			uboot_make_envs+=("${var}=${val@Q}")
			display_alert "U-boot make: ${var}" "${val}" "debug"
		fi
	done
}
