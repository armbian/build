function extension_prepare_config__linux_source_package_extension() {
	display_alert "Packaging kernel source enabled. This will enforce ARTIFACT_IGNORE_CACHE=yes in order to prepare the source code." "${EXTENSION}" "info"
	declare -g ARTIFACT_IGNORE_CACHE=yes	# enforce building from scratch
	declare -g KERNEL_GIT=shallow			# download necessary branch only
}

function add_host_dependencies__add_fakeroot() {
	display_alert "Adding packages to host dependencies" "${EXTENSION}" "info"
	EXTRA_BUILD_DEPS="${EXTRA_BUILD_DEPS} fakeroot"
}

function armbian_kernel_config__create_ksrc_package() {
	if [[ -f .config ]]; then

		#( set -o posix ; set )
		echo ${kernel_version_family}

		display_alert "Packaging kernel source..." "${EXTENSION}" "info"
		declare kernel_work_dir="${SRC}/cache/sources/${LINUXSOURCEDIR}"
		declare CHOSEN_KSRC=linux-source-${BRANCH}-${LINUXFAMILY}

		ts=$(date +%s)
		local sources_pkg_dir tmp_src_dir
		tmp_src_dir=$(mktemp -d)
		trap "ret=\$?; rm -rf \"${tmp_src_dir}\" ; exit \$ret" 0 1 2 3 15
		sources_pkg_dir=${tmp_src_dir}/${CHOSEN_KSRC}_${REVISION}_all
		mkdir -p "${sources_pkg_dir}"/usr/src/ \
			"${sources_pkg_dir}"/usr/share/doc/linux-source-${version}-${LINUXFAMILY} \
			"${sources_pkg_dir}"/DEBIAN

		cp "${SRC}/config/kernel/${LINUXCONFIG}.config" "default_${LINUXCONFIG}.config"
		xz < ${kernel_work_dir}/.config > "${sources_pkg_dir}/usr/src/${LINUXCONFIG}_${version}_${REVISION}_config.xz"

		display_alert "Compressing sources for the linux-source package" "${EXTENSION}" "info"
		tar cp --directory="$kernel_work_dir" --exclude='.git' --owner=root . |
			pv -p -b -r -s "$(du -sb "$kernel_work_dir" --exclude=='.git' | cut -f1)" |
			xz -T0 -1 > "${sources_pkg_dir}/usr/src/linux-source-${version}-${LINUXFAMILY}.tar.xz"
		cp ${kernel_work_dir}/COPYING "${sources_pkg_dir}/usr/share/doc/linux-source-${version}-${LINUXFAMILY}/LICENSE"

		cat <<- EOF > "${sources_pkg_dir}"/DEBIAN/control
			Package: linux-source-${version}-${BRANCH}-${LINUXFAMILY}
			Version: ${version}-${BRANCH}-${LINUXFAMILY}+${REVISION}
			Architecture: all
			Maintainer: $MAINTAINER <$MAINTAINERMAIL>
			Section: kernel
			Priority: optional
			Depends: binutils, coreutils, linux-base
			Provides: linux-source, linux-source-${REVISION}-${LINUXFAMILY}
			Recommends: gcc, make
			Description: This package provides the source code for the Linux kernel $REVISION
		EOF

		fakeroot dpkg-deb -b -z0 "${sources_pkg_dir}" "${sources_pkg_dir}.deb"
		rsync --remove-source-files -rq "${sources_pkg_dir}.deb" "${DEB_STORAGE}/"

		te=$(date +%s)
		display_alert "Make the linux-source package" "$(($te - $ts)) sec." "info"
		rm -rf "${tmp_src_dir}"
	fi
}