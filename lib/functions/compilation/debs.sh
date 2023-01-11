#!/usr/bin/env bash
compile_firmware() {
	display_alert "Merging and packaging linux firmware" "@host" "info"

	local firmwaretempdir plugin_dir

	firmwaretempdir=$(mktemp -d) # subject to TMPDIR/WORKDIR, so is protected by single/common error trapmanager to clean-up.
	chmod 700 ${firmwaretempdir}

	plugin_dir="armbian-firmware${FULL}"
	mkdir -p "${firmwaretempdir}/${plugin_dir}/lib/firmware"
	
	local ARMBIAN_FIRMWARE_GIT_SOURCE="${ARMBIAN_FIRMWARE_GIT_SOURCE:-"https://github.com/armbian/firmware"}"
	local ARMBIAN_FIRMWARE_GIT_BRANCH="${ARMBIAN_FIRMWARE_GIT_BRANCH:-"master"}"

	fetch_from_repo "${ARMBIAN_FIRMWARE_GIT_SOURCE}" "armbian-firmware-git" "branch:${ARMBIAN_FIRMWARE_GIT_BRANCH}"

	if [[ -n $FULL ]]; then
		fetch_from_repo "$MAINLINE_FIRMWARE_SOURCE" "linux-firmware-git" "branch:main"
		# cp : create hardlinks
		run_host_command_logged cp -af --reflink=auto "${SRC}"/cache/sources/linux-firmware-git/* "${firmwaretempdir}/${plugin_dir}/lib/firmware/"
		# cp : create hardlinks for ath11k WCN685x hw2.1 firmware since they are using the same firmware with hw2.0
		run_host_command_logged cp -af --reflink=auto "${firmwaretempdir}/${plugin_dir}/lib/firmware/ath11k/WCN6855/hw2.0/" "${firmwaretempdir}/${plugin_dir}/lib/firmware/ath11k/WCN6855/hw2.1/"
	fi
	# overlay our firmware
	# cp : create hardlinks
	cp -af --reflink=auto "${SRC}"/cache/sources/armbian-firmware-git/* "${firmwaretempdir}/${plugin_dir}/lib/firmware/"

	rm -rf "${firmwaretempdir}/${plugin_dir}"/lib/firmware/.git
	cd "${firmwaretempdir}/${plugin_dir}" || exit

	# set up control file
	mkdir -p DEBIAN
	cat <<- END > DEBIAN/control
		Package: armbian-firmware${FULL}
		Version: $REVISION
		Architecture: all
		Maintainer: $MAINTAINER <$MAINTAINERMAIL>
		Installed-Size: 1
		Replaces: linux-firmware, firmware-brcm80211, firmware-ralink, firmware-samsung, firmware-realtek, armbian-firmware${REPLACE}
		Section: kernel
		Priority: optional
		Description: Linux firmware${FULL}
	END

	cd "${firmwaretempdir}" || exit
	# pack
	mv "armbian-firmware${FULL}" "armbian-firmware${FULL}_${REVISION}_all"
	display_alert "Building firmware package" "armbian-firmware${FULL}_${REVISION}_all" "info"
	fakeroot_dpkg_deb_build "armbian-firmware${FULL}_${REVISION}_all"
	mv "armbian-firmware${FULL}_${REVISION}_all" "armbian-firmware${FULL}"
	run_host_command_logged rsync -rq "armbian-firmware${FULL}_${REVISION}_all.deb" "${DEB_STORAGE}/"

}

compile_armbian-zsh() {

	local tmp_dir armbian_zsh_dir
	tmp_dir=$(mktemp -d) # subject to TMPDIR/WORKDIR, so is protected by single/common error trapmanager to clean-up.
	chmod 700 ${tmp_dir}

	armbian_zsh_dir=armbian-zsh_${REVISION}_all
	display_alert "Building deb" "armbian-zsh" "info"

	fetch_from_repo "$GITHUB_SOURCE/ohmyzsh/ohmyzsh" "oh-my-zsh" "branch:master"
	fetch_from_repo "$GITHUB_SOURCE/mroth/evalcache" "evalcache" "branch:master"

	mkdir -p "${tmp_dir}/${armbian_zsh_dir}"/{DEBIAN,etc/skel/,etc/oh-my-zsh/,/etc/skel/.oh-my-zsh/cache}

	# set up control file
	cat <<- END > "${tmp_dir}/${armbian_zsh_dir}"/DEBIAN/control
		Package: armbian-zsh
		Version: $REVISION
		Architecture: all
		Maintainer: $MAINTAINER <$MAINTAINERMAIL>
		Depends: zsh, tmux
		Section: utils
		Priority: optional
		Description: Armbian improved ZShell
	END

	# set up post install script
	cat <<- END > "${tmp_dir}/${armbian_zsh_dir}"/DEBIAN/postinst
		#!/bin/sh

		# copy cache directory if not there yet
		awk -F'[:]' '{if (\$3 >= 1000 && \$3 != 65534 || \$3 == 0) print ""\$6"/.oh-my-zsh"}' /etc/passwd | xargs -i sh -c 'test ! -d {} && cp -R --attributes-only /etc/skel/.oh-my-zsh {}'
		awk -F'[:]' '{if (\$3 >= 1000 && \$3 != 65534 || \$3 == 0) print ""\$6"/.zshrc"}' /etc/passwd | xargs -i sh -c 'test ! -f {} && cp -R /etc/skel/.zshrc {}'

		# fix owner permissions in home directory
		awk -F'[:]' '{if (\$3 >= 1000 && \$3 != 65534 || \$3 == 0) print ""\$1":"\$3" "\$6"/.oh-my-zsh"}' /etc/passwd | xargs -n2 chown -R
		awk -F'[:]' '{if (\$3 >= 1000 && \$3 != 65534 || \$3 == 0) print ""\$1":"\$3" "\$6"/.zshrc"}' /etc/passwd | xargs -n2 chown -R

		# add support for bash profile
		! grep emulate /etc/zsh/zprofile  >/dev/null && echo "emulate sh -c 'source /etc/profile'" >> /etc/zsh/zprofile
		exit 0
	END

	cp -R "${SRC}"/cache/sources/oh-my-zsh "${tmp_dir}/${armbian_zsh_dir}"/etc/
	cp -R "${SRC}"/cache/sources/evalcache "${tmp_dir}/${armbian_zsh_dir}"/etc/oh-my-zsh/plugins
	cp "${tmp_dir}/${armbian_zsh_dir}"/etc/oh-my-zsh/templates/zshrc.zsh-template "${tmp_dir}/${armbian_zsh_dir}"/etc/skel/.zshrc

	chmod -R g-w,o-w "${tmp_dir}/${armbian_zsh_dir}"/etc/oh-my-zsh/

	# we have common settings
	sed -i "s/^export ZSH=.*/export ZSH=\/etc\/oh-my-zsh/" "${tmp_dir}/${armbian_zsh_dir}"/etc/skel/.zshrc

	# user cache
	sed -i "/^export ZSH=.*/a export ZSH_CACHE_DIR=~\/.oh-my-zsh\/cache" "${tmp_dir}/${armbian_zsh_dir}"/etc/skel/.zshrc

	# define theme
	sed -i 's/^ZSH_THEME=.*/ZSH_THEME="mrtazz"/' "${tmp_dir}/${armbian_zsh_dir}"/etc/skel/.zshrc

	# disable auto update since we provide update via package
	sed -i "s/^# zstyle ':omz:update' mode disabled.*/zstyle ':omz:update' mode disabled/g" "${tmp_dir}/${armbian_zsh_dir}"/etc/skel/.zshrc

	# define default plugins
	sed -i 's/^plugins=.*/plugins=(evalcache git git-extras debian tmux screen history extract colorize web-search docker)/' "${tmp_dir}/${armbian_zsh_dir}"/etc/skel/.zshrc

	chmod 755 "${tmp_dir}/${armbian_zsh_dir}"/DEBIAN/postinst

	fakeroot_dpkg_deb_build "${tmp_dir}/${armbian_zsh_dir}"
	run_host_command_logged rsync --remove-source-files -r "${tmp_dir}/${armbian_zsh_dir}.deb" "${DEB_STORAGE}/"

}

