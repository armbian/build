install_distribution_specific() {
	display_alert "Applying distribution specific tweaks for" "$RELEASE" "info"

	case $RELEASE in
		xenial)
			# remove legal info from Ubuntu
			[[ -f "${SDCARD}"/etc/legal ]] && rm "${SDCARD}"/etc/legal

			# ureadahead needs kernel tracing options that AFAIK are present only in mainline. disable
			chroot "${SDCARD}" /bin/bash -c \
				"systemctl --no-reload mask ondemand.service ureadahead.service >/dev/null 2>&1"
			chroot "${SDCARD}" /bin/bash -c \
				"systemctl --no-reload mask setserial.service etc-setserial.service >/dev/null 2>&1"

			;;

		stretch | buster | sid)
			# remove doubled uname from motd
			[[ -f "${SDCARD}"/etc/update-motd.d/10-uname ]] && rm "${SDCARD}"/etc/update-motd.d/10-uname
			# rc.local is not existing but one might need it
			install_rclocal
			;;

		bullseye)
			# remove doubled uname from motd
			[[ -f "${SDCARD}"/etc/update-motd.d/10-uname ]] && rm "${SDCARD}"/etc/update-motd.d/10-uname
			# rc.local is not existing but one might need it
			install_rclocal
			# fix missing versioning
			[[ $(grep -L "VERSION_ID=" "${SDCARD}"/etc/os-release) ]] && echo 'VERSION_ID="11"' >> "${SDCARD}"/etc/os-release
			[[ $(grep -L "VERSION=" "${SDCARD}"/etc/os-release) ]] && echo 'VERSION="11 (bullseye)"' >> "${SDCARD}"/etc/os-release
			;;

		bionic | focal | hirsute | impish | jammy)
			# by using default lz4 initrd compression leads to corruption, go back to proven method
			sed -i "s/^COMPRESS=.*/COMPRESS=gzip/" "${SDCARD}"/etc/initramfs-tools/initramfs.conf

			# cleanup motd services and related files
			chroot "${SDCARD}" /bin/bash -c "systemctl disable  motd-news.service >/dev/null 2>&1"
			chroot "${SDCARD}" /bin/bash -c "systemctl disable  motd-news.timer >/dev/null 2>&1"

			rm -f "${SDCARD}"/etc/update-motd.d/{10-uname,10-help-text,50-motd-news,80-esm,80-livepatch,90-updates-available,91-release-upgrade,95-hwe-eol}

			# remove motd news from motd.ubuntu.com
			[[ -f "${SDCARD}"/etc/default/motd-news ]] && sed -i "s/^ENABLED=.*/ENABLED=0/" "${SDCARD}"/etc/default/motd-news

			# rc.local is not existing but one might need it
			install_rclocal

			if [ -d "${SDCARD}"/etc/NetworkManager ]; then
				local RENDERER=NetworkManager
			else
				local RENDERER=networkd
			fi

			# Basic Netplan config. Let NetworkManager/networkd manage all devices on this system
			[[ -d "${SDCARD}"/etc/netplan ]] && cat <<- EOF > "${SDCARD}"/etc/netplan/armbian-default.yaml
				network:
				  version: 2
				  renderer: $RENDERER
			EOF

			# DNS fix
			if [ -n "$NAMESERVER" ]; then
				sed -i "s/#DNS=.*/DNS=$NAMESERVER/g" "${SDCARD}"/etc/systemd/resolved.conf
			fi

			# Journal service adjustements
			sed -i "s/#Storage=.*/Storage=volatile/g" "${SDCARD}"/etc/systemd/journald.conf
			sed -i "s/#Compress=.*/Compress=yes/g" "${SDCARD}"/etc/systemd/journald.conf
			sed -i "s/#RateLimitIntervalSec=.*/RateLimitIntervalSec=30s/g" "${SDCARD}"/etc/systemd/journald.conf
			sed -i "s/#RateLimitBurst=.*/RateLimitBurst=10000/g" "${SDCARD}"/etc/systemd/journald.conf

			# Chrony temporal fix https://bugs.launchpad.net/ubuntu/+source/chrony/+bug/1878005
			[[ -f "${SDCARD}"/etc/default/chrony ]] && sed -i '/DAEMON_OPTS=/s/"-F -1"/"-F 0"/' "${SDCARD}"/etc/default/chrony

			# disable conflicting services
			chroot "${SDCARD}" /bin/bash -c "systemctl --no-reload mask ondemand.service >/dev/null 2>&1"
			;;
	esac

	# use list modules INITRAMFS
	if [ -f "${SRC}"/config/modules/"${MODULES_INITRD}" ]; then
		display_alert "Use file list modules INITRAMFS" "${MODULES_INITRD}"
		sed -i "s/^MODULES=.*/MODULES=list/" "${SDCARD}"/etc/initramfs-tools/initramfs.conf
		cat "${SRC}"/config/modules/"${MODULES_INITRD}" >> "${SDCARD}"/etc/initramfs-tools/modules
	fi
}

