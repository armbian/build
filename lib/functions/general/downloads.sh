#!/usr/bin/env bash
function get_urls() {
	local catalog=$1
	local filename=$2

	display_alert "Looking up continent code for mirrors" "geoip" "debug"
	local continent_code
	continent_code=$(curl --silent --fail https://cache.armbian.com/geoip | jq '.continent.code' -r)
	display_alert "Found continent code for mirrors" "${continent_code}" "info"

	declare -a urls=()

	# this uses `jq` hostdep
	case $catalog in
		toolchain)
			# urls+=("https://dl.armbian.com/_toolchain/${filename}") # @TODO: rpardini: this was commented out when I found it
			# shellcheck disable=SC2207 # yep old code, I know, gotta expand here
			urls+=($(
				curl --silent --fail "https://dl.armbian.com/mirrors" |
					jq -r "(${continent_code:+.${continent_code} // } .default) | .[]" |
					sed "s#\$#/_toolchain/${filename}#"
			))
			;;

		rootfs)
			# urls+=("https://cache.armbian.com/rootfs/${ROOTFSCACHE_VERSION}/${filename}") # @TODO: rpardini: this was commented out when I found it
			urls+=("https://github.com/armbian/cache/releases/download/${ROOTFSCACHE_VERSION}/${filename}")
			urls+=(
				$(
					curl --silent --fail "https://cache.armbian.com/mirrors" |
						jq -r "(${continent_code:+.${continent_code} // } .default) | .[]" |
						sed "s#\$#/rootfs/${ROOTFSCACHE_VERSION}/${filename}#"
				)
			)
			;;

		*)
			exit_with_error "Unknown catalog '${catalog}'"
			return 1
			;;
	esac

	declare number_urls=${#urls[@]}
	display_alert "Found ${number_urls} URLs for catalog" "${catalog}: ${urls[*]}" "info"

	echo "${urls[@]}"
	unset urls
	return 0
}

# Terrible idea, this runs download_and_verify_internal() with error handling disabled.
function download_and_verify() {
	display_alert "Using download_and_verify(), which" "is not correctly handled for armbian-next; expect problems" "warn"
	download_and_verify_internal "${@}" || true
}

function download_and_verify_internal() {

	local catalog=$1
	local filename=$2
	local localdir=$SRC/cache/$catalog

	local keys=(
		"8F427EAF" # Linaro Toolchain Builder
		"9F0E78D5" # Igor Pecovnik
	)

	mkdir -p "${SRC}/cache/.aria2"
	local aria2_options=(
		# Display
		--console-log-level=error
		--summary-interval=0
		--download-result=hide

		# Meta
		--server-stat-if="${SRC}/cache/.aria2/server_stats"
		--server-stat-of="${SRC}/cache/.aria2/server_stats"
		--dht-file-path="${SRC}/cache/.aria2/dht.dat"
		--rpc-save-upload-metadata=false
		--auto-save-interval=0

		# File
		--auto-file-renaming=false
		--allow-overwrite=true
		--file-allocation=trunc

		# Connection
		--disable-ipv6=$DISABLE_IPV6
		--connect-timeout=10
		--timeout=10
		--allow-piece-length-change=true
		--max-connection-per-server=2
		--lowest-speed-limit=500K

		# BT
		--seed-time=0
		--bt-stop-timeout=30
	)

	# try to avoid "[ERROR] Failed to open ServerStat file .../cache/.aria2/server_stats for read." on first run
	if [[ ! -f "${SRC}/cache/.aria2/server_stats" ]]; then
		mkdir -p "${SRC}/cache/.aria2"
		touch "${SRC}/cache/.aria2/server_stats"
	fi

	# use local signature file
	if [[ -f "${SRC}/config/torrents/${filename}.asc" ]]; then
		local torrent="${SRC}/config/torrents/${filename}.torrent"
		ln -sf "${SRC}/config/torrents/${filename}.asc" "${localdir}/${filename}.asc"
	else
		# download signature file
		aria2c "${aria2_options[@]}" \
			--continue=false \
			--dir="${localdir}" --out="${filename}.asc" \
			$(get_urls "${catalog}" "${filename}.asc")

		local rc=$?
		if [[ $rc -ne 0 ]]; then
			# Except `not found`
			[[ $rc -ne 3 ]] && display_alert "Failed to download signature file. aria2 exit code:" "$rc" "wrn"
			return $rc
		fi

		[[ ${USE_TORRENT} == "yes" ]] &&
			local torrent="$(get_urls "${catalog}" "${filename}.torrent")"
	fi

	# download torrent first
	local direct=yes
	if [[ ${USE_TORRENT} == "yes" ]]; then

		display_alert "downloading using torrent network" "$filename"
		aria2c "${aria2_options[@]}" \
			--follow-torrent=mem \
			--dir="${localdir}" \
			${torrent}

		[[ $? -eq 0 ]] && direct=no

	fi

	# direct download if torrent fails
	if [[ $direct != "no" ]]; then
		display_alert "downloading using http(s) network" "$filename"
		aria2c "${aria2_options[@]}" \
			--dir="${localdir}" --out="${filename}" \
			$(get_urls "${catalog}" "${filename}")

		local rc=$?
		if [[ $rc -ne 0 ]]; then
			display_alert "Failed to download. aria2 exit code:" "$rc" "wrn"
			return $rc
		fi

		echo ""
	fi

	local verified=false
	if [[ -f ${localdir}/${filename}.asc ]]; then

		if grep -q 'BEGIN PGP SIGNATURE' "${localdir}/${filename}.asc"; then

			if [[ ! -d "${SRC}"/cache/.gpg ]]; then
				mkdir -p "${SRC}"/cache/.gpg
				chmod 700 "${SRC}"/cache/.gpg
				touch "${SRC}"/cache/.gpg/gpg.conf
				chmod 600 "${SRC}"/cache/.gpg/gpg.conf
			fi

			for key in "${keys[@]}"; do
				gpg --homedir "${SRC}/cache/.gpg" --no-permission-warning \
					--list-keys "${key}" ||
					gpg --homedir "${SRC}/cache/.gpg" --no-permission-warning \
						${http_proxy:+--keyserver-options http-proxy="${http_proxy}"} \
						--keyserver "hkp://keyserver.ubuntu.com:80" \
						--recv-keys "${key}" ||
					exit_with_error "Failed to receive key" "${key}"
			done

			gpg --homedir "${SRC}"/cache/.gpg --no-permission-warning --trust-model always \
				-q --verify "${localdir}/${filename}.asc"
			[[ ${PIPESTATUS[0]} -eq 0 ]] && verified=true && display_alert "Verified" "PGP" "info"

		else

			[[ "$(md5sum "${localdir}/${filename}" | awk '{printf $1}')" == "$(awk '{printf $1}' ${localdir}/${filename}.asc)" ]] &&
				verified=true && display_alert "Verified" "MD5" "info"

		fi

		if [[ $verified != true ]]; then
			rm -rf "${localdir:?}/${filename:?}"* # We also delete asc file
			exit_with_error "verification failed"
		fi

	fi
}
