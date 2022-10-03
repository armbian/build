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
