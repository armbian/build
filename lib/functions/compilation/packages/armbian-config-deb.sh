compile_armbian-config() {

	local tmp_dir armbian_config_dir
	tmp_dir=$(mktemp -d) # subject to TMPDIR/WORKDIR, so is protected by single/common error trapmanager to clean-up.
	chmod 700 "${tmp_dir}"

	armbian_config_dir=armbian-config_${REVISION}_all
	display_alert "Building deb" "armbian-config" "info"

	fetch_from_repo "https://github.com/armbian/config" "armbian-config" "branch:master"
	fetch_from_repo "https://github.com/dylanaraps/neofetch" "neofetch" "tag:7.1.0"

	# @TODO: move this to where it is actually used; not everyone needs to pull this in
	fetch_from_repo "$GITHUB_SOURCE/complexorganizations/wireguard-manager" "wireguard-manager" "branch:main"

	mkdir -p "${tmp_dir}/${armbian_config_dir}"/{DEBIAN,usr/bin/,usr/sbin/,usr/lib/armbian-config/}

	# set up control file
	cat <<- END > "${tmp_dir}/${armbian_config_dir}"/DEBIAN/control
		Package: armbian-config
		Version: $REVISION
		Architecture: all
		Maintainer: $MAINTAINER <$MAINTAINERMAIL>
		Replaces: armbian-bsp, neofetch
		Depends: bash, iperf3, psmisc, curl, bc, expect, dialog, pv, zip, \
		debconf-utils, unzip, build-essential, html2text, html2text, dirmngr, software-properties-common, debconf, jq
		Recommends: armbian-bsp
		Suggests: libpam-google-authenticator, qrencode, network-manager, sunxi-tools
		Section: utils
		Priority: optional
		Description: Armbian configuration utility
	END

	install -m 755 "${SRC}"/cache/sources/neofetch/neofetch "${tmp_dir}/${armbian_config_dir}"/usr/bin/neofetch
	cd "${tmp_dir}/${armbian_config_dir}"/usr/bin/ || exit_with_error "Failed to cd to ${tmp_dir}/${armbian_config_dir}/usr/bin/"
	process_patch_file "${SRC}/patch/misc/add-armbian-neofetch.patch" "applying"

	install -m 755 "${SRC}"/cache/sources/wireguard-manager/wireguard-manager.sh "${tmp_dir}/${armbian_config_dir}"/usr/bin/wireguard-manager
	install -m 755 "${SRC}"/cache/sources/armbian-config/scripts/tv_grab_file "${tmp_dir}/${armbian_config_dir}"/usr/bin/tv_grab_file
	install -m 755 "${SRC}"/cache/sources/armbian-config/debian-config "${tmp_dir}/${armbian_config_dir}"/usr/sbin/armbian-config
	install -m 644 "${SRC}"/cache/sources/armbian-config/debian-config-jobs "${tmp_dir}/${armbian_config_dir}"/usr/lib/armbian-config/jobs.sh
	install -m 644 "${SRC}"/cache/sources/armbian-config/debian-config-submenu "${tmp_dir}/${armbian_config_dir}"/usr/lib/armbian-config/submenu.sh
	install -m 644 "${SRC}"/cache/sources/armbian-config/debian-config-functions "${tmp_dir}/${armbian_config_dir}"/usr/lib/armbian-config/functions.sh
	install -m 644 "${SRC}"/cache/sources/armbian-config/debian-config-functions-network "${tmp_dir}/${armbian_config_dir}"/usr/lib/armbian-config/functions-network.sh
	install -m 755 "${SRC}"/cache/sources/armbian-config/softy "${tmp_dir}/${armbian_config_dir}"/usr/sbin/softy
	# fallback to replace armbian-config in BSP
	ln -sf /usr/sbin/armbian-config "${tmp_dir}/${armbian_config_dir}"/usr/bin/armbian-config
	ln -sf /usr/sbin/softy "${tmp_dir}/${armbian_config_dir}"/usr/bin/softy

	fakeroot_dpkg_deb_build "${tmp_dir}/${armbian_config_dir}"
	run_host_command_logged rsync --remove-source-files -r "${tmp_dir}/${armbian_config_dir}.deb" "${DEB_STORAGE}/"
}
