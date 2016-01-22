#!/bin/bash
#
# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.
#
# This file is a part of tool chain https://github.com/igorpecovnik/lib
#

# Functions:
# debootstrap_ng
# create_rootfs_cache
# prepare_partitions
# create_image
# unmount_on_exit

# custom_debootstrap_ng
#
# main debootstrap function
#
debootstrap_ng()
{
	display_alert "Starting build process for" "$BOARD $RELEASE" "info"

	# trap to unmount stuff in case of error/manual interruption
	trap unmount_on_exit INT TERM EXIT

	# stage: clean and create directories
	rm -rf $DEST/cache/sdcard $DEST/cache/mount
	mkdir -p $DEST/cache/sdcard $DEST/cache/mount

	# stage: verify tmpfs configuration and mount
	# default maximum size for tmpfs mount is 1/2 of available RAM
	# CLI needs ~1.2GiB, Desktop - ~2.4GiB TODO: verify
	# calculate and set tmpfs mount to use 2/3 of available RAM
	local phymem=$(( $(awk '/MemTotal/ {print $2}' /proc/meminfo) / 1024 * 2 / 3)) # MiB
	if [[ $BUILD_DESKTOP == yes ]]; then local tmpfs_max_size=2400; else local tmpfs_max_size=1200; fi # MiB
	if [[ $FORCE_USE_RAMDISK == no ]]; then
		local use_tmpfs=no
	elif [[ $FORCE_USE_RAMDISK == yes || $phymem -gt $tmpfs_max_size ]]; then
		local use_tmpfs=yes
	fi

	if [[ $use_tmpfs == yes ]]; then
		mount -t tmpfs -o size=${tmpfs_max_size}M tmpfs $DEST/cache/sdcard
	fi

	# stage: prepare basic rootfs: unpack cache or create from scratch
	create_rootfs_cache

	# stage: mount or remount chroot special filesystems
	mount -t proc chproc $DEST/cache/sdcard/proc
	mount -t sysfs chsys $DEST/cache/sdcard/sys
	mount -t devtmpfs chdev $DEST/cache/sdcard/dev || mount --bind /dev $DEST/cache/sdcard/dev
	mount -t devpts chpts $DEST/cache/sdcard/dev/pts

	# stage: install distribution specific
	# NOTE: can be called from create_rootfs_cache
	# but it makes a little difference
	install_distribution_specific

	# stage: install kernel and u-boot packages
	# install board specific applications
	display_alert "Installing kernel, u-boot and board specific" "$RELEASE $BOARD" "info"
	install_kernel
	install_board_specific

	# cleanup for install_kernel and install_board_specific
	umount $DEST/cache/sdcard/tmp

	# install desktop files
	if [[ $BUILD_DESKTOP == yes ]]; then
		install_desktop
	fi

	# install additional applications
	if [[ $EXTERNAL == yes ]]; then
		install_external_applications
	fi

	# stage: user customization script
	# NOTE: installing too many packages may fill tmpfs mount
	cp $SRC/userpatches/customize-image.sh $DEST/cache/sdcard/tmp/customize-image.sh
	chmod +x $DEST/cache/sdcard/tmp/customize-image.sh
	display_alert "Calling image customization script" "customize-image.sh" "info"
	chroot $DEST/cache/sdcard /bin/bash -c "/tmp/customize-image.sh $RELEASE $FAMILY $BOARD $BUILD_DESKTOP"

	# stage: cleanup
	rm -f $DEST/cache/sdcard/usr/sbin/policy-rc.d
	rm -f $DEST/cache/sdcard/usr/bin/qemu-arm-static
	if [[ -x $DEST/cache/sdcard/sbin/initctl.REAL ]]; then
		mv -f $DEST/cache/sdcard/sbin/initctl.REAL $DEST/cache/sdcard/sbin/initctl
	fi
	if [[ -x $DEST/cache/sdcard/sbin/start-stop-daemon.REAL ]]; then
		mv -f $DEST/cache/sdcard/sbin/start-stop-daemon.REAL $DEST/cache/sdcard/sbin/start-stop-daemon
	fi

	umount -l $DEST/cache/sdcard/dev/pts
	umount -l $DEST/cache/sdcard/dev
	umount -l $DEST/cache/sdcard/proc
	umount -l $DEST/cache/sdcard/sys

	# stage: create partitions, format, mount image
	prepare_partitions

	# stage: create image
	create_image

	# stage: unmount tmpfs
	if [[ $use_tmpfs = yes ]]; then
		umount $DEST/cache/sdcard
	fi

	# remove exit trap
	trap - INT TERM EXIT

} #############################################################################

