compile_firmware() {
	display_alert "Merging and packaging linux firmware" "@host" "info"

	local firmwaretempdir plugin_dir

	firmwaretempdir=$(mktemp -d)
	chmod 700 ${firmwaretempdir}

	# @TODO: these traps are a real trap.
	#trap "rm -rf \"${firmwaretempdir}\" ; exit 0" 0 1 2 3 15
	plugin_dir="armbian-firmware${FULL}"
	mkdir -p "${firmwaretempdir}/${plugin_dir}/lib/firmware"

	fetch_from_repo "https://github.com/armbian/firmware" "armbian-firmware-git" "branch:master"

	if [[ -n $FULL ]]; then
		fetch_from_repo "$MAINLINE_FIRMWARE_SOURCE" "linux-firmware-git" "branch:master"
		# cp : create hardlinks
		cp -af --reflink=auto "${SRC}"/cache/sources/linux-firmware-git/* "${firmwaretempdir}/${plugin_dir}/lib/firmware/"
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
	rsync -rq "armbian-firmware${FULL}_${REVISION}_all.deb" "${DEB_STORAGE}/"

	# remove temp directory - @TODO: maybe not, just leave thrash behind.
	rm -rf "${firmwaretempdir}"
}

compile_armbian-zsh() {

	local tmp_dir armbian_zsh_dir
	tmp_dir=$(mktemp -d)
	chmod 700 ${tmp_dir}

	# @TODO: these traps are a real trap.
	#trap "rm -rf \"${tmp_dir}\" ; exit 0" 0 1 2 3 15
	armbian_zsh_dir=armbian-zsh_${REVISION}_all
	display_alert "Building deb" "armbian-zsh" "info"

	fetch_from_repo "https://github.com/robbyrussell/oh-my-zsh" "oh-my-zsh" "branch:master"
	fetch_from_repo "https://github.com/mroth/evalcache" "evalcache" "branch:master"

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

	# disable prompt while update
	sed -i 's/# DISABLE_UPDATE_PROMPT="true"/DISABLE_UPDATE_PROMPT="true"/g' "${tmp_dir}/${armbian_zsh_dir}"/etc/skel/.zshrc

	# disable auto update since we provide update via package
	sed -i 's/# DISABLE_AUTO_UPDATE="true"/DISABLE_AUTO_UPDATE="true"/g' "${tmp_dir}/${armbian_zsh_dir}"/etc/skel/.zshrc

	# define default plugins
	sed -i 's/^plugins=.*/plugins=(evalcache git git-extras debian tmux screen history extract colorize web-search docker)/' "${tmp_dir}/${armbian_zsh_dir}"/etc/skel/.zshrc

	chmod 755 "${tmp_dir}/${armbian_zsh_dir}"/DEBIAN/postinst

	fakeroot_dpkg_deb_build "${tmp_dir}/${armbian_zsh_dir}"
	rsync --remove-source-files -rq "${tmp_dir}/${armbian_zsh_dir}.deb" "${DEB_STORAGE}/"
	rm -rf "${tmp_dir}"

}

compile_armbian-config() {

	local tmp_dir armbian_config_dir
	tmp_dir=$(mktemp -d)
	chmod 700 ${tmp_dir}

	# @TODO: these traps are a real trap.
	#trap "rm -rf \"${tmp_dir}\" ; exit 0" 0 1 2 3 15
	armbian_config_dir=armbian-config_${REVISION}_all
	display_alert "Building deb" "armbian-config" "info"

	fetch_from_repo "https://github.com/armbian/config" "armbian-config" "branch:master"
	fetch_from_repo "https://github.com/dylanaraps/neofetch" "neofetch" "tag:7.1.0"
	fetch_from_repo "https://github.com/complexorganizations/wireguard-manager" "wireguard-manager" "tag:v1.0.0.10-26-2021"

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
	rsync --remove-source-files -rq "${tmp_dir}/${armbian_config_dir}.deb" "${DEB_STORAGE}/"
	rm -rf "${tmp_dir}"
}

compile_xilinx_bootgen() {
	# Source code checkout
	(fetch_from_repo "https://github.com/Xilinx/bootgen.git" "xilinx-bootgen" "branch:master")

	pushd "${SRC}"/cache/sources/xilinx-bootgen || exit

	# Compile and install only if git commit hash changed
	# need to check if /usr/local/bin/bootgen to detect new Docker containers with old cached sources
	if [[ ! -f .commit_id || $(improved_git rev-parse @ 2> /dev/null) != $(< .commit_id) || ! -f /usr/local/bin/bootgen ]]; then
		display_alert "Compiling" "xilinx-bootgen" "info"
		make -s clean > /dev/null
		make -s -j$(nproc) bootgen > /dev/null
		mkdir -p /usr/local/bin/
		install bootgen /usr/local/bin > /dev/null 2>&1
		improved_git rev-parse @ 2> /dev/null > .commit_id
	fi

	popd
}
