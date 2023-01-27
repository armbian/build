function image_compress_and_checksum() {
	[[ -n $SEND_TO_SERVER ]] && return 0

	# check that 'version' is set
	[[ -z $version ]] && exit_with_error "version is not set"
	# compression_type: declared in outer scope

	if [[ $COMPRESS_OUTPUTIMAGE == *gz* ]]; then
		display_alert "Compressing" "${DESTIMG}/${version}.img.gz" "info"
		pigz -3 < "$DESTIMG/${version}".img > "$DESTIMG/${version}".img.gz
		compression_type=".gz"
	fi

	if [[ $COMPRESS_OUTPUTIMAGE == *xz* ]]; then
		# @TODO: rpardini: I'd just move to zstd and be done with it. It does it right.
		display_alert "Compressing" "${DESTIMG}/${version}.img.xz" "info"
		declare -i available_cpu
		available_cpu=$(grep -c 'processor' /proc/cpuinfo)
		[[ ${available_cpu} -gt 16 ]] && available_cpu=16 # using more cpu cores for compressing is pointless
		pixz -7 -p ${available_cpu} -f $((available_cpu + 2)) < "$DESTIMG/${version}".img > "${DESTIMG}/${version}".img.xz
		compression_type=".xz"
	fi

	if [[ $COMPRESS_OUTPUTIMAGE == *img* || $COMPRESS_OUTPUTIMAGE == *7z* ]]; then
		compression_type=""
	fi

	if [[ $COMPRESS_OUTPUTIMAGE == *sha* ]]; then
		cd "${DESTIMG}" || exit_with_error "Could not cd to ${DESTIMG}"
		display_alert "SHA256 calculating" "${version}.img${compression_type}" "info"
		sha256sum -b "${version}.img${compression_type}" > "${version}.img${compression_type}".sha
	fi

	fingerprint_image "${DESTIMG}/${version}.img${compression_type}.txt" "${version}"

	if [[ $COMPRESS_OUTPUTIMAGE == *7z* ]]; then
		display_alert "Untested code path, bumpy road ahead" "7z compression" "wrn"
		display_alert "Compressing" "${DESTIMG}/${version}.7z" "info"
		7za a -t7z -bd -m0=lzma2 -mx=3 -mfb=64 -md=32m -ms=on "${DESTIMG}/${version}".7z "${version}".key "${version}".img*
		find "${DESTIMG}"/ -type
		f \( -name "${version}.img" -o -name "${version}.img.asc" -o -name "${version}.img.txt" -o -name "${version}.img.sha" \) -print0 |
			xargs -0 rm
	fi
}
