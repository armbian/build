#!/usr/bin/env bash
create_linux-source_package() {
	ts=$(date +%s)
	local sources_pkg_dir tmp_src_dir
	tmp_src_dir=$(mktemp -d)
	trap "ret=\$?; rm -rf \"${tmp_src_dir}\" ; exit \$ret" 0 1 2 3 15
	sources_pkg_dir=${tmp_src_dir}/${CHOSEN_KSRC}_${REVISION}_all
	mkdir -p "${sources_pkg_dir}"/usr/src/ \
		"${sources_pkg_dir}"/usr/share/doc/linux-source-${version}-${LINUXFAMILY} \
		"${sources_pkg_dir}"/DEBIAN

	cp "${SRC}/config/kernel/${LINUXCONFIG}.config" "default_${LINUXCONFIG}.config"
	xz < .config > "${sources_pkg_dir}/usr/src/${LINUXCONFIG}_${version}_${REVISION}_config.xz"

	display_alert "Compressing sources for the linux-source package"
	tar cp --directory="$kerneldir" --exclude='.git' --owner=root . |
		pv -p -b -r -s "$(du -sb "$kerneldir" --exclude=='.git' | cut -f1)" |
		pixz -4 > "${sources_pkg_dir}/usr/src/linux-source-${version}-${LINUXFAMILY}.tar.xz"
	cp COPYING "${sources_pkg_dir}/usr/share/doc/linux-source-${version}-${LINUXFAMILY}/LICENSE"

	cat <<- EOF > "${sources_pkg_dir}"/DEBIAN/control
		Package: linux-source-${version}-${BRANCH}-${LINUXFAMILY}
		Version: ${version}-${BRANCH}-${LINUXFAMILY}+${REVISION}
		Architecture: all
		Maintainer: $MAINTAINER <$MAINTAINERMAIL>
		Section: kernel
		Priority: optional
		Depends: binutils, coreutils
		Provides: linux-source, linux-source-${version}-${LINUXFAMILY}
		Recommends: gcc, make
		Description: This package provides the source code for the Linux kernel $version
	EOF

	fakeroot dpkg-deb -b -Z${DEB_COMPRESS} -z0 "${sources_pkg_dir}" "${sources_pkg_dir}.deb"
	rsync --remove-source-files -rq "${sources_pkg_dir}.deb" "${DEB_STORAGE}/"

	te=$(date +%s)
	display_alert "Make the linux-source package" "$(($te - $ts)) sec." "info"
	rm -rf "${tmp_src_dir}"
}
