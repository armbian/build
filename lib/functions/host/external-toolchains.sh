# This is mostly deprecated, since SKIP_EXTERNAL_TOOLCHAINS=yes by default.

function download_external_toolchains() {
	# build aarch64
	if [[ $(dpkg --print-architecture) == amd64 ]]; then
		if [[ "${SKIP_EXTERNAL_TOOLCHAINS}" != "yes" ]]; then

			# bind mount toolchain if defined
			if [[ -d "${ARMBIAN_CACHE_TOOLCHAIN_PATH}" ]]; then
				mountpoint -q "${SRC}"/cache/toolchain && umount -l "${SRC}"/cache/toolchain
				mount --bind "${ARMBIAN_CACHE_TOOLCHAIN_PATH}" "${SRC}"/cache/toolchain
			fi

			display_alert "Checking for external GCC compilers" "" "info"
			# download external Linaro compiler and missing special dependencies since they are needed for certain sources

			local toolchains=(
				"gcc-linaro-aarch64-none-elf-4.8-2013.11_linux.tar.xz"
				"gcc-linaro-arm-none-eabi-4.8-2014.04_linux.tar.xz"
				"gcc-linaro-arm-linux-gnueabihf-4.8-2014.04_linux.tar.xz"
				"gcc-linaro-7.4.1-2019.02-x86_64_arm-linux-gnueabi.tar.xz"
				"gcc-linaro-7.4.1-2019.02-x86_64_aarch64-linux-gnu.tar.xz"
				"gcc-arm-8.3-2019.03-x86_64-arm-linux-gnueabihf.tar.xz"
				"gcc-arm-8.3-2019.03-x86_64-aarch64-linux-gnu.tar.xz"
				"gcc-arm-9.2-2019.12-x86_64-arm-none-linux-gnueabihf.tar.xz"
				"gcc-arm-9.2-2019.12-x86_64-aarch64-none-linux-gnu.tar.xz"
				"gcc-arm-11.2-2022.02-x86_64-arm-none-linux-gnueabihf.tar.xz"
				"gcc-arm-11.2-2022.02-x86_64-aarch64-none-linux-gnu.tar.xz"
			)

			USE_TORRENT_STATUS=${USE_TORRENT}
			USE_TORRENT="no"
			for toolchain in "${toolchains[@]}"; do
				local toolchain_zip="${SRC}/cache/toolchain/${toolchain}"
				local toolchain_dir="${toolchain_zip%.tar.*}"
				if [[ ! -f "${toolchain_dir}/.download-complete" ]]; then
					download_and_verify "toolchain" "${toolchain}" ||
						exit_with_error "Failed to download toolchain" "${toolchain}"

					display_alert "decompressing"
					pv -p -b -r -c -N "[ .... ] ${toolchain}" "${toolchain_zip}" |
						xz -dc |
						tar xp --xattrs --no-same-owner --overwrite -C "${SRC}/cache/toolchain/"
					if [[ $? -ne 0 ]]; then
						rm -rf "${toolchain_dir}"
						exit_with_error "Failed to decompress toolchain" "${toolchain}"
					fi

					touch "${toolchain_dir}/.download-complete"
					rm -rf "${toolchain_zip}"* # Also delete asc file
				fi
			done
			USE_TORRENT=${USE_TORRENT_STATUS}

			local existing_dirs=($(ls -1 "${SRC}"/cache/toolchain))
			for dir in "${existing_dirs[@]}"; do
				local found=no
				for toolchain in "${toolchains[@]}"; do
					[[ $dir == ${toolchain%.tar.*} ]] && found=yes
				done
				if [[ $found == no ]]; then
					display_alert "Removing obsolete toolchain" "$dir"
					rm -rf "${SRC}/cache/toolchain/${dir}"
				fi
			done
		else
			display_alert "Ignoring toolchains" "SKIP_EXTERNAL_TOOLCHAINS: ${SKIP_EXTERNAL_TOOLCHAINS}" "info"
		fi
	fi
}