compile_armbian-config() {

	local tmp_dir armbian_config_dir
	tmp_dir=$(mktemp -d) # subject to TMPDIR/WORKDIR, so is protected by single/common error trapmanager to clean-up.
	chmod 700 ${tmp_dir}

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
	cd "${tmp_dir}/${armbian_config_dir}"/usr/bin/
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

compile_xilinx_bootgen() {
	# Source code checkout
	fetch_from_repo "https://github.com/Xilinx/bootgen.git" "xilinx-bootgen" "branch:master"

	pushd "${SRC}"/cache/sources/xilinx-bootgen || exit

	# Compile and install only if git commit hash changed
	# need to check if /usr/local/bin/bootgen to detect new Docker containers with old cached sources
	if [[ ! -f .commit_id || $(git rev-parse @ 2> /dev/null) != $(< .commit_id) || ! -f /usr/local/bin/bootgen ]]; then
		display_alert "Compiling" "xilinx-bootgen" "info"
		make -s clean > /dev/null
		make -s -j$(nproc) bootgen > /dev/null
		mkdir -p /usr/local/bin/
		install bootgen /usr/local/bin > /dev/null 2>&1
		git rev-parse @ 2> /dev/null > .commit_id
	fi

	popd
}

# @TODO: code from master via Igor; not yet armbian-next'fied! warning!!
compile_plymouth_theme_armbian() {

	local tmp_dir work_dir
	tmp_dir=$(mktemp -d)
	chmod 700 ${tmp_dir}
	plymouth_theme_armbian_dir=armbian-plymouth-theme_${REVISION}_all
	display_alert "Building deb" "armbian-plymouth-theme" "info"

	mkdir -p "${tmp_dir}/${plymouth_theme_armbian_dir}"/{DEBIAN,usr/share/plymouth/themes/armbian}

	# set up control file
	cat <<- END > "${tmp_dir}/${plymouth_theme_armbian_dir}"/DEBIAN/control
		Package: armbian-plymouth-theme
		Version: $REVISION
		Architecture: all
		Maintainer: $MAINTAINER <$MAINTAINERMAIL>
		Depends: plymouth, plymouth-themes
		Section: universe/x11
		Priority: optional
		Description: boot animation, logger and I/O multiplexer - armbian theme
	END

	cp "${SRC}"/packages/plymouth-theme-armbian/debian/{postinst,prerm,postrm} \
		"${tmp_dir}/${plymouth_theme_armbian_dir}"/DEBIAN/
	chmod 755 "${tmp_dir}/${plymouth_theme_armbian_dir}"/DEBIAN/{postinst,prerm,postrm}

	# this requires `imagemagick`

	convert -resize 256x256 \
		"${SRC}"/packages/plymouth-theme-armbian/armbian-logo.png \
		"${tmp_dir}/${plymouth_theme_armbian_dir}"/usr/share/plymouth/themes/armbian/bgrt-fallback.png

	# convert -resize 52x52 \
	# 	"${SRC}"/packages/plymouth-theme-armbian/spinner.gif \
	# 	"${tmp_dir}/${plymouth_theme_armbian_dir}"/usr/share/plymouth/themes/armbian/animation-%04d.png

	convert -resize 52x52 \
		"${SRC}"/packages/plymouth-theme-armbian/spinner.gif \
		"${tmp_dir}/${plymouth_theme_armbian_dir}"/usr/share/plymouth/themes/armbian/throbber-%04d.png

	cp "${SRC}"/packages/plymouth-theme-armbian/watermark.png \
		"${tmp_dir}/${plymouth_theme_armbian_dir}"/usr/share/plymouth/themes/armbian/

	cp "${SRC}"/packages/plymouth-theme-armbian/{bullet,capslock,entry,keyboard,keymap-render,lock}.png \
		"${tmp_dir}/${plymouth_theme_armbian_dir}"/usr/share/plymouth/themes/armbian/

	cp "${SRC}"/packages/plymouth-theme-armbian/armbian.plymouth \
		"${tmp_dir}/${plymouth_theme_armbian_dir}"/usr/share/plymouth/themes/armbian/

	fakeroot dpkg-deb -b -Z${DEB_COMPRESS} "${tmp_dir}/${plymouth_theme_armbian_dir}" > /dev/null
	rsync --remove-source-files -rq "${tmp_dir}/${plymouth_theme_armbian_dir}.deb" "${DEB_STORAGE}/"
	rm -rf "${tmp_dir}"
}
