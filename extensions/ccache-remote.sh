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
# Automatically sets USE_CCACHE=yes
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

# Query Redis stats (keys count and memory usage)
function get_redis_stats() {
	local ip="$1"
	local port="${2:-6379}"
	local stats=""

	if command -v redis-cli &>/dev/null; then
		local keys mem
		keys=$(timeout 2 redis-cli -h "$ip" -p "$port" DBSIZE 2>/dev/null | grep -oE '[0-9]+')
		mem=$(timeout 2 redis-cli -h "$ip" -p "$port" INFO memory 2>/dev/null | grep "used_memory_human" | cut -d: -f2 | tr -d '[:space:]')
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

# This runs on the HOST before Docker is launched.
# Resolves 'ccache.local' via mDNS (requires Avahi on server publishing this hostname
# with: avahi-publish-address -R ccache.local <IP>) and passes the resolved IP
# to Docker container via CCACHE_REMOTE_STORAGE environment variable.
# mDNS resolution doesn't work inside Docker, so we must resolve on host.
function add_host_dependencies__setup_remote_ccache_for_docker() {
	# Skip if already configured explicitly
	if [[ -n "${CCACHE_REMOTE_STORAGE}" ]]; then
		display_alert "Remote ccache pre-configured" "${CCACHE_REMOTE_STORAGE}" "info"
		declare -g -a DOCKER_EXTRA_ARGS+=("--env" "CCACHE_REMOTE_STORAGE=${CCACHE_REMOTE_STORAGE}")
		return 0
	fi

	# Try to resolve ccache.local via mDNS on the host
	local ccache_ip
	ccache_ip=$(getent hosts ccache.local 2>/dev/null | awk '{print $1; exit}')

	if [[ -n "${ccache_ip}" ]]; then
		display_alert "Remote ccache discovered on host" "redis://${ccache_ip}:6379" "info"

		# Show Redis stats
		local stats
		stats=$(get_redis_stats "${ccache_ip}" 6379)
		if [[ -n "$stats" ]]; then
			display_alert "Remote ccache stats" "${stats}" "info"
		fi

		# Pass to Docker via DOCKER_EXTRA_ARGS
		declare -g -a DOCKER_EXTRA_ARGS+=("--env" "CCACHE_REMOTE_STORAGE=redis://${ccache_ip}:6379|connect-timeout=500")
	else
		display_alert "Remote ccache not found on host" "ccache.local not resolvable via mDNS" "debug"
	fi
}

# Show ccache remote storage statistics at the end of build (success or failure)
function ccache_remote_show_final_stats() {
	display_alert "Ccache cleanup handler" "CCACHE_DIR=${CCACHE_DIR:-unset} CCACHE_REMOTE_STORAGE=${CCACHE_REMOTE_STORAGE:-unset}" "debug"
	if [[ -n "${CCACHE_REMOTE_STORAGE}" ]]; then
		local stats_output read_hit read_miss write error total pct
		# Need to explicitly set CCACHE_DIR when reading stats
		stats_output=$(CCACHE_DIR="${CCACHE_DIR}" ccache --print-stats 2>&1)
		display_alert "Ccache raw stats" "$(echo "$stats_output" | grep remote_storage)" "debug"
		# Use remote_storage_read_hit/miss for actual cache operations
		read_hit=$(echo "$stats_output" | grep "^remote_storage_read_hit" | cut -f2)
		read_miss=$(echo "$stats_output" | grep "^remote_storage_read_miss" | cut -f2)
		write=$(echo "$stats_output" | grep "^remote_storage_write" | cut -f2)
		error=$(echo "$stats_output" | grep "^remote_storage_error" | cut -f2)
		total=$((read_hit + read_miss))
		pct=0
		if [[ $total -gt 0 ]]; then
			pct=$((read_hit * 100 / total))
		fi
		display_alert "Remote ccache result" "read_hit=${read_hit:-0} read_miss=${read_miss:-0} write=${write:-0} error=${error:-0} (${pct}% hit rate)" "info"
	else
		display_alert "Ccache cleanup handler" "CCACHE_REMOTE_STORAGE not set" "debug"
	fi
}

# This runs inside Docker (or native build) during configuration
function extension_prepare_config__setup_remote_ccache() {
	# Enable ccache
	declare -g USE_CCACHE=yes

	# Register cleanup handler to show stats at the end of build
	add_cleanup_handler ccache_remote_show_final_stats

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

# This hook runs right before kernel make - add CCACHE_REMOTE_STORAGE to make environment.
# Required because kernel build uses 'env -i' which clears all environment variables.
function kernel_make_config__add_ccache_remote_storage() {
	if [[ -n "${CCACHE_REMOTE_STORAGE}" ]]; then
		common_make_envs+=("CCACHE_REMOTE_STORAGE='${CCACHE_REMOTE_STORAGE}'")
		display_alert "Kernel make: added remote ccache" "${CCACHE_REMOTE_STORAGE}" "debug"
	fi
}

# This hook runs right before u-boot make - add CCACHE_REMOTE_STORAGE to make environment.
# Required because u-boot build uses 'env -i' which clears all environment variables.
function uboot_make_config__add_ccache_remote_storage() {
	if [[ -n "${CCACHE_REMOTE_STORAGE}" ]]; then
		uboot_make_envs+=("CCACHE_REMOTE_STORAGE='${CCACHE_REMOTE_STORAGE}'")
		display_alert "U-boot make: added remote ccache" "${CCACHE_REMOTE_STORAGE}" "debug"
	fi
}