# create_sources_list <release> <basedir>
#
# <release>: buster|bullseye|bionic|focal|hirsute|impish|jammy|sid
# <basedir>: path to root directory
#
create_sources_list() {
	local release=$1
	local basedir=$2
	[[ -z $basedir ]] && exit_with_error "No basedir passed to create_sources_list"

	case $release in
		stretch | buster)
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

		bullseye | bookworm | trixie)
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

		sid) # sid is permanent unstable development and has no such thing as updates or security
			cat <<- EOF > "${basedir}"/etc/apt/sources.list
				deb http://${DEBIAN_MIRROR} $release main contrib non-free
				#deb-src http://${DEBIAN_MIRROR} $release main contrib non-free
			EOF
			;;

		xenial | bionic | focal | hirsute | impish | jammy)
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

	# stage: add armbian repository and install key
	if [[ $DOWNLOAD_MIRROR == "china" ]]; then
		echo "deb https://mirrors.tuna.tsinghua.edu.cn/armbian $RELEASE main ${RELEASE}-utils ${RELEASE}-desktop" > "${basedir}"/etc/apt/sources.list.d/armbian.list
	elif [[ $DOWNLOAD_MIRROR == "bfsu" ]]; then
		echo "deb http://mirrors.bfsu.edu.cn/armbian $RELEASE main ${RELEASE}-utils ${RELEASE}-desktop" > "${basedir}"/etc/apt/sources.list.d/armbian.list
	else
		echo "deb http://"$([[ $BETA == yes ]] && echo "beta" || echo "apt")".armbian.com $RELEASE main ${RELEASE}-utils ${RELEASE}-desktop" > "${basedir}"/etc/apt/sources.list.d/armbian.list
	fi

	# replace local package server if defined. Suitable for development
	[[ -n $LOCAL_MIRROR ]] && echo "deb http://$LOCAL_MIRROR $RELEASE main ${RELEASE}-utils ${RELEASE}-desktop" > "${basedir}"/etc/apt/sources.list.d/armbian.list

	# disable repo if SKIP_ARMBIAN_REPO=yes
	if [[ "${SKIP_ARMBIAN_REPO}" == "yes" ]]; then
		display_alert "Disabling armbian repo" "${ARCH}-${RELEASE}" "wrn"
		mv "${SDCARD}"/etc/apt/sources.list.d/armbian.list "${SDCARD}"/etc/apt/sources.list.d/armbian.list.disabled
	fi

	display_alert "Adding Armbian repository and authentication key" "/etc/apt/sources.list.d/armbian.list" "info"
	cp "${SRC}"/config/armbian.key "${basedir}"
	chroot "${basedir}" /bin/bash -c "cat armbian.key | apt-key add - > /dev/null 2>&1"
	rm "${basedir}"/armbian.key
}
#--------------------------------------------------------------------------------------------------------------------------------
# Create kernel boot logo from packages/blobs/splash/logo.png and packages/blobs/splash/spinner.gif (animated)
# and place to the file /lib/firmware/bootsplash
#--------------------------------------------------------------------------------------------------------------------------------