# create_rootfs_cache
#
# unpacks cached rootfs for $RELEASE or creates one
#
create_rootfs_cache()
{
	[[ $BUILD_DESKTOP == yes ]] && local variant_desktop=yes
	local cache_fname="$DEST/cache/rootfs/$RELEASE${variant_desktop:+_desktop}-ng.tgz"
	if [[ -f $cache_fname ]]; then
		local filemtime=$(stat -c %Y $cache_fname)
		local currtime=$(date +%s)
		local diff=$(( (currtime - filemtime) / 86400 ))
		display_alert "Extracting $(basename $cache_fname)" "$diff days old" "info"
		pv -p -b -r -c -N "$(basename $cache_fname)" "$cache_fname" | pigz -dc | tar xp -C $DEST/cache/sdcard/
	else
		display_alert "Creating new rootfs for" "$RELEASE" "info"

		# stage: debootstrap base system
		# apt-cacher-ng mirror configurarion
		if [[ $RELEASE = trusty ]]; then
			local apt_mirror="http://localhost:3142/ports.ubuntu.com/"
		else
			local apt_mirror="http://localhost:3142/httpredir.debian.org/debian"
		fi
		# apt-cacher-ng apt-get proxy parameter
		local apt_extra='-o Acquire::http::Proxy="http://localhost:3142"'

		display_alert "Installing base system" "Stage 1/2" "info"
		eval 'debootstrap --include=debconf-utils,locales --arch=armhf --foreign $RELEASE $DEST/cache/sdcard/ $apt_mirror' \
			${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/debootstrap.log'} \
			${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Debootstrap (stage 1/2)..." 20 80'} \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}

		cp /usr/bin/qemu-arm-static $DEST/cache/sdcard/usr/bin/
		# NOTE: not needed?
		mkdir -p $DEST/cache/sdcard/usr/share/keyrings/
		cp /usr/share/keyrings/debian-archive-keyring.gpg $DEST/cache/sdcard/usr/share/keyrings/

		display_alert "Installing base system" "Stage 2/2" "info"
		eval 'chroot $DEST/cache/sdcard /bin/bash -c "/debootstrap/debootstrap --second-stage"' \
			${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/debootstrap.log'} \
			${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Debootstrap (stage 2/2)..." 20 80'} \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}

		# stage: prepare chroot environment to install extra packages
		mount -t proc chproc $DEST/cache/sdcard/proc
		mount -t sysfs chsys $DEST/cache/sdcard/sys
		mount -t devtmpfs chdev $DEST/cache/sdcard/dev || mount --bind /dev $DEST/cache/sdcard/dev
		mount -t devpts chpts $DEST/cache/sdcard/dev/pts

		# policy-rc.d script prevents starting or reloading services
		# from dpkg pre- and post-install scripts during image creation

cat <<EOF > $DEST/cache/sdcard/usr/sbin/policy-rc.d
#!/bin/sh
exit 101
EOF
		chmod 755 $DEST/cache/sdcard/usr/sbin/policy-rc.d

		# ported from debootstrap and multistrap for upstart support
		if [[ -x $DEST/cache/sdcard/sbin/initctl ]]; then
			mv $DEST/cache/sdcard/sbin/start-stop-daemon $DEST/cache/sdcard/sbin/start-stop-daemon.REAL
cat <<EOF > $DEST/cache/sdcard/sbin/start-stop-daemon
#!/bin/sh
echo "Warning: Fake start-stop-daemon called, doing nothing"
EOF
			chmod 755 $DEST/cache/sdcard/sbin/start-stop-daemon
		fi

		if [[ -x $DEST/cache/sdcard/sbin/initctl ]]; then
			mv $DEST/cache/sdcard/sbin/initctl $DEST/cache/sdcard/sbin/initctl.REAL
cat <<EOF > $DEST/cache/sdcard/sbin/initctl
#!/bin/sh
echo "Warning: Fake initctl called, doing nothing"
EOF
			chmod 755 $DEST/cache/sdcard/sbin/initctl
		fi

		# stage: configure language and locales
		display_alert "Configuring locales" "$DEST_LANG" "info"

		if [ -f $DEST/cache/sdcard/etc/locale.gen ]; then sed -i "s/^# $DEST_LANG/$DEST_LANG/" $DEST/cache/sdcard/etc/locale.gen; fi
		eval 'LC_ALL=C LANG=C chroot $DEST/cache/sdcard /bin/bash -c "locale-gen $DEST_LANG"' ${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}
		eval 'LC_ALL=C LANG=C chroot $DEST/cache/sdcard /bin/bash -c "update-locale LANG=$DEST_LANG LANGUAGE=$DEST_LANG LC_MESSAGES=POSIX"' \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}
		LC_ALL=C LANG=C chroot $DEST/cache/sdcard /bin/bash -c "export CHARMAP=$CONSOLE_CHAR FONTFACE=8x16"

		# stage: copy proper apt sources list
		cp $SRC/lib/config/sources.list.$RELEASE $DEST/cache/sdcard/etc/apt/sources.list

		# stage: add armbian repository and install key
		echo "deb http://apt.armbian.com $RELEASE main" > $DEST/cache/sdcard/etc/apt/sources.list.d/armbian.list
		cp $SRC/lib/bin/armbian.key $DEST/cache/sdcard
		eval 'chroot $DEST/cache/sdcard /bin/bash -c "cat armbian.key | apt-key add -"' \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}
		rm $DEST/cache/sdcard/armbian.key

		# stage: update packages list
		display_alert "Updating package list" "$RELEASE" "info"
		eval 'LC_ALL=C LANG=C chroot $DEST/cache/sdcard /bin/bash -c "apt-get -y $apt_extra update"' \
			${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/debootstrap.log'} \
			${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Updating package lists..." 20 80'} \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}

		# common packages
		local package_list="alsa-utils automake btrfs-tools bash-completion bc bridge-utils bluez build-essential cmake cpufrequtils curl psmisc \
			device-tree-compiler dosfstools evtest figlet fbset fping git haveged hddtemp hdparm hostapd htop i2c-tools ifenslave-2.6 \
			iperf ir-keytable iotop iozone3 iw less libbluetooth-dev libbluetooth3 libtool libwrap0-dev libfuse2 libssl-dev lirc lsof makedev \
			module-init-tools mtp-tools nano ntfs-3g ntp parted pkg-config pciutils pv python-smbus rfkill rsync screen stress sudo subversion \
			sysfsutils toilet u-boot-tools unattended-upgrades unzip usbutils vlan wireless-tools weather-util weather-util-data wget wpasupplicant \
			iptables dvb-apps libdigest-sha-perl libproc-processtable-perl w-scan apt-transport-https sysbench libusb-dev dialog fake-hwclock \
			console-setup console-data kbd console-common unicode-data openssh-server"

		# release specific packages
		# NOTE: wheezy doen't have f2fs-tools package available
		case $RELEASE in
			wheezy)
			package_list="$package_list libnl-dev"
			;;
			jessie)
			package_list="$package_list thin-provisioning-tools libnl-3-dev libnl-genl-3-dev libpam-systemd \
				software-properties-common python-software-properties libnss-myhostname f2fs-tools"
			;;
			trusty)
			package_list="$package_list libnl-3-dev libnl-genl-3-dev software-properties-common python-software-properties f2fs-tools"
			;;
		esac

		# additional desktop packages
		if [[ $BUILD_DESKTOP == yes ]]; then
			# common packages
			package_list="$package_list xserver-xorg xserver-xorg-core xfonts-base xinit nodm x11-xserver-utils xfce4 lxtask xterm mirage radiotray wicd thunar-volman galculator \
			gtk2-engines gtk2-engines-murrine gtk2-engines-pixbuf libgtk2.0-bin gcj-jre-headless xfce4-screenshooter libgnome2-perl"
			# release specific desktop packages
			case $RELEASE in
				wheezy)
				package_list="$package_list mozo pluma iceweasel icedove"
				;;
				jessie)
				package_list="$package_list mozo pluma iceweasel libreoffice-writer libreoffice-java-common icedove"
				;;
				trusty)
				package_list="$package_list libreoffice-writer libreoffice-java-common thunderbird firefox gnome-icon-theme-full tango-icon-theme gvfs-backends"
				;;
			esac
			# hardware acceleration support packages
			# cache is not LINUXCONFIG and BRANCH specific, so installing anyway
			#if [[ $LINUXCONFIG == *sun* && $BRANCH != "next" ]] &&
			package_list="$package_list xorg-dev xutils-dev x11proto-dri2-dev xutils-dev libdrm-dev libvdpau-dev"
		fi

		# stage: install additional packages
		display_alert "Installing packages for" "Armbian" "info"
		eval 'LC_ALL=C LANG=C chroot $DEST/cache/sdcard /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y $apt_extra --no-install-recommends install $package_list"' \
			${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/debootstrap.log'} \
			${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Installing Armbian system..." 20 80'} \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}

		# DEBUG: print free space
		df -h | grep "$DEST/cache/" | tee -a $DEST/debug/debootstrap.log

		# stage: remove downloaded packages
		chroot $DEST/cache/sdcard /bin/bash -c "apt-get clean"

		# stage: make rootfs cache archive
		display_alert "Ending debootstrap process and preparing cache" "$RELEASE" "info"
		sync
		# the only reason to unmount here is compression progress display
		# based on rootfs size calculation
		umount -l $DEST/cache/sdcard/dev/pts
		umount -l $DEST/cache/sdcard/dev
		umount -l $DEST/cache/sdcard/proc
		umount -l $DEST/cache/sdcard/sys

		tar cp --directory=$DEST/cache/sdcard/ --exclude='./dev/*' --exclude='./proc/*' --exclude='./run/*' --exclude='./tmp/*' \
			--exclude='./sys/*' . | \
		pv -p -b -r -s $(du -sb $DEST/cache/sdcard/ | cut -f1) -N "$(basename $cache_fname)" | pigz > $cache_fname
	fi

} #############################################################################

# prepare_partitions
#
# creates image file, partitions and fs
# and mounts it to local dir
# FS-dependent stuff (boot and root fs partition types) happens here
#
prepare_partitions()
{
	display_alert "Preparing image file for rootfs" "$BOARD $RELEASE" "info"

	# Fixed image size is in 1M dd blocks (MiB)
	# to get size of block device /dev/sdX execute as root:
	# echo $(( $(blockdev --getsize64 /dev/sdX) / 1024 / 1024 ))
	if [[ $USE_F2FS_ROOT == yes && -z $FIXED_IMAGE_SIZE ]]; then
		display_alert "F2FS root needs user-defined SD card size" "FIXED_IMAGE_SIZE" "err"
		exit 1
	fi

	if [[ $USE_F2FS_ROOT == yes ]]; then
		display_alert "Building image with F2FS root filesystem. Make sure selected kernel version supports F2FS" "$CHOOSEN_KERNEL" "info"
	fi

	# possible partition combinations
	# ext4 root only (BOOTSIZE == 0 && USE_F2FS_ROOT != yes)
	# fat32 boot + ext4 root (BOOTSIZE > 0 && USE_F2FS_ROOT != yes)
	# fat32 boot + f2fs root (BOOTSIZE > 0; USE_F2FS_ROOT == yes)
	# ext4 boot + f2fs root (BOOTSIZE == 0; USE_F2FS_ROOT == yes)

	# declare makes local variables by default
	# if used inside a function
	# NOTE: mountopts string should always start with comma if not empty

	# array copying in old bash versions is tricky, so having filesystems as arrays
	# with attributes as keys is not a good idea
	declare -A parttype mkopts mkfs mountopts

	parttype[ext4]=ext4
	parttype[fat]=fat16
	parttype[f2fs]=ext4 # not a copy-paste error

	mkopts[ext4]='-q' # "-O journal_data_writeback" can be set here
	mkopts[fat]='-n boot'
#	mkopts[f2fs] is empty

	mkfs[ext4]=ext4
	mkfs[fat]=vfat
	mkfs[f2fs]=f2fs

	mountopts[ext4]=',commit=600'
#	mountopts[fat] is empty
#	mountopts[f2fs] is empty

	# stage: calculate rootfs size
	local rootfs_size=$(du -sm $DEST/cache/sdcard/ | cut -f1) # MiB
	display_alert "Current rootfs size" "$rootfs_size MiB" "info"
	if [[ -n $FIXED_IMAGE_SIZE && $FIXED_IMAGE_SIZE =~ ^[0-9]+$ ]]; then
		display_alert "Using user-defined image size" "$FIXED_IMAGE_SIZE MiB" "info"
		local sdsize=$FIXED_IMAGE_SIZE
		# basic sanity check
		if [[ $sdsize -lt $rootfs_size ]]; then
			display_alert "User defined image size is too small" "$sdsize <= $rootfs_size" "err"
			exit 1
		fi
	else
		local imagesize=$(( $rootfs_size + $OFFSET + $BOOTSIZE )) # MiB
		# Hardcoded overhead +30% for ext4 leaves ~10% free on root partition
		# extra 128 MiB for emergency swap file
		local sdsize=$(bc -l <<< "scale=0; ($imagesize * 1.3) / 1 + 128")
	fi

	# stage: create blank image
	display_alert "Creating blank image for rootfs" "$sdsize MiB" "info"
	dd if=/dev/zero bs=1M status=none count=$sdsize | pv -p -b -r -s $(( $sdsize * 1024 * 1024 )) | dd status=none of=$DEST/cache/tmprootfs.raw

	# stage: determine partition configuration
	# root
	if [[ $USE_F2FS_ROOT == yes ]]; then
		local rootfs=f2fs
	else
		local rootfs=ext4
	fi

	# boot
	if [[ $USE_F2FS_ROOT == yes && $BOOTSIZE == 0 ]]; then
		local bootfs=ext4
		BOOTSIZE=32 #MiB
	elif [[ $BOOTSIZE != 0 ]]; then
		local bootfs=fat
	fi

	# stage: calculate boot partition size
	BOOTSTART=$(($OFFSET * 2048))
	ROOTSTART=$(($BOOTSTART + ($BOOTSIZE * 2048)))
	BOOTEND=$(($ROOTSTART - 1))

	# stage: create partition table
	display_alert "Creating partitions" "${bootfs:+/boot: $bootfs }root: $rootfs" "info"
	parted -s $DEST/cache/tmprootfs.raw -- mklabel msdos
	if [[ $BOOTSIZE == 0 ]]; then
		parted -s $DEST/cache/tmprootfs.raw -- mkpart primary ${parttype[$rootfs]} ${ROOTSTART}s -1s
	else
		parted -s $DEST/cache/tmprootfs.raw -- mkpart primary ${parttype[$bootfs]} ${BOOTSTART}s ${BOOTEND}s
		parted -s $DEST/cache/tmprootfs.raw -- mkpart primary ${parttype[$rootfs]} ${ROOTSTART}s -1s
	fi

	# stage: mount image
	LOOP=$(losetup -f)
	if [[ -z $LOOP ]]; then
		# NOTE: very unlikely with this debootstrap process
		display_alert "Unable to find free loop device" "err"
		exit 1
	fi

	# NOTE: losetup -P option is not available in Trusty
	losetup $LOOP $DEST/cache/tmprootfs.raw
	partprobe $LOOP

	# stage: create fs
	if [[ $BOOTSIZE == 0 ]]; then
		eval mkfs.${mkfs[$rootfs]} ${mkopts[$rootfs]} ${LOOP}p1 ${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}
	else
		eval mkfs.${mkfs[$bootfs]} ${mkopts[$bootfs]} ${LOOP}p1 ${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}
		eval mkfs.${mkfs[$rootfs]} ${mkopts[$rootfs]} ${LOOP}p2 ${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}
	fi

	# stage: mount partitions and create proper fstab
	rm -f $DEST/cache/sdcard/etc/fstab
	if [[ $BOOTSIZE == 0 ]]; then
		mount ${LOOP}p1 $DEST/cache/mount/
		echo "/dev/mmcblk0p1 / ${parttype[$rootfs]} defaults,noatime,nodiratime,errors=remount-ro${mountopts[$rootfs]} 0 0" >> $DEST/cache/sdcard/etc/fstab
	else
		mount ${LOOP}p2 $DEST/cache/mount/
		echo "/dev/mmcblk0p2 / ${parttype[$rootfs]} defaults,noatime,nodiratime,errors=remount-ro${mountopts[$rootfs]} 0 0" >> $DEST/cache/sdcard/etc/fstab
		# create /boot on rootfs after it is mounted
		mkdir -p $DEST/cache/mount/boot/
		mount ${LOOP}p1 $DEST/cache/mount/boot/
		echo "/dev/mmcblk0p1 /boot ${parttype[$bootfs]} defaults${mountopts[$bootfs]} 0 0" >> $DEST/cache/sdcard/etc/fstab
	fi
	echo "tmpfs /tmp tmpfs defaults,rw,nosuid,nodev 0 0" >> $DEST/cache/sdcard/etc/fstab

} #############################################################################

