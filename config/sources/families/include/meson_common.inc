#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/
#
ARCH=armhf
LINUXFAMILY=meson
KERNEL_IMAGE_TYPE='uImage'
KERNEL_INSTALL_TYPE='uinstall'
SRC_LOADADDR='LOADADDR=0x00208000'
NAME_KERNEL=uImage

SERIALCON="ttyAML0"

CPUMIN=504000
CPUMAX=1632000
GOVERNOR=ondemand

SKIP_BOOTSPLASH="yes"

case $BRANCH in

	current)
		declare -g KERNEL_MAJOR_MINOR="6.12"
		declare -g KERNELBRANCH="tag:v6.12.28" # frozen on this version
		;;
esac

family_tweaks_bsp() {
	mkdir -p "$destination/etc/X11/xorg.conf.d"
	cat <<- EOF > "$destination/etc/X11/xorg.conf.d/02-driver.conf"
		Section "OutputClass"
			Identifier "Amlogic"
			MatchDriver "meson"
			Driver "modesetting"
			Option "PrimaryGPU" "true"
		EndSection
	EOF
}
