ARCH=armhf
LINUXFAMILY=meson
KERNEL_IMAGE_TYPE=uImage
SRC_LOADADDR='LOADADDR=0x00208000'

SERIALCON="ttyAML0"

CPUMIN=504000
CPUMAX=1632000
GOVERNOR=ondemand

SKIP_BOOTSPLASH="yes"

case $BRANCH in
	current)

		KERNELBRANCH="branch:linux-5.15.y"
		KERNELPATCHDIR='meson-'$BRANCH

		;;

	edge)

		KERNELBRANCH="branch:linux-6.1.y"
		KERNELPATCHDIR='meson-'$BRANCH

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
