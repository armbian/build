enable_extension "grub"
export SERIALCON="tty1"                          # Cant reasonably expect UEFI stuff to have a serial console. Customize if otherwise.
export SKIP_BOOTSPLASH="yes"                     # No splash.
export UEFI_GRUB_TIMEOUT=${UEFI_GRUB_TIMEOUT:-1} # Default 1-second timeout for GRUB menu.
case "${BRANCH}" in

current)
	# This will force `unset KERNELSOURCE` later; no kernel will be built.
	# Instead, the distro's default linux-generic kernel will be installed.
	export DISTRO_GENERIC_KERNEL=yes
	;;

edge)
	export DISTRO_GENERIC_KERNEL=no
	export LINUXCONFIG="linux-uefi-${LINUXFAMILY}-${BRANCH}"
	export KERNELBRANCH="branch:linux-5.15.y"
	export KERNELPATCHDIR="uefi-${LINUXFAMILY}-${BRANCH}" # Might be empty.
	export KERNELDIR="linux-uefi-${LINUXFAMILY}"          # Avoid sharing a source tree with others, until we know it's safe.
	function add_host_dependencies__libelf_and_libfdt() { # Conditional extension: when building the UEFI kernels, make sure some host-side libs are available
		export EXTRA_BUILD_DEPS="${EXTRA_BUILD_DEPS} libfdt-dev libelf-dev"
	}
	;;
esac
