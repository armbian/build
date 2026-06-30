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
#   Redis: redis://[[USERNAME:]PASSWORD@]HOST[:PORT][|attribute=value...]
#   HTTP:  http://HOST[:PORT]/PATH/[|attribute=value...]
#   Common attributes:
#     connect-timeout=N   - connection timeout in milliseconds (default: 100)
#     operation-timeout=N - operation timeout in milliseconds (default: 10000)
#   Examples:
#     "redis://default:secretpass@192.168.1.65:6379|connect-timeout=500"
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
#     # For Redis (no auth):
#     avahi-publish-service "ccache-redis" _ccache._tcp 6379 type=redis
#     # For Redis with shared-secret password (sniffable on LAN — only useful
#     # as defense against accidental cross-machine writes, not as
#     # confidentiality on a hostile LAN):
#     avahi-publish-service "ccache-redis" _ccache._tcp 6666 type=redis password=<secret>
#
#   DNS SRV record (for remote/hosted build servers):
#     Set CCACHE_REMOTE_DOMAIN to your domain, then create DNS records:
#       _ccache._tcp.example.com.  SRV  0 0 8088 ccache.example.com.
#       _ccache._tcp.example.com.  TXT  "type=http" "path=/ccache/"
#       # or for redis with auth:
#       _ccache._tcp.example.com.  TXT  "type=redis" "password=<secret>"
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

# Format host:port, wrapping IPv6 addresses in brackets for URL compatibility (RFC 2732)
function ccache_format_host_port() {
	local host="$1" port="$2"
	if [[ "${host}" == *:* ]]; then
		echo "[${host}]:${port}"
	else
		echo "${host}:${port}"
	fi
}

