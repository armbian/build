# cleaning <target>
#
# target: what to clean
# "make" - "make clean" for selected kernel and u-boot
# "debs" - delete output/debs for board&branch
# "ubootdebs" - delete output/debs for uboot&board&branch
# "alldebs" - delete output/debs
# "cache" - delete output/cache
# "oldcache" - remove old output/cache
# "images" - delete output/images
# "sources" - delete output/sources
#
cleaning() {
	case $1 in
		debs) # delete ${DEB_STORAGE} for current branch and family
			if [[ -d "${DEB_STORAGE}" ]]; then
				display_alert "Cleaning ${DEB_STORAGE} for" "$BOARD $BRANCH" "info"
				# easier than dealing with variable expansion and escaping dashes in file names
				find "${DEB_STORAGE}" -name "${CHOSEN_UBOOT}_*.deb" -delete
				find "${DEB_STORAGE}" \( -name "${CHOSEN_KERNEL}_*.deb" -o \
					-name "armbian-*.deb" -o \
					-name "${CHOSEN_KERNEL/image/dtb}_*.deb" -o \
					-name "${CHOSEN_KERNEL/image/headers}_*.deb" -o \
					-name "${CHOSEN_KERNEL/image/source}_*.deb" -o \
					-name "${CHOSEN_KERNEL/image/firmware-image}_*.deb" \) -delete
				[[ -n $RELEASE ]] && rm -f "${DEB_STORAGE}/${RELEASE}/${CHOSEN_ROOTFS}"_*.deb
				[[ -n $RELEASE ]] && rm -f "${DEB_STORAGE}/${RELEASE}/armbian-desktop-${RELEASE}"_*.deb
			fi
			;;

		ubootdebs) # delete ${DEB_STORAGE} for uboot, current branch and family
			if [[ -d "${DEB_STORAGE}" ]]; then
				display_alert "Cleaning ${DEB_STORAGE} for u-boot" "$BOARD $BRANCH" "info"
				# easier than dealing with variable expansion and escaping dashes in file names
				find "${DEB_STORAGE}" -name "${CHOSEN_UBOOT}_*.deb" -delete
			fi
			;;

		extras) # delete ${DEB_STORAGE}/extra/$RELEASE for all architectures
			if [[ -n $RELEASE && -d ${DEB_STORAGE}/extra/$RELEASE ]]; then
				display_alert "Cleaning ${DEB_STORAGE}/extra for" "$RELEASE" "info"
				rm -rf "${DEB_STORAGE}/extra/${RELEASE}"
			fi
			;;

		alldebs) # delete output/debs
			[[ -d "${DEB_STORAGE}" ]] && display_alert "Cleaning" "${DEB_STORAGE}" "info" && rm -rf "${DEB_STORAGE}"/*
			;;

		cache) # delete output/cache
			[[ -d "${SRC}"/cache/rootfs ]] && display_alert "Cleaning" "rootfs cache (all)" "info" && find "${SRC}"/cache/rootfs -type f -delete
			;;

		images) # delete output/images
			[[ -d "${DEST}"/images ]] && display_alert "Cleaning" "output/images" "info" && rm -rf "${DEST}"/images/*
			;;

		sources) # delete output/sources and output/buildpkg
			[[ -d "${SRC}"/cache/sources ]] && display_alert "Cleaning" "sources" "info" && rm -rf "${SRC}"/cache/sources/* "${DEST}"/buildpkg/*
			;;

		oldcache) # remove old `cache/rootfs` except for the newest 8 files
			if [[ -d "${SRC}"/cache/rootfs && $(ls -1 "${SRC}"/cache/rootfs/*.lz4 2> /dev/null | wc -l) -gt "${ROOTFS_CACHE_MAX}" ]]; then
				display_alert "Cleaning" "rootfs cache (old)" "info"
				(
					cd "${SRC}"/cache/rootfs
					ls -t *.lz4 | sed -e "1,${ROOTFS_CACHE_MAX}d" | xargs -d '\n' rm -f
				)
				# Remove signatures if they are present. We use them for internal purpose
				(
					cd "${SRC}"/cache/rootfs
					ls -t *.asc | sed -e "1,${ROOTFS_CACHE_MAX}d" | xargs -d '\n' rm -f
				)
			fi
			;;
	esac
}
