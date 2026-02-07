# Extension: ccache-remote
# Enables ccache with remote storage for sharing compilation cache across build hosts.
# Supports Redis and HTTP/WebDAV backends (ccache 4.4+).
#
# Documentation:
#   Redis:   https://ccache.dev/howto/redis-storage.html
#   HTTP:    https://ccache.dev/howto/http-storage.html
#   General: https://ccache.dev/manual/4.10.html#config_remote_storage
#
# Usage:
#   # With explicit Redis server:
#   ./compile.sh ENABLE_EXTENSIONS=ccache-remote CCACHE_REMOTE_STORAGE="redis://192.168.1.65:6379" BOARD=...
#
#   # With HTTP/WebDAV server:
#   ./compile.sh ENABLE_EXTENSIONS=ccache-remote CCACHE_REMOTE_STORAGE="http://192.168.1.65:8088/ccache/" BOARD=...
#
#   # Auto-discovery via DNS-SD (no URL needed, discovers type/host/port):
#   ./compile.sh ENABLE_EXTENSIONS=ccache-remote BOARD=...
#
#   # DNS SRV discovery for remote build servers:
#   ./compile.sh ENABLE_EXTENSIONS=ccache-remote CCACHE_REMOTE_DOMAIN="example.com" BOARD=...
#
#   # Disable local cache, use remote only (saves local disk space):
#   ./compile.sh ENABLE_EXTENSIONS=ccache-remote CCACHE_REMOTE_ONLY=yes BOARD=...
#
# Automatically sets USE_CCACHE=yes
#
# Supported ccache environment variables (passed through to builds):
# See: https://ccache.dev/manual/latest.html#_configuration_options
#   CCACHE_BASEDIR        - base directory for path normalization (enables cache sharing)
#   CCACHE_REMOTE_STORAGE - remote storage URL (redis://... or http://...)
#   CCACHE_REMOTE_DOMAIN  - domain for DNS SRV discovery (e.g., "example.com")
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
#   Redis: redis://HOST[:PORT][|attribute=value...]
#   HTTP:  http://HOST[:PORT]/PATH/[|attribute=value...]
#   Common attributes:
#     connect-timeout=N   - connection timeout in milliseconds (default: 100)
#     operation-timeout=N - operation timeout in milliseconds (default: 10000)
#   Examples:
#     "redis://192.168.1.65:6379|connect-timeout=500"
#     "http://192.168.1.65:8088/ccache/"
#
# Auto-discovery (priority order):
#   1. Explicit CCACHE_REMOTE_STORAGE - used as-is, no discovery
#   2. DNS-SD browse for _ccache._tcp on local network (avahi-browse)
#   3. DNS SRV record _ccache._tcp.DOMAIN (when CCACHE_REMOTE_DOMAIN is set)
#   4. Legacy mDNS: resolve 'ccache.local' hostname (fallback)
#
#   When multiple services are found, Redis is preferred over HTTP.
#
#   DNS-SD service publication (on cache server):
#     # For HTTP/WebDAV:
#     avahi-publish-service "ccache-webdav" _ccache._tcp 8088 type=http path=/ccache/
#     # For Redis:
#     avahi-publish-service "ccache-redis" _ccache._tcp 6379 type=redis
#
#   DNS SRV record (for remote/hosted build servers):
#     Set CCACHE_REMOTE_DOMAIN to your domain, then create DNS records:
#       _ccache._tcp.example.com.  SRV  0 0 8088 ccache.example.com.
#       _ccache._tcp.example.com.  TXT  "type=http" "path=/ccache/"
#     The cache server must be reachable from the build host (e.g., via port forwarding).
#
#   Legacy mDNS (backward compatible):
#     Publish 'ccache.local' hostname via Avahi:
#       avahi-publish-address -R ccache.local <SERVER_IP>
#     Or create a systemd service (see below).
#
#   Server setup: see README.server-setup.md and config files in misc/
#     - misc/redis/redis-ccache.conf   — Redis configuration example
#     - misc/nginx/ccache-webdav.conf  — nginx WebDAV configuration example
#     - misc/avahi/ccache-*.service    — Avahi DNS-SD service files (static, always announce)
#     - misc/systemd/ccache-avahi-*.service — systemd units (announce only while service runs)
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
	CCACHE_REMOTE_DOMAIN
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