# Extract hostname from CCACHE_REMOTE_STORAGE URL (strips scheme, userinfo, port, path)
function ccache_extract_url_host() {
	local url="$1"
	local after_scheme="${url#*://}"
	# Strip userinfo if present
	if [[ "${after_scheme}" == *@* ]]; then
		after_scheme="${after_scheme##*@}"
	fi
	local host
	# Handle bracketed IPv6: [addr]:port
	if [[ "${after_scheme}" == \[* ]]; then
		host="${after_scheme#\[}"
		host="${host%%\]*}"
	else
		# Strip port, path, and ccache attributes
		host="${after_scheme%%[:\/|]*}"
	fi
	echo "${host}"
}

# Discover ccache remote storage via DNS-SD (mDNS/Avahi) or DNS SRV records.
# Looks for _ccache._tcp services with TXT records: type=http|redis, path=/...
# Prefers Redis over HTTP when multiple services are found.
# Sets CCACHE_REMOTE_STORAGE on success, returns 1 if nothing found.
function ccache_discover_remote_storage() {
	# Method 1: DNS-SD browse on local network (requires avahi-browse)
	if command -v avahi-browse &> /dev/null; then
		local browse_output
		browse_output=$(timeout 5 avahi-browse -rpt _ccache._tcp 2> /dev/null || true)
		if [[ -n "${browse_output}" ]]; then
			# Parse resolved lines: =;IFACE;PROTO;NAME;TYPE;DOMAIN;HOSTNAME;ADDRESS;PORT;"txt"...
			# Prefer IPv4 (proto=IPv4), prefer type=redis over type=http
			local redis_url="" http_url=""
			local redis_host="" redis_host_ip="" http_host="" http_host_ip=""
			while IFS=';' read -r status iface proto name stype domain hostname address port txt_rest; do
				[[ "${status}" == "=" && "${proto}" == "IPv4" ]] || continue
				local svc_type="" svc_path="" svc_password=""
				# Parse TXT records from remaining fields
				if [[ "${txt_rest}" =~ \"type=([a-z]+)\" ]]; then
					svc_type="${BASH_REMATCH[1]}"
				fi
				if [[ "${txt_rest}" =~ \"path=([^\"]+)\" ]]; then
					svc_path="${BASH_REMATCH[1]}"
				fi
				# Optional auth TXT for redis-protocol backends. Spec:
				#   redis://[[USERNAME:]PASSWORD@]HOST[:PORT][|attribute=value...]
				# Password sniffable on the LAN — only useful as shared-secret
				# against accidental cross-machine writes, not as defense in depth.
				if [[ "${txt_rest}" =~ \"password=([^\"]+)\" ]]; then
					svc_password="${BASH_REMATCH[1]}"
				fi
				# Use hostname for URL (Docker --add-host resolves it), fall back to address
				local svc_host="${hostname%.local}"
				svc_host="${svc_host%.}"
				[[ -z "${svc_host}" ]] && svc_host="${address}"
				# Validate password (if any) once — the RFC 3986 unreserved-char
				# whitelist applies equally to redis URL `PWD@host` userinfo and
				# http URL `:PWD@host` Basic-auth userinfo. Any URL gen/sub-delim
				# (`@ # ? / : =`), the ccache attribute separator `|`, or the
				# percent-encoding marker `%` would break URL parsing. The
				# announce TXT carries the password verbatim, so the publisher's
				# generator must produce a URL-safe value (e.g. `openssl rand -hex 16`).
				#
				# Note on the redis form: plain `PWD@host` userinfo (no leading
				# colon, no `username:` prefix) is what ccache 4.9 needs — it
				# sends 1-arg legacy `AUTH <pwd>`. The Redis-6 ACL form
				# `redis://:PWD@host` parses but silently never sends AUTH; the
				# `redis://default:PWD@host` form sends 2-arg `AUTH default PWD`
				# which KvRocks <= 2.15.0 rejects with `ERR wrong number of
				# arguments`.
				if [[ -n "${svc_password}" && ! "${svc_password}" =~ ^[A-Za-z0-9._~-]+$ ]]; then
					display_alert "DNS-SD: announce with URL-unsafe password — skipping" \
						"${svc_host}:${port} (password must match [A-Za-z0-9._~-]+)" "wrn"
					continue
				fi
				if [[ "${svc_type}" == "redis" ]]; then
					if [[ -n "${svc_password}" ]]; then
						redis_url="redis://${svc_password}@${svc_host}:${port}|connect-timeout=${CCACHE_REDIS_CONNECT_TIMEOUT}"
					else
						redis_url="redis://${svc_host}:${port}|connect-timeout=${CCACHE_REDIS_CONNECT_TIMEOUT}"
					fi
					redis_host="${svc_host}"
					redis_host_ip="${address}"
				elif [[ "${svc_type}" == "http" ]]; then
					if [[ -n "${svc_password}" ]]; then
						http_url="http://:${svc_password}@${svc_host}:${port}${svc_path}"
					else
						http_url="http://${svc_host}:${port}${svc_path}"
					fi
					http_host="${svc_host}"
					http_host_ip="${address}"
				fi
			done <<< "${browse_output}"
			# Redis preferred over HTTP; set hostname->IP mapping for Docker --add-host
			if [[ -n "${redis_url}" ]]; then
				export CCACHE_REMOTE_STORAGE="${redis_url}"
				declare -g CCACHE_REMOTE_HOST="${redis_host}"
				declare -g CCACHE_REMOTE_HOST_IP="${redis_host_ip}"
				display_alert "DNS-SD: discovered Redis ccache" "$(ccache_mask_storage_url "${CCACHE_REMOTE_STORAGE}")" "info"
				return 0
			elif [[ -n "${http_url}" ]]; then
				export CCACHE_REMOTE_STORAGE="${http_url}"
				declare -g CCACHE_REMOTE_HOST="${http_host}"
				declare -g CCACHE_REMOTE_HOST_IP="${http_host_ip}"
				display_alert "DNS-SD: discovered HTTP ccache" "$(ccache_mask_storage_url "${CCACHE_REMOTE_STORAGE}")" "info"
				return 0
			fi
		fi
	fi

	# Method 2: DNS SRV record for remote setups (CCACHE_REMOTE_DOMAIN must be set)
	if [[ -n "${CCACHE_REMOTE_DOMAIN}" ]] && command -v dig &> /dev/null; then
		local srv_output
		srv_output=$(dig +short SRV "_ccache._tcp.${CCACHE_REMOTE_DOMAIN}" 2> /dev/null || true)
		if [[ -n "${srv_output}" ]]; then
			local srv_port srv_host
			# SRV format: priority weight port target
			read -r _ _ srv_port srv_host <<< "${srv_output}"
			srv_host="${srv_host%.}" # strip trailing dot
			if [[ -n "${srv_host}" && -n "${srv_port}" ]]; then
				# Check TXT record for service type, path, and optional password.
				local txt_output svc_type="redis" svc_path="" svc_password=""
				txt_output=$(dig +short TXT "_ccache._tcp.${CCACHE_REMOTE_DOMAIN}" 2> /dev/null || true)
				if [[ "${txt_output}" =~ type=([a-z]+) ]]; then
					svc_type="${BASH_REMATCH[1]}"
				fi
				if [[ "${txt_output}" =~ path=([^\"[:space:]]+) ]]; then
					svc_path="${BASH_REMATCH[1]}"
				fi
				if [[ "${txt_output}" =~ password=([^\"[:space:]]+) ]]; then
					svc_password="${BASH_REMATCH[1]}"
				fi
				# Validate password (if any) against the RFC 3986 unreserved-char
				# whitelist — same gate applies to both redis URL `PWD@host`
				# userinfo and http URL `:PWD@host` Basic-auth userinfo. On
				# failure, fall through to Method 3 (ccache.local) instead of
				# aborting the whole function so legacy mDNS discovery still
				# gets a chance.
				if [[ -n "${svc_password}" && ! "${svc_password}" =~ ^[A-Za-z0-9._~-]+$ ]]; then
					display_alert "DNS SRV: URL-unsafe password — skipping" \
						"_ccache._tcp.${CCACHE_REMOTE_DOMAIN} (password must match [A-Za-z0-9._~-]+)" "wrn"
				else
					local host_port
					host_port=$(ccache_format_host_port "${srv_host}" "${srv_port}")
					if [[ "${svc_type}" == "http" ]]; then
						if [[ -n "${svc_password}" ]]; then
							export CCACHE_REMOTE_STORAGE="http://:${svc_password}@${host_port}${svc_path}"
						else
							export CCACHE_REMOTE_STORAGE="http://${host_port}${svc_path}"
						fi
					elif [[ -n "${svc_password}" ]]; then
						export CCACHE_REMOTE_STORAGE="redis://${svc_password}@${host_port}|connect-timeout=${CCACHE_REDIS_CONNECT_TIMEOUT}"
					else
						export CCACHE_REMOTE_STORAGE="redis://${host_port}|connect-timeout=${CCACHE_REDIS_CONNECT_TIMEOUT}"
					fi
					display_alert "DNS SRV: discovered ccache" "$(ccache_mask_storage_url "${CCACHE_REMOTE_STORAGE}")" "info"
					return 0
				fi
			fi
		fi
	fi

	# Method 3: Legacy fallback - resolve ccache.local hostname
	local ccache_ip
	ccache_ip=$(getent hosts ccache.local 2> /dev/null | awk '{print $1; exit}' || true)
	if [[ -n "${ccache_ip}" ]]; then
		local host_port
		host_port=$(ccache_format_host_port "${ccache_ip}" "6379")
		export CCACHE_REMOTE_STORAGE="redis://${host_port}|connect-timeout=${CCACHE_REDIS_CONNECT_TIMEOUT}"
		display_alert "mDNS: discovered ccache" "$(ccache_mask_storage_url "${CCACHE_REMOTE_STORAGE}")" "info"
		return 0
	fi

	return 1
}

# Query Redis stats (keys count and memory usage)
function ccache_get_redis_stats() {
	local ip="$1"
	local port="${2:-6379}"
	local password="$3"
	local stats=""

	if command -v redis-cli &> /dev/null; then
		local auth_args=()
		[[ -n "${password}" ]] && auth_args+=(-a "${password}" --no-auth-warning)
		local keys mem
		keys=$(timeout 2 redis-cli -h "$ip" -p "$port" "${auth_args[@]}" DBSIZE 2> /dev/null | grep -oE '[0-9]+' || true)
		mem=$(timeout 2 redis-cli -h "$ip" -p "$port" "${auth_args[@]}" INFO memory 2> /dev/null | grep "used_memory_human" | cut -d: -f2 | tr -d '[:space:]' || true)
		if [[ -n "$keys" ]]; then
			stats="keys=${keys:-0}, mem=${mem:-?}"
		fi
	else
		# Fallback: try netcat for basic connectivity check
		if nc -z -w 2 "$ip" "$port" 2> /dev/null; then
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
	http_code=$(timeout 3 curl -s -o /dev/null -w "%{http_code}" -X HEAD "${url}" 2> /dev/null || true)
	if [[ -n "${http_code}" && "${http_code}" != "000" ]]; then
		stats="reachable (HTTP ${http_code})"
	fi
	echo "$stats"
}

# Query remote storage stats based on URL scheme (redis:// or http://)
# Parses userinfo (user:pass@) from Redis URLs to pass credentials to redis-cli
function ccache_get_remote_stats() {
	local url="$1"
	if [[ "${url}" =~ ^redis:// ]]; then
		local password="" host="" port="6379"
		# Strip scheme and attributes
		local authority="${url#redis://}"
		authority="${authority%%|*}"
		# Extract password from userinfo (before last @)
		if [[ "${authority}" =~ ^(.+)@(.+)$ ]]; then
			local userinfo="${BASH_REMATCH[1]}"
			authority="${BASH_REMATCH[2]}"
			# Accept both user:pass / :pass (Redis-6 ACL form) and bare pass
			# (legacy form discovery emits — see ccache_discover_remote_storage).
			if [[ "${userinfo}" == *:* ]]; then
				password="${userinfo#*:}"
			else
				password="${userinfo}"
			fi
		fi
		# Parse host:port (IPv6 in brackets or plain)
		if [[ "${authority}" =~ ^\[([^]]+)\]:?([0-9]*) ]]; then
			host="${BASH_REMATCH[1]}"
			[[ -n "${BASH_REMATCH[2]}" ]] && port="${BASH_REMATCH[2]}"
		elif [[ "${authority}" =~ ^([^:]+):?([0-9]*) ]]; then
			host="${BASH_REMATCH[1]}"
			[[ -n "${BASH_REMATCH[2]}" ]] && port="${BASH_REMATCH[2]}"
		fi
		[[ -n "${host}" ]] && ccache_get_redis_stats "${host}" "${port}" "${password}"
	elif [[ "${url}" =~ ^https?:// ]]; then
		# Strip ccache attributes after | for the URL
		ccache_get_http_stats "${url%%|*}"
	fi
}

# Mask credentials in storage URLs to avoid leaking secrets into build logs
# Handles any URI scheme with userinfo component (e.g., redis://user:pass@host)
# Uses last @ as delimiter since userinfo may contain special characters
function ccache_mask_storage_url() {
	local url="$1"
	if [[ "${url}" =~ ^([a-zA-Z][a-zA-Z0-9+.-]*://)(.+)@([^@]+)$ ]]; then
		echo "${BASH_REMATCH[1]}****@${BASH_REMATCH[3]}"
	else
		echo "${url}"
	fi
}

# Validate that credentials in storage URL do not contain characters unsafe for URL parsing.
# Passwords with / + = or spaces break URL parsing in ccache and in our mask function.
# Returns 1 and displays error if invalid characters are found.
function ccache_validate_storage_url() {
	local url="$1"
	# Extract userinfo (part between :// and last @)
	if [[ "${url}" =~ ^[a-zA-Z][a-zA-Z0-9+.-]*://(.+)@[^@]+$ ]]; then
		local userinfo="${BASH_REMATCH[1]}"
		if [[ "${userinfo}" =~ [/+=[:space:]] ]]; then
			display_alert "Password contains URL-unsafe characters (/ + = or spaces)" \
				"Generate a safe password: openssl rand -hex 24" "err"
			return 1
		fi
	fi
	return 0
}

# This runs on the HOST just before Docker container is launched.
# Resolves 'ccache.local' via mDNS (requires Avahi on server publishing this hostname
# Docker hook: resolve hostnames and handle loopback for container access.
# mDNS/local DNS may not work inside Docker, so we resolve on host and
# pass the mapping via --add-host. Loopback addresses are rewritten to
# host.docker.internal.
function host_pre_docker_launch__setup_remote_ccache() {
	if [[ -n "${CCACHE_REMOTE_STORAGE}" ]]; then
		ccache_validate_storage_url "${CCACHE_REMOTE_STORAGE}" || return 1
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

	# Ensure hostname in CCACHE_REMOTE_STORAGE is resolvable inside Docker.
	# Docker containers may not have access to host mDNS/local DNS.
	if [[ -n "${CCACHE_REMOTE_STORAGE}" ]]; then
		local _host
		_host=$(ccache_extract_url_host "${CCACHE_REMOTE_STORAGE}")
		if [[ -n "${_host}" ]]; then
			# Loopback addresses: rewrite to host.docker.internal
			if [[ "${_host}" == "localhost" || "${_host}" == "127.0.0.1" || "${_host}" == "::1" ]]; then
				CCACHE_REMOTE_STORAGE="${CCACHE_REMOTE_STORAGE//localhost/host.docker.internal}"
				CCACHE_REMOTE_STORAGE="${CCACHE_REMOTE_STORAGE//127.0.0.1/host.docker.internal}"
				CCACHE_REMOTE_STORAGE="${CCACHE_REMOTE_STORAGE//\[::1\]/host.docker.internal}"
				DOCKER_EXTRA_ARGS+=("--add-host=host.docker.internal:host-gateway")
				display_alert "Rewriting loopback URL for Docker" "$(ccache_mask_storage_url "${CCACHE_REMOTE_STORAGE}")" "info"
			# Hostname (not IP): resolve on host and pass via --add-host
			elif [[ "${_host}" =~ [a-zA-Z] ]]; then
				local _resolved_ip="${CCACHE_REMOTE_HOST_IP:-}"
				# If not from discovery, resolve now; prefer IPv4 (Docker bridge often lacks IPv6)
				if [[ -z "${_resolved_ip}" || "${CCACHE_REMOTE_HOST}" != "${_host}" ]]; then
					_resolved_ip=$(getent ahostsv4 "${_host}" 2> /dev/null | awk '{print $1; exit}' || true)
					[[ -z "${_resolved_ip}" ]] && _resolved_ip=$(getent hosts "${_host}" 2> /dev/null | awk '{print $1; exit}' || true)
				fi
				if [[ -n "${_resolved_ip}" ]]; then
					# Hostname resolves to loopback on host — service runs locally, use host-gateway for Docker
					if [[ "${_resolved_ip}" == "127."* || "${_resolved_ip}" == "::1" ]]; then
						DOCKER_EXTRA_ARGS+=("--add-host=${_host}:host-gateway")
						display_alert "Docker --add-host (loopback→host-gateway)" "${_host}:${_resolved_ip} → host-gateway" "debug"
					else
						DOCKER_EXTRA_ARGS+=("--add-host=${_host}:${_resolved_ip}")
						display_alert "Docker --add-host" "${_host}:${_resolved_ip}" "debug"
					fi
				else
					display_alert "Cannot resolve hostname for Docker" "${_host}" "wrn"
				fi
			fi
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
	# Enable ccache with a consistent cache directory ($SRC/cache/ccache).
	# PRIVATE_CCACHE ensures the same CCACHE_DIR is used in native and Docker builds,
	# avoiding fragmented caches in /root/.cache/ccache vs $SRC/cache/ccache.
	declare -g USE_CCACHE=yes
	declare -g PRIVATE_CCACHE=yes

	# If CCACHE_REMOTE_STORAGE was passed from host (via Docker env), it's already set
	if [[ -n "${CCACHE_REMOTE_STORAGE}" ]]; then
		ccache_validate_storage_url "${CCACHE_REMOTE_STORAGE}" || return 1
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
