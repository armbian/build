export SERIALCON="tty1"                          # Cant reasonably expect UEFI stuff to have a serial console. Customize if otherwise.
export SKIP_BOOTSPLASH="yes"                     # No splash.
export UEFI_GRUB_TIMEOUT=${UEFI_GRUB_TIMEOUT:-3} # Default 3-seconds timeout for GRUB menu.
export BOARD_FIRMWARE_INSTALL="-full"            # Install full firmware for UEFI boards
case "${BRANCH}" in

	legacy)
		# This will force `unset KERNELSOURCE` later; no kernel will be built.
		# Instead, the distro's default linux-generic kernel will be installed.
		export DISTRO_GENERIC_KERNEL=yes
		;;

	current)
		export DISTRO_GENERIC_KERNEL=no
		export LINUXCONFIG="linux-uefi-${LINUXFAMILY}-${BRANCH}"
		export KERNELBRANCH="branch:linux-5.15.y"
		export KERNELPATCHDIR="uefi-${LINUXFAMILY}-${BRANCH}" # Might be empty.
		export KERNELDIR="linux-uefi-${LINUXFAMILY}"          # Avoid sharing a source tree with others, until we know it's safe.
		;;

	edge)
		export DISTRO_GENERIC_KERNEL=no
		export LINUXCONFIG="linux-uefi-${LINUXFAMILY}-${BRANCH}"
		export KERNELBRANCH="branch:linux-6.0.y"
		export KERNELPATCHDIR="uefi-${LINUXFAMILY}-${BRANCH}" # Might be empty.
		export KERNELDIR="linux-uefi-${LINUXFAMILY}"          # Avoid sharing a source tree with others, until we know it's safe.
		;;
esac