# Discover ccache remote storage via DNS-SD (mDNS/Avahi) or DNS SRV records.
# Looks for _ccache._tcp services with TXT records: type=http|redis, path=/...
# Prefers Redis over HTTP when multiple services are found.
# Sets CCACHE_REMOTE_STORAGE on success, returns 1 if nothing found.
function ccache_discover_remote_storage() {
	# Method 1: DNS-SD browse on local network (requires avahi-browse)
	if command -v avahi-browse &>/dev/null; then
		local browse_output
		browse_output=$(timeout 5 avahi-browse -rpt _ccache._tcp 2>/dev/null || true)
		if [[ -n "${browse_output}" ]]; then
			# Parse resolved lines: =;IFACE;PROTO;NAME;TYPE;DOMAIN;HOSTNAME;ADDRESS;PORT;"txt"...
			# Prefer IPv4 (proto=IPv4), prefer type=redis over type=http
			local redis_url="" http_url=""
			while IFS=';' read -r status iface proto name stype domain hostname address port txt_rest; do
				[[ "${status}" == "=" && "${proto}" == "IPv4" ]] || continue
				local svc_type="" svc_path=""
				# Parse TXT records from remaining fields
				if [[ "${txt_rest}" =~ \"type=([a-z]+)\" ]]; then
					svc_type="${BASH_REMATCH[1]}"
				fi
				if [[ "${txt_rest}" =~ \"path=([^\"]+)\" ]]; then
					svc_path="${BASH_REMATCH[1]}"
				fi
				if [[ "${svc_type}" == "redis" ]]; then
					redis_url="redis://${address}:${port}|connect-timeout=${CCACHE_REDIS_CONNECT_TIMEOUT}"
				elif [[ "${svc_type}" == "http" ]]; then
					http_url="http://${address}:${port}${svc_path}"
				fi
			done <<< "${browse_output}"
			# Redis preferred over HTTP
			if [[ -n "${redis_url}" ]]; then
				export CCACHE_REMOTE_STORAGE="${redis_url}"
				display_alert "DNS-SD: discovered Redis ccache" "$(ccache_mask_storage_url "${CCACHE_REMOTE_STORAGE}")" "info"
				return 0
			elif [[ -n "${http_url}" ]]; then
				export CCACHE_REMOTE_STORAGE="${http_url}"
				display_alert "DNS-SD: discovered HTTP ccache" "$(ccache_mask_storage_url "${CCACHE_REMOTE_STORAGE}")" "info"
				return 0
			fi
		fi
	fi

	# Method 2: DNS SRV record for remote setups (CCACHE_REMOTE_DOMAIN must be set)
	if [[ -n "${CCACHE_REMOTE_DOMAIN}" ]] && command -v dig &>/dev/null; then
		local srv_output
		srv_output=$(dig +short SRV "_ccache._tcp.${CCACHE_REMOTE_DOMAIN}" 2>/dev/null || true)
		if [[ -n "${srv_output}" ]]; then
			local srv_port srv_host
			# SRV format: priority weight port target
			read -r _ _ srv_port srv_host <<< "${srv_output}"
			srv_host="${srv_host%.}" # strip trailing dot
			if [[ -n "${srv_host}" && -n "${srv_port}" ]]; then
				# Check TXT record for service type and path
				local txt_output svc_type="redis" svc_path=""
				txt_output=$(dig +short TXT "_ccache._tcp.${CCACHE_REMOTE_DOMAIN}" 2>/dev/null || true)
				if [[ "${txt_output}" =~ type=([a-z]+) ]]; then
					svc_type="${BASH_REMATCH[1]}"
				fi
				if [[ "${txt_output}" =~ path=([^\"[:space:]]+) ]]; then
					svc_path="${BASH_REMATCH[1]}"
				fi
				if [[ "${svc_type}" == "http" ]]; then
					export CCACHE_REMOTE_STORAGE="http://${srv_host}:${srv_port}${svc_path}"
				else
					export CCACHE_REMOTE_STORAGE="redis://${srv_host}:${srv_port}|connect-timeout=${CCACHE_REDIS_CONNECT_TIMEOUT}"
				fi
				display_alert "DNS SRV: discovered ccache" "$(ccache_mask_storage_url "${CCACHE_REMOTE_STORAGE}")" "info"
				return 0
			fi
		fi
	fi

	# Method 3: Legacy fallback - resolve ccache.local hostname
	local ccache_ip
	ccache_ip=$(getent hosts ccache.local 2>/dev/null | awk '{print $1; exit}' || true)
	if [[ -n "${ccache_ip}" ]]; then
		export CCACHE_REMOTE_STORAGE="redis://${ccache_ip}:6379|connect-timeout=${CCACHE_REDIS_CONNECT_TIMEOUT}"
		display_alert "mDNS: discovered ccache" "$(ccache_mask_storage_url "${CCACHE_REMOTE_STORAGE}")" "info"
		return 0
	fi

	return 1
}

# Query Redis stats (keys count and memory usage)
function ccache_get_redis_stats() {
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

# Check HTTP/WebDAV storage reachability via HEAD request
function ccache_get_http_stats() {
	local url="$1"
	local stats=""
	local http_code
	http_code=$(timeout 3 curl -s -o /dev/null -w "%{http_code}" -X HEAD "${url}" 2>/dev/null || true)
	if [[ -n "${http_code}" && "${http_code}" != "000" ]]; then
		stats="reachable (HTTP ${http_code})"
	fi
	echo "$stats"
}

# Query remote storage stats based on URL scheme (redis:// or http://)
function ccache_get_remote_stats() {
	local url="$1"
	if [[ "${url}" =~ ^redis://([^:/|]+):?([0-9]*) ]]; then
		ccache_get_redis_stats "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]:-6379}"
	elif [[ "${url}" =~ ^https?:// ]]; then
		# Strip ccache attributes after | for the URL
		ccache_get_http_stats "${url%%|*}"
	fi
}

# Mask credentials in storage URLs to avoid leaking secrets into build logs
# Handles any URI scheme with userinfo component (e.g., redis://user:pass@host)
function ccache_mask_storage_url() {
	local url="$1"
	if [[ "${url}" =~ ^([a-zA-Z][a-zA-Z0-9+.-]*://)([^@/]+)@(.*)$ ]]; then
		echo "${BASH_REMATCH[1]}****@${BASH_REMATCH[3]}"
	else
		echo "${url}"
	fi
}

# This runs on the HOST just before Docker container is launched.
# Resolves 'ccache.local' via mDNS (requires Avahi on server publishing this hostname
# with: avahi-publish-address -R ccache.local <IP>) and passes the resolved IP
# to Docker container via CCACHE_REMOTE_STORAGE environment variable.
# mDNS resolution doesn't work inside Docker, so we must resolve on host.
function host_pre_docker_launch__setup_remote_ccache() {
	if [[ -n "${CCACHE_REMOTE_STORAGE}" ]]; then
		display_alert "Remote ccache pre-configured" "$(ccache_mask_storage_url "${CCACHE_REMOTE_STORAGE}")" "info"
	elif ! ccache_discover_remote_storage; then
		display_alert "Remote ccache not found on host" "no service discovered" "debug"
	fi

	# Show backend stats if we have a remote storage URL
	if [[ -n "${CCACHE_REMOTE_STORAGE}" ]]; then
		local stats
		stats=$(ccache_get_remote_stats "${CCACHE_REMOTE_STORAGE}")
		if [[ -n "$stats" ]]; then
			display_alert "Remote ccache stats" "${stats}" "info"
		fi
	fi

	# Pass all set CCACHE_* variables to Docker
	local var val
	for var in "${CCACHE_PASSTHROUGH_VARS[@]}"; do
		val="${!var}"
		if [[ -n "${val}" ]]; then
			DOCKER_EXTRA_ARGS+=("--env" "${var}=${val}")
			local log_val="${val}"
			[[ "${var}" == "CCACHE_REMOTE_STORAGE" ]] && log_val="$(ccache_mask_storage_url "${val}")"
			display_alert "Docker env" "${var}=${log_val}" "debug"
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
		display_alert "Remote ccache configured" "$(ccache_mask_storage_url "${CCACHE_REMOTE_STORAGE}")" "info"
		return 0
	fi

	# For native (non-Docker) builds, try to discover
	if ccache_discover_remote_storage; then
		return 0
	fi

	if [[ "${CCACHE_REMOTE_ONLY}" == "yes" ]]; then
		display_alert "Remote ccache not available" "CCACHE_REMOTE_ONLY=yes but no remote found, ccache will be ineffective" "wrn"
	else
		display_alert "Remote ccache not available" "using local cache only" "debug"
	fi

	return 0
}

# Inject all set CCACHE_PASSTHROUGH_VARS into the given make environment array
# Uses bash nameref to write into the caller's array variable
function ccache_inject_envs() {
	local -n target_array="$1"
	local label="$2"
	local var val
	for var in "${CCACHE_PASSTHROUGH_VARS[@]}"; do
		val="${!var}"
		if [[ -n "${val}" ]]; then
			target_array+=("${var}=${val@Q}")
			local log_val="${val}"
			[[ "${var}" == "CCACHE_REMOTE_STORAGE" ]] && log_val="$(ccache_mask_storage_url "${val}")"
			display_alert "${label}: ${var}" "${log_val}" "debug"
		fi
	done
}

# This hook runs right before kernel make - add ccache env vars to make environment.
# Required because kernel build uses 'env -i' which clears all environment variables.
function kernel_make_config__add_ccache_remote_storage() {
	ccache_inject_envs common_make_envs "Kernel make"
}

# This hook runs right before u-boot make - add ccache env vars to make environment.
# Required because u-boot build uses 'env -i' which clears all environment variables.
function uboot_make_config__add_ccache_remote_storage() {
	ccache_inject_envs uboot_make_envs "U-boot make"
}
