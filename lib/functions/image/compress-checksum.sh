function image_compress_and_checksum() {
	[[ -n $SEND_TO_SERVER ]] && return 0

	if [[ $COMPRESS_OUTPUTIMAGE == "" || $COMPRESS_OUTPUTIMAGE == no ]]; then
		COMPRESS_OUTPUTIMAGE="sha,gpg,img"
	elif [[ $COMPRESS_OUTPUTIMAGE == yes ]]; then
		COMPRESS_OUTPUTIMAGE="sha,gpg,7z"
	fi

	if [[ $COMPRESS_OUTPUTIMAGE == *gz* ]]; then
		display_alert "Compressing" "${DESTIMG}/${version}.img.gz" "info"
		pigz -3 < $DESTIMG/${version}.img > $DESTIMG/${version}.img.gz
		compression_type=".gz"
	fi

	if [[ $COMPRESS_OUTPUTIMAGE == *xz* ]]; then
		# @TODO: rpardini: I'd just move to zstd and be done with it. It does it right.

		display_alert "Compressing" "${DESTIMG}/${version}.img.xz" "info"
		# compressing consumes a lot of memory we don't have. Waiting for previous packing job to finish helps to run a lot more builds in parallel
		available_cpu=$(grep -c 'processor' /proc/cpuinfo)
		[[ ${available_cpu} -gt 16 ]] && available_cpu=16                                               # using more cpu cores for compressing is pointless
		available_mem=$(LC_ALL=c free | grep Mem | awk '{print $4/$2 * 100.0}' | awk '{print int($1)}') # in percentage
		# build optimisations when memory drops below 5%
		if [[ ${BUILD_ALL} == yes && (${available_mem} -lt 15 || $(ps -uax | grep "pixz" | wc -l) -gt 4) ]]; then
			while [[ $(ps -uax | grep "pixz" | wc -l) -gt 2 ]]; do
				echo -en "#"
				sleep 20
			done
		fi
		pixz -7 -p ${available_cpu} -f $(expr ${available_cpu} + 2) < $DESTIMG/${version}.img > ${DESTIMG}/${version}.img.xz
		compression_type=".xz"
	fi

	if [[ $COMPRESS_OUTPUTIMAGE == *img* || $COMPRESS_OUTPUTIMAGE == *7z* ]]; then
		#			mv $DESTIMG/${version}.img ${FINALDEST}/${version}.img || exit 1
		compression_type=""
	fi

	if [[ $COMPRESS_OUTPUTIMAGE == *sha* ]]; then
		cd ${DESTIMG}
		display_alert "SHA256 calculating" "${version}.img${compression_type}" "info"
		sha256sum -b ${version}.img${compression_type} > ${version}.img${compression_type}.sha
	fi

	if [[ $COMPRESS_OUTPUTIMAGE == *gpg* ]]; then
		cd ${DESTIMG}
		if [[ -n $GPG_PASS ]]; then
			display_alert "GPG signing" "${version}.img${compression_type}" "info"
			if [[ -n $SUDO_USER ]]; then
				sudo chown -R ${SUDO_USER}:${SUDO_USER} "${DESTIMG}"/
				SUDO_PREFIX="sudo -H -u ${SUDO_USER}"
			else
				SUDO_PREFIX=""
			fi
			echo "${GPG_PASS}" | $SUDO_PREFIX bash -c "gpg --passphrase-fd 0 --armor --detach-sign --pinentry-mode loopback --batch --yes ${DESTIMG}/${version}.img${compression_type}" || exit 1
		else
			display_alert "GPG signing skipped - no GPG_PASS" "${version}.img" "wrn"
		fi
	fi

	fingerprint_image "${DESTIMG}/${version}.img${compression_type}.txt" "${version}"

	if [[ $COMPRESS_OUTPUTIMAGE == *7z* ]]; then
		display_alert "Compressing" "${DESTIMG}/${version}.7z" "info"
		7za a -t7z -bd -m0=lzma2 -mx=3 -mfb=64 -md=32m -ms=on \
			${DESTIMG}/${version}.7z ${version}.key ${version}.img* > /dev/null 2>&1
		find ${DESTIMG}/ -type \
			f \( -name "${version}.img" -o -name "${version}.img.asc" -o -name "${version}.img.txt" -o -name "${version}.img.sha" \) -print0 |
			xargs -0 rm > /dev/null 2>&1
	fi
}
