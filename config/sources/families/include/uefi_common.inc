enable_extension "grub"
export SERIALCON="tty1"                          # Cant reasonably expect UEFI stuff to have a serial console. Customize if otherwise.
export SKIP_BOOTSPLASH="yes"                     # No splash.
export UEFI_GRUB_TIMEOUT=${UEFI_GRUB_TIMEOUT:-1} # Default 1-second timeout for GRUB menu.
export BOARD_FIRMWARE_INSTALL="-full"            # Install full firmware for UEFI boards
case "${BRANCH}" in

	ddk)
		# This will force `unset KERNELSOURCE` later; no kernel will be built.
		# Instead, the distro's default linux-generic kernel will be installed.
		export DISTRO_GENERIC_KERNEL=yes
		;;

	current)
		export DISTRO_GENERIC_KERNEL=no
		export LINUXCONFIG="linux-uefi-${LINUXFAMILY}-${BRANCH}"
		export KERNEL_MAJOR_MINOR="5.15"                      # Major and minor versions of this kernel. For mainline caching.
		export KERNELBRANCH="branch:linux-5.15.y"             # Branch or tag to build from. It should match MAJOR_MINOR
		export KERNELPATCHDIR="uefi-${LINUXFAMILY}-${BRANCH}" # Might be empty.
		;;

	edge)
		export DISTRO_GENERIC_KERNEL=no
		export LINUXCONFIG="linux-uefi-${LINUXFAMILY}-${BRANCH}"
		export KERNEL_MAJOR_MINOR="5.19"                      # Major and minor versions of this kernel. For mainline caching.
		export KERNELBRANCH="branch:linux-5.19.y"             # Branch or tag to build from. It should match MAJOR_MINOR
		export KERNELPATCHDIR="uefi-${LINUXFAMILY}-${BRANCH}" # Might be empty.
		;;
esac
