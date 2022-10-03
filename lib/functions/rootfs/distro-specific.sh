install_distribution_specific()
{

	display_alert "Applying distribution specific tweaks for" "$RELEASE" "info"

	case $RELEASE in

	sid)

			# (temporally) disable broken service
			chroot "${SDCARD}" /bin/bash -c "systemctl --no-reload disable smartmontools.service >/dev/null 2>&1"

		;;

	focal|jammy)

			# by using default lz4 initrd compression leads to corruption, go back to proven method
			sed -i "s/^COMPRESS=.*/COMPRESS=gzip/" "${SDCARD}"/etc/initramfs-tools/initramfs.conf

			rm -f "${SDCARD}"/etc/update-motd.d/{10-uname,10-help-text,50-motd-news,80-esm,80-livepatch,90-updates-available,91-release-upgrade,95-hwe-eol}

			if [ -d "${SDCARD}"/etc/NetworkManager ]; then
				local RENDERER=NetworkManager
			else
				local RENDERER=networkd
			fi

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
			sed -i '/DAEMON_OPTS=/s/"-F -1"/"-F 0"/' "${SDCARD}"/etc/default/chrony

			# disable conflicting services
			chroot "${SDCARD}" /bin/bash -c "systemctl --no-reload mask ondemand.service >/dev/null 2>&1"

		;;

	esac

	# configure language and locales
	display_alert "Configuring locales" "$DEST_LANG" "info"
	if [[ -f $SDCARD/etc/locale.gen ]]; then
		[ -n "$DEST_LANG" ] && sed -i "s/^# $DEST_LANG/$DEST_LANG/" $SDCARD/etc/locale.gen
		sed -i '/ C.UTF-8/s/^# //g' $SDCARD/etc/locale.gen
		sed -i '/en_US.UTF-8/s/^# //g' $SDCARD/etc/locale.gen
	fi
	eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -c "locale-gen"' ${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}
	[ -n "$DEST_LANG" ] && eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -c \
	"update-locale --reset LANG=$DEST_LANG LANGUAGE=$DEST_LANG LC_ALL=$DEST_LANG"' ${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}

	# Basic Netplan config. Let NetworkManager/networkd manage all devices on this system
	[[ -d "${SDCARD}"/etc/netplan ]] && cat <<-EOF > "${SDCARD}"/etc/netplan/armbian-default.yaml
	network:
		  version: 2
		  renderer: $RENDERER
	EOF

	# cleanup motd services and related files
	chroot "${SDCARD}" /bin/bash -c "systemctl disable motd-news.service >/dev/null 2>&1"
	chroot "${SDCARD}" /bin/bash -c "systemctl disable motd-news.timer >/dev/null 2>&1"

	# remove motd news from motd.ubuntu.com
	[[ -f "${SDCARD}"/etc/default/motd-news ]] && sed -i "s/^ENABLED=.*/ENABLED=0/" "${SDCARD}"/etc/default/motd-news

	# remove doubled uname from motd
	[[ -f "${SDCARD}"/etc/update-motd.d/10-uname ]] && rm "${SDCARD}"/etc/update-motd.d/10-uname

	# rc.local is not existing but one might need it
	install_rclocal

	# use list modules INITRAMFS
	if [ -f "${SRC}"/config/modules/"${MODULES_INITRD}" ]; then
		display_alert "Use file list modules INITRAMFS" "${MODULES_INITRD}"
		sed -i "s/^MODULES=.*/MODULES=list/" "${SDCARD}"/etc/initramfs-tools/initramfs.conf
		cat "${SRC}"/config/modules/"${MODULES_INITRD}" >> "${SDCARD}"/etc/initramfs-tools/modules
	fi
}

# create_sources_list <release> <basedir>
#
# <release>: bullseye|focal|jammy|sid
# <basedir>: path to root directory
#
create_sources_list()
{
	local release=$1
	local basedir=$2
	[[ -z $basedir ]] && exit_with_error "No basedir passed to create_sources_list"

	case $release in
	buster)
	cat <<-EOF > "${basedir}"/etc/apt/sources.list
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

	bullseye|bookworm|trixie)
	cat <<-EOF > "${basedir}"/etc/apt/sources.list
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
	cat <<-EOF > "${basedir}"/etc/apt/sources.list
	deb http://${DEBIAN_MIRROR} $release main contrib non-free
	#deb-src http://${DEBIAN_MIRROR} $release main contrib non-free
	EOF
	;;

	focal|jammy)
	cat <<-EOF > "${basedir}"/etc/apt/sources.list
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

	display_alert "Adding Armbian repository and authentication key" "/etc/apt/sources.list.d/armbian.list" "info"

	# apt-key add is getting deprecated
	APT_VERSION=$(chroot "${basedir}" /bin/bash -c "apt --version | cut -d\" \" -f2")
	if linux-version compare "${APT_VERSION}" ge 2.4.1; then
		# add armbian key
		mkdir -p "${basedir}"/usr/share/keyrings
		# change to binary form
		gpg --dearmor < "${SRC}"/config/armbian.key > "${basedir}"/usr/share/keyrings/armbian.gpg
		SIGNED_BY="[signed-by=/usr/share/keyrings/armbian.gpg] "
	else
		# use old method for compatibility reasons
		cp "${SRC}"/config/armbian.key "${basedir}"
		chroot "${basedir}" /bin/bash -c "cat armbian.key | apt-key add - > /dev/null 2>&1"
	fi

	# stage: add armbian repository and install key
	if [[ $DOWNLOAD_MIRROR == "china" ]]; then
		echo "deb ${SIGNED_BY}https://mirrors.tuna.tsinghua.edu.cn/armbian $RELEASE main ${RELEASE}-utils ${RELEASE}-desktop" > "${basedir}"/etc/apt/sources.list.d/armbian.list
	elif [[ $DOWNLOAD_MIRROR == "bfsu" ]]; then
	    echo "deb ${SIGNED_BY}http://mirrors.bfsu.edu.cn/armbian $RELEASE main ${RELEASE}-utils ${RELEASE}-desktop" > "${basedir}"/etc/apt/sources.list.d/armbian.list
	else
		echo "deb ${SIGNED_BY}http://"$([[ $BETA == yes ]] && echo "beta" || echo "apt" )".armbian.com $RELEASE main ${RELEASE}-utils ${RELEASE}-desktop" > "${basedir}"/etc/apt/sources.list.d/armbian.list
	fi

	# replace local package server if defined. Suitable for development
	[[ -n $LOCAL_MIRROR ]] && echo "deb ${SIGNED_BY}http://$LOCAL_MIRROR $RELEASE main ${RELEASE}-utils ${RELEASE}-desktop" > "${basedir}"/etc/apt/sources.list.d/armbian.list

	# disable repo if SKIP_ARMBIAN_REPO=yes
	if [[ "${SKIP_ARMBIAN_REPO}" == "yes" ]]; then
		display_alert "Disabling armbian repo" "${ARCH}-${RELEASE}" "wrn"
		mv "${SDCARD}"/etc/apt/sources.list.d/armbian.list "${SDCARD}"/etc/apt/sources.list.d/armbian.list.disabled
	fi

}
