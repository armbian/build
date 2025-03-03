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
	disable_systemd_service_sdcard smartmontools.service smartd.service

	if [[ "${DISTRIBUTION}" == "Ubuntu" ]]; then

		# by using default lz4 initrd compression leads to corruption, go back to proven method
		# @TODO: rpardini: this should be a config option (which is always set to zstd ;-D )
		sed -i "s/^COMPRESS=.*/COMPRESS=gzip/" "${SDCARD}"/etc/initramfs-tools/initramfs.conf

		run_host_command_logged rm -f "${SDCARD}"/etc/update-motd.d/{10-uname,10-help-text,50-motd-news,80-esm,80-livepatch,90-updates-available,91-release-upgrade,95-hwe-eol}

		# Journal service adjustements
		sed -i "s/#Storage=.*/Storage=volatile/g" "${SDCARD}"/etc/systemd/journald.conf
		sed -i "s/#Compress=.*/Compress=yes/g" "${SDCARD}"/etc/systemd/journald.conf
		sed -i "s/#RateLimitIntervalSec=.*/RateLimitIntervalSec=30s/g" "${SDCARD}"/etc/systemd/journald.conf
		sed -i "s/#RateLimitBurst=.*/RateLimitBurst=10000/g" "${SDCARD}"/etc/systemd/journald.conf

		# disable conflicting services
		disable_systemd_service_sdcard ondemand.service

		# Remove Ubuntu APT spamming
		install_artifact_deb_chroot "fake-ubuntu-advantage-tools"
		truncate --size=0 "${SDCARD}"/etc/apt/apt.conf.d/20apt-esm-hook.conf
	fi

	# install our base-files package (this replaces the original from Debian/Ubuntu)
	if [[ "${KEEP_ORIGINAL_OS_RELEASE:-"no"}" != "yes" ]]; then
		install_artifact_deb_chroot "armbian-base-files" "--allow-downgrades"
	fi

	# Set DNS server if systemd-resolved is in use
	if [[ -n "$NAMESERVER" && -f "${SDCARD}"/etc/systemd/resolved.conf ]]; then
		display_alert "Using systemd-resolved" "for DNS management" "info"
		# This used to set a default DNS entry from $NAMESERVER into "${SDCARD}"/etc/systemd/resolved.conf.d/00-armbian-default-dns.conf -- no longer; better left to DHCP.
	fi

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
# <release>: bullseye|bookworm|sid|focal|jammy|noble|oracular|plucky
# <basedir>: path to root directory
#
function create_sources_list_and_deploy_repo_key() {
	declare when="${1}"
	declare release="${2}"
	declare basedir="${3}" # @TODO: rpardini: this is SDCARD in all practical senses. Why not just use SDCARD?
	[[ -z $basedir ]] && exit_with_error "No basedir passed to create_sources_list_and_deploy_repo_key"

	declare distro=""

	# Add upstream (Debian/Ubuntu) APT repository
	case $release in
		buster | bullseye | bookworm | trixie)
			distro="debian"

			declare -a suites=("${release}" "${release}-updates")
			declare -a security_suites=("${release}-security")
			declare -a components=(main contrib non-free)

			if [[ "$release" == "buster" ]]; then
				security_suites=("${release}/updates")
			else
			  suites+=("${release}-backports")
			fi

			if [[ "$release" != "buster" && "$release" != "bullseye" ]]; then
			  components+=("non-free-firmware")
			fi

			cat <<- EOF > "${basedir}/etc/apt/sources.list.d/${distro}.sources"
			Types: deb
			URIs: http://${DEBIAN_MIRROR}
			Suites: ${suites[@]}
			Components: ${components[@]}
			Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

			Types: deb
			URIs: http://${DEBIAN_SECURTY}
			Suites: ${security_suites[@]}
			Components: ${components[@]}
			Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
			EOF
			;;

		sid | unstable)
			distro="debian"

			# sid is permanent unstable development and has no such thing as updates or security
			cat <<- EOF > "${basedir}/etc/apt/sources.list.d/${distro}.sources"
			Types: deb
			URIs: http://${DEBIAN_MIRROR}
			Suites: ${release}
			Components: main contrib non-free non-free-firmware
			Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
			EOF

			# Required for some packages on riscv64.
			# See: http://lists.debian.org/debian-riscv/2023/07/msg00053.html
			if [[ "${ARCH}" == riscv64 ]]; then
				cat <<- EOF >> "${basedir}/etc/apt/sources.list.d/${distro}.sources"

				Types: deb
				URIs: http://deb.debian.org/debian-ports/
				Suites: ${release}
				Components: main
				Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
				Architectures: riscv64
				EOF
			fi
			;;

		focal | jammy | noble | oracular | plucky)
			distro="ubuntu"

			cat <<- EOF > "${basedir}/etc/apt/sources.list.d/${distro}.sources"
			Types: deb
			URIs: http://${UBUNTU_MIRROR}
			Suites: ${release} ${release}-security ${release}-updates ${release}-backports
			Components: main restricted universe multiverse
			Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
			EOF
			;;
	esac

	# add armbian key
	display_alert "Adding Armbian repository and authentication key" "${when} :: /etc/apt/sources.list.d/armbian.sources" "info"
	mkdir -p "${basedir}"/usr/share/keyrings
	# change to binary form
	APT_SIGNING_KEY_FILE="/usr/share/keyrings/armbian.gpg"
	gpg --dearmor < "${SRC}"/config/armbian.key > "${basedir}${APT_SIGNING_KEY_FILE}"

	# lets keep old way for old distributions
	if [[ "${RELEASE}" =~ (focal|bullseye) ]]; then
		cp "${SRC}"/config/armbian.key "${basedir}"
		chroot "${basedir}" /bin/bash -c "cat armbian.key | apt-key add - > /dev/null 2>&1"
	fi

	# Add Armbian APT repository
	declare -a components=()
	if [[ "${when}" == "image"* ]]; then # only include the 'main' component when deploying to image (early or late)
		components+=("main")
	fi
	components+=("${RELEASE}-utils")   # utils contains packages Igor picks from other repos
	components+=("${RELEASE}-desktop") # desktop contains packages Igor picks from other repos

	# stage: add armbian repository and install key
	# armbian_mirror="http://$([[ $BETA == yes ]] && echo "beta" || echo "apt").armbian.com"
	declare armbian_mirror="apt.armbian.com"
	if [[ -n $LOCAL_MIRROR ]]; then
		armbian_mirror="$LOCAL_MIRROR"
	elif [[ $DOWNLOAD_MIRROR == "china" ]]; then
		armbian_mirror="mirrors.tuna.tsinghua.edu.cn/armbian"
	elif [[ $DOWNLOAD_MIRROR == "bfsu" ]]; then
		armbian_mirror="mirrors.bfsu.edu.cn/armbian"
	elif [[ $BETA == "yes" ]]; then
		armbian_mirror="beta.armbian.com"
	fi
	cat <<- EOF > "${basedir}"/etc/apt/sources.list.d/armbian.sources
	Types: deb
	URIs: https://${armbian_mirror}
	Suites: $RELEASE
	Components: ${components[*]}
	Signed-By: ${APT_SIGNING_KEY_FILE}
	EOF

	# disable repo if DISTRIBUTION_STATUS==eos, or if SKIP_ARMBIAN_REPO==yes, or if when==image-early.
	if [[ "${when}" == "image-early" ||
		"$(cat "${SRC}/config/distributions/${RELEASE}/support")" == "eos" ||
		"${SKIP_ARMBIAN_REPO}" == "yes" ]]; then
		display_alert "Disabling Armbian repo" "${ARCH}-${RELEASE} :: skip:${SKIP_ARMBIAN_REPO:-"no"} when:${when}" "info"
		mv "${SDCARD}"/etc/apt/sources.list.d/armbian.sources "${SDCARD}"/etc/apt/sources.list.d/armbian.sources.disabled
	fi

	declare CUSTOM_REPO_WHEN="${when}"

	# Let user customize
	call_extension_method "custom_apt_repo" <<- 'CUSTOM_APT_REPO'
		*customize apt sources.list.d and/or deploy repo keys*
		Called after core Armbian has finished setting up SDCARD's debian.sources/ubuntu.sources and armbian.sources in /etc/apt/sources.list.d/.
		If SKIP_ARMBIAN_REPO=yes, armbian.sources.disabled is present instead.
		The global Armbian GPG key has been deployed to SDCARD's ${APT_SIGNING_KEY_FILE}, de-armored.
		You can implement this hook to add, remove, or modify sources.list.d entries, and/or deploy additional GPG keys.
		Important: honor $CUSTOM_REPO_WHEN; if it's ==rootfs, don't add repos/components that carry the .debs produced by armbian/build.
		Ideally, also don't add any possibly-conflicting repo if `$CUSTOM_REPO_WHEN==image-early`.
		`$CUSTOM_APT_REPO==image-late` is passed during the very final stages of image building, after all packages were installed/upgraded.
	CUSTOM_APT_REPO

	unset CUSTOM_REPO_WHEN

	return 0
}
