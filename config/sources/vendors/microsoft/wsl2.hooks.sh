# enable output-vhdx, so image files for wsl2 can be used directly as Hyper-V virtual machines as well.
enable_extension "image-output-vhdx" # Use .vhdx dynamic output, for Hyper-V (not Azure 1024-aligned static vhd)

# A separate LINUXFAMILY and thus kernel .debs for wsl2; one day we might consider merging wsl2/hyperv patches into generic uefi
function post_family_config__wsl2() {
	: "${LINUXFAMILY:?"LINUXFAMILY not set"}"
	declare -g LINUXFAMILY="wsl2-${LINUXFAMILY}"
	declare -g LINUXCONFIG="linux-${LINUXFAMILY}-${BRANCH}"

	# We _definitely_ don't want any extra drivers in these kernels -- it's purely a VM/Hyper-V thing
	declare -g -r EXTRAWIFI="no" # readonly global
}

function post_family_config_branch_current__wsl2() {
	declare -g KERNEL_MAJOR_MINOR="6.1"                                      # Major and minor versions of this kernel. For mainline caching.
	declare -g KERNELBRANCH="branch:linux-6.1.y"                             # Branch or tag to build from. It should match MAJOR_MINOR
	declare -g KERNELPATCHDIR="archive/${LINUXFAMILY}-${KERNEL_MAJOR_MINOR}" # Microsoft patches
	display_alert "Using mainline kernel ${KERNELBRANCH} for" "${BOARD}" "info"
}

function post_family_config_branch_edge__wsl2() {
	declare -g KERNEL_MAJOR_MINOR="6.6"                                      # Major and minor versions of this kernel. For mainline caching.
	declare -g KERNELBRANCH="branch:linux-6.6.y"                             # Branch or tag to build from. It should match MAJOR_MINOR
	declare -g KERNELPATCHDIR="archive/${LINUXFAMILY}-${KERNEL_MAJOR_MINOR}" # Microsoft patches
	display_alert "Using mainline kernel ${KERNELBRANCH} for" "${BOARD}" "info"
}
