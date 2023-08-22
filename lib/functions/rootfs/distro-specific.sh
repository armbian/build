#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function install_distribution_specific() {
	display_alert "Applying distribution specific tweaks for" "${RELEASE:-}" "info"

	# disable broken service, the problem is in default misconfiguration
	# disable hostapd as it needs to be configured to start correctly
	disable_systemd_service_sdcard smartmontools.service smartd.service hostapd.service

	case "${RELEASE}" in

		focal | jammy | kinetic | lunar)

			# by using default lz4 initrd compression leads to corruption, go back to proven method
			# @TODO: rpardini: this should be a config option (which is always set to zstd ;-D )
			sed -i "s/^COMPRESS=.*/COMPRESS=gzip/" "${SDCARD}"/etc/initramfs-tools/initramfs.conf

			run_host_command_logged rm -f "${SDCARD}"/etc/update-motd.d/{10-uname,10-help-text,50-motd-news,80-esm,80-livepatch,90-updates-available,91-release-upgrade,95-hwe-eol}

			declare RENDERER=networkd
			if [ -d "${SDCARD}"/etc/NetworkManager ]; then
				local RENDERER=NetworkManager
			fi

			# DNS fix
			if [[ -n "$NAMESERVER" ]]; then
				if [[ -f "${SDCARD}"/etc/systemd/resolved.conf ]]; then
					sed -i "s/#DNS=.*/DNS=$NAMESERVER/g" "${SDCARD}"/etc/systemd/resolved.conf
				else
					display_alert "DNS fix" "/etc/systemd/resolved.conf not found: ${DISTRIBUTION} ${RELEASE}" "info"
				fi
			fi

			# Journal service adjustements
			sed -i "s/#Storage=.*/Storage=volatile/g" "${SDCARD}"/etc/systemd/journald.conf
			sed -i "s/#Compress=.*/Compress=yes/g" "${SDCARD}"/etc/systemd/journald.conf
			sed -i "s/#RateLimitIntervalSec=.*/RateLimitIntervalSec=30s/g" "${SDCARD}"/etc/systemd/journald.conf
			sed -i "s/#RateLimitBurst=.*/RateLimitBurst=10000/g" "${SDCARD}"/etc/systemd/journald.conf

			# Chrony temporal fix https://bugs.launchpad.net/ubuntu/+source/chrony/+bug/1878005
			[[ -f "${SDCARD}"/etc/default/chrony ]] && sed -i '/DAEMON_OPTS=/s/"-F -1"/"-F 0"/' "${SDCARD}"/etc/default/chrony

			# disable conflicting services
			disable_systemd_service_sdcard ondemand.service

			# Remove Ubuntu APT spamming
			install_artifact_deb_chroot "fake-ubuntu-advantage-tools"
			truncate --size=0 "${SDCARD}"/etc/apt/apt.conf.d/20apt-esm-hook.conf

			;;
	esac

	# install our base-files package (this replaces the original from Debian/Ubuntu)
	if [[ "${KEEP_ORIGINAL_OS_RELEASE:-"no"}" != "yes" ]]; then
		install_artifact_deb_chroot "armbian-base-files"
	fi

	# Basic Netplan config. Let NetworkManager/networkd manage all devices on this system
	[[ -d "${SDCARD}"/etc/netplan ]] && cat <<- EOF > "${SDCARD}"/etc/netplan/armbian-default.yaml
		network:
		  version: 2
		  renderer: ${RENDERER}
	EOF

	# cleanup motd services and related files
	disable_systemd_service_sdcard motd-news.service motd-news.timer

	# remove motd news from motd.ubuntu.com
	[[ -f "${SDCARD}"/etc/default/motd-news ]] && sed -i "s/^ENABLED=.*/ENABLED=0/" "${SDCARD}"/etc/default/motd-news

	# remove doubled uname from motd
	[[ -f "${SDCARD}"/etc/update-motd.d/10-uname ]] && rm "${SDCARD}"/etc/update-motd.d/10-uname

	# rc.local is not existing but one might need it
	install_rclocal

	# use list modules INITRAMFS
	if [ -f "${SRC}"/config/modules/"${MODULES_INITRD}" ]; then
		display_alert "Use file list modules MODULES_INITRD" "${MODULES_INITRD}"
		sed -i "s/^MODULES=.*/MODULES=list/" "${SDCARD}"/etc/initramfs-tools/initramfs.conf
		cat "${SRC}"/config/modules/"${MODULES_INITRD}" >> "${SDCARD}"/etc/initramfs-tools/modules
	fi
}

# create_sources_list_and_deploy_repo_key <when> <release> <basedir>
#
# <when>: rootfs|image
# <release>: bullseye|bookworm|sid|focal|jammy|kinetic|lunar
# <basedir>: path to root directory
#
function create_sources_list_and_deploy_repo_key() {
	declare when="${1}"
	declare release="${2}"
	declare basedir="${3}" # @TODO: rpardini: this is SDCARD in all practical senses. Why not just use SDCARD?
	[[ -z $basedir ]] && exit_with_error "No basedir passed to create_sources_list_and_deploy_repo_key"

	case $release in
		buster)
			cat <<- EOF > "${basedir}"/etc/apt/sources.list
				deb http://${DEBIAN_MIRROR} $release main contrib non-free
				#deb-src http://${DEBIAN_MIRROR} $release main contrib non-free

				deb http://${DEBIAN_MIRROR} ${release}-updates main contrib non-free
				#deb-src http://${DEBIAN_MIRROR} ${release}-updates main contrib non-free

				deb http://${DEBIAN_MIRROR} ${release}-backports main contrib non-free
				#deb-src http://${DEBIAN_MIRROR} ${release}-backports main contrib non-free

				deb http://${DEBIAN_SECURTY} ${release}/updates main contrib non-free
				#deb-src http://${DEBIAN_SECURTY} ${release}/updates main contrib non-free
			EOF
			;;

		bullseye)
			cat <<- EOF > "${basedir}"/etc/apt/sources.list
				deb http://${DEBIAN_MIRROR} $release main contrib non-free
				#deb-src http://${DEBIAN_MIRROR} $release main contrib non-free

				deb http://${DEBIAN_MIRROR} ${release}-updates main contrib non-free
				#deb-src http://${DEBIAN_MIRROR} ${release}-updates main contrib non-free

				deb http://${DEBIAN_MIRROR} ${release}-backports main contrib non-free
				#deb-src http://${DEBIAN_MIRROR} ${release}-backports main contrib non-free

				deb http://${DEBIAN_SECURTY} ${release}-security main contrib non-free
				#deb-src http://${DEBIAN_SECURTY} ${release}-security main contrib non-free
			EOF
			;;

		bookworm | trixie)
			# non-free firmware in bookworm and later has moved from the non-free archive component to a new non-free-firmware component (alongside main/contrib/non-free). This was implemented on 2023-01-27, see also https://lists.debian.org/debian-boot/2023/01/msg00235.html
			cat <<- EOF > "${basedir}"/etc/apt/sources.list
				deb http://${DEBIAN_MIRROR} $release main contrib non-free non-free-firmware
				#deb-src http://${DEBIAN_MIRROR} $release main contrib non-free non-free-firmware

				deb http://${DEBIAN_MIRROR} ${release}-updates main contrib non-free non-free-firmware
				#deb-src http://${DEBIAN_MIRROR} ${release}-updates main contrib non-free non-free-firmware

				deb http://${DEBIAN_MIRROR} ${release}-backports main contrib non-free non-free-firmware
				#deb-src http://${DEBIAN_MIRROR} ${release}-backports main contrib non-free non-free-firmware

				deb http://${DEBIAN_SECURTY} ${release}-security main contrib non-free non-free-firmware
				#deb-src http://${DEBIAN_SECURTY} ${release}-security main contrib non-free non-free-firmware
			EOF
			;;

		sid) # sid is permanent unstable development and has no such thing as updates or security
			cat <<- EOF > "${basedir}"/etc/apt/sources.list
				deb http://${DEBIAN_MIRROR} $release main contrib non-free non-free-firmware
				#deb-src http://${DEBIAN_MIRROR} $release main contrib non-free non-free-firmware

				deb http://${DEBIAN_MIRROR} unstable main contrib non-free non-free-firmware
				#deb-src http://${DEBIAN_MIRROR} unstable main contrib non-free non-free-firmware
			EOF

			# Exception: with riscv64 not everything was moved from ports
			# https://lists.debian.org/debian-riscv/2023/07/msg00053.html
			if [[ "${ARCH}" == riscv64 ]]; then
				echo "deb http://deb.debian.org/debian-ports/ sid main " >> "${basedir}"/etc/apt/sources.list
			fi
			;;

		focal | jammy | kinetic | lunar)
			cat <<- EOF > "${basedir}"/etc/apt/sources.list
				deb http://${UBUNTU_MIRROR} $release main restricted universe multiverse
				#deb-src http://${UBUNTU_MIRROR} $release main restricted universe multiverse

				deb http://${UBUNTU_MIRROR} ${release}-security main restricted universe multiverse
				#deb-src http://${UBUNTU_MIRROR} ${release}-security main restricted universe multiverse

				deb http://${UBUNTU_MIRROR} ${release}-updates main restricted universe multiverse
				#deb-src http://${UBUNTU_MIRROR} ${release}-updates main restricted universe multiverse

				deb http://${UBUNTU_MIRROR} ${release}-backports main restricted universe multiverse
				#deb-src http://${UBUNTU_MIRROR} ${release}-backports main restricted universe multiverse
			EOF
			;;
	esac

	display_alert "Adding Armbian repository and authentication key" "${when} :: /etc/apt/sources.list.d/armbian.list" "info"

	# apt-key add is getting deprecated
	APT_VERSION=$(chroot "${basedir}" /bin/bash -c "apt --version | cut -d\" \" -f2")
	if linux-version compare "${APT_VERSION}" ge 2.4.1; then
		# add armbian key
		mkdir -p "${basedir}"/usr/share/keyrings
		# change to binary form
		gpg --dearmor < "${SRC}"/config/armbian.key > "${basedir}"/usr/share/keyrings/armbian.gpg
		SIGNED_BY="[signed-by=/usr/share/keyrings/armbian.gpg] "
	else
		# use old method for compatibility reasons # @TODO: rpardini: not gonna fix this?
		cp "${SRC}"/config/armbian.key "${basedir}"
		chroot "${basedir}" /bin/bash -c "cat armbian.key | apt-key add -"
	fi

	declare -a components=()
	if [[ "${when}" == "image"* ]]; then # only include the 'main' component when deploying to image (early or late)
		components+=("main")
	fi
	components+=("${RELEASE}-utils")   # utils contains packages Igor picks from other repos
	components+=("${RELEASE}-desktop") # desktop contains packages Igor picks from other repos

	# stage: add armbian repository and install key
	if [[ $DOWNLOAD_MIRROR == "china" ]]; then
		echo "deb ${SIGNED_BY}https://mirrors.tuna.tsinghua.edu.cn/armbian $RELEASE ${components[*]}" > "${basedir}"/etc/apt/sources.list.d/armbian.list
	elif [[ $DOWNLOAD_MIRROR == "bfsu" ]]; then
		echo "deb ${SIGNED_BY}http://mirrors.bfsu.edu.cn/armbian $RELEASE ${components[*]}" > "${basedir}"/etc/apt/sources.list.d/armbian.list
	else
		echo "deb ${SIGNED_BY}http://$([[ $BETA == yes ]] && echo "beta" || echo "apt").armbian.com $RELEASE ${components[*]}" > "${basedir}"/etc/apt/sources.list.d/armbian.list
	fi

	# replace local package server if defined. Suitable for development
	[[ -n $LOCAL_MIRROR ]] && echo "deb ${SIGNED_BY}http://$LOCAL_MIRROR $RELEASE ${components[*]}" > "${basedir}"/etc/apt/sources.list.d/armbian.list

	# disable repo if SKIP_ARMBIAN_REPO==yes, or if when==image-early.
	if [[ "${when}" == "image-early" || "${SKIP_ARMBIAN_REPO}" == "yes" ]]; then
		display_alert "Disabling Armbian repo" "${ARCH}-${RELEASE} :: skip:${SKIP_ARMBIAN_REPO:-"no"} when:${when}" "info"
		mv "${SDCARD}"/etc/apt/sources.list.d/armbian.list "${SDCARD}"/etc/apt/sources.list.d/armbian.list.disabled
	fi

	declare CUSTOM_REPO_WHEN="${when}"

	# Let user customize
	call_extension_method "custom_apt_repo" <<- 'CUSTOM_APT_REPO'
		*customize apt sources.list.d and/or deploy repo keys*
		Called after core Armbian has finished setting up SDCARD's sources.list and sources.list.d/armbian.list.
		If SKIP_ARMBIAN_REPO=yes, armbian.list.disabled is present instead.
		The global Armbian GPG key has been deployed to SDCARD's /usr/share/keyrings/armbian.gpg, de-armored.
		You can implement this hook to add, remove, or modify sources.list.d entries, and/or deploy additional GPG keys.
		Important: honor $CUSTOM_REPO_WHEN; if it's ==rootfs, don't add repos/components that carry the .debs produced by armbian/build.
		Ideally, also don't add any possibly-conflicting repo if `$CUSTOM_REPO_WHEN==image-early`.
		`$CUSTOM_APT_REPO==image-late` is passed during the very final stages of image building, after all packages were installed/upgraded.
	CUSTOM_APT_REPO

	unset CUSTOM_REPO_WHEN

	return 0
}