# create_image
#
# finishes creation of image from cached rootfs
#
create_image()
{
	# stage: check for fat /boot workaround
	# using this method to avoid using another global variable
	local bootfstype=$(findmnt --target $DEST/cache/mount/boot -o FSTYPE -n)
	[[ $bootfstype == vfat ]] && local boot_workaround=yes

	# stage: rsync all except /boot if its filesystem is fat
	display_alert "Copying files to image" "tmprootfs.raw" "info"
	eval 'rsync -aHAXWh ${boot_workaround:+ --exclude="/boot/*"} --exclude="/dev/*" --exclude="/proc/*" --exclude="/run/*" --exclude="/tmp/*" \
		--exclude="/sys/*" --info=progress2,stats1 $DEST/cache/sdcard/ $DEST/cache/mount/'

	# stage: rsync /boot
	# needs other options for fat32 compatibility
	if [[ $boot_workaround == yes ]]; then
		display_alert "Copying files to /boot partition" "tmprootfs.raw" "info"
		rsync -rLtWh --info=progress2,stats1 $DEST/cache/sdcard/boot $DEST/cache/mount/boot
	fi

	# stage: fix u-boot script
	# needs rewriting and testing u-boot scripts
	# for other boards

	if [[ $BOOTSIZE != 0 && -f $DEST/cache/mount/boot/boot.scr ]]; then
		rm -f $DEST/cache/mount/boot/boot.scr
		sed -i 's/mmcblk0p1/mmcblk0p2/' $DEST/cache/mount/boot/boot.cmd
		# rely on rootfs type autodetect
		sed -i 's/rootfstype=ext4//' $DEST/cache/mount/boot/boot.cmd
		mkimage -C none -A arm -T script -d $DEST/cache/mount/boot/boot.cmd $DEST/cache/mount/boot/boot.scr > /dev/null 2>&1
	fi

	# DEBUG: print free space
	df -h | grep "$DEST/cache/" | tee -a $DEST/debug/debootstrap.log

	# stage: write u-boot
	write_uboot $LOOP

	# unmount /boot first, rootfs second, image file last
	if [[ $BOOTSIZE != 0 ]]; then umount -l $DEST/cache/mount/boot; fi
	umount -l $DEST/cache/mount/
	losetup -d $LOOP

	# # stage: create file name
	VER="${VER/-$LINUXFAMILY/}"
	VERSION=$VERSION" "$VER
	VERSION="${VERSION// /_}"
	VERSION="${VERSION//$BRANCH/}"
	VERSION="${VERSION//__/_}"

	if [[ $BUILD_DESKTOP = yes ]]; then
		VERSION=$VERSION"_desktop"
	fi

	mv $DEST/cache/tmprootfs.raw $DEST/cache/$VERSION.raw
	cd $DEST/cache/
	mkdir -p $DEST/images

	# stage: compressing or copying image file
	if [[ -n $FIXED_IMAGE_SIZE ]]; then
		display_alert "Copying image file" "$VERSION.raw" "info"
		mv -f $DEST/cache/$VERSION.raw $DEST/images/$VERSION.raw
		display_alert "Done building" "$DEST/images/$VERSION.raw" "info"
	else
		display_alert "Signing and compressing" "$VERSION.zip" "info"
		# stage: sign with PGP
		if [[ $GPG_PASS != "" ]]; then
			echo $GPG_PASS | gpg --passphrase-fd 0 --armor --detach-sign --batch --yes $VERSION.raw
			echo $GPG_PASS | gpg --passphrase-fd 0 --armor --detach-sign --batch --yes armbian.txt
		fi
		zip -FSq $DEST/images/$VERSION.zip $VERSION.raw* armbian.txt
		rm -f $VERSION.raw *.asc armbian.txt
		display_alert "Done building" "$DEST/images/$VERSION.zip" "info"
	fi

} #############################################################################

# unmount_on_exit
#
unmount_on_exit()
{
		umount -l $DEST/cache/sdcard/dev/pts >/dev/null 2>&1
		umount -l $DEST/cache/sdcard/dev >/dev/null 2>&1
		umount -l $DEST/cache/sdcard/proc >/dev/null 2>&1
		umount -l $DEST/cache/sdcard/sys >/dev/null 2>&1

		umount -l $DEST/cache/sdcard/ >/dev/null 2>&1

		umount -l $DEST/cache/mount/boot >/dev/null 2>&1
		umount -l $DEST/cache/mount/ >/dev/null 2>&1

		losetup -d $LOOP >/dev/null 2>&1

		exit 1

} #############################################################################