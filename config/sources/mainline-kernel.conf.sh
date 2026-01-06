#
# SPDX-License-Identifier: GPL-2.0
# Copyright (c) 2023 Ricardo Pardini <ricardo@pardini.net>
# This file is a part of the Armbian Build Framework https://github.com/armbian/build/
#

# Shared versioning logic for Armbian mainline kernels.
function mainline_kernel_decide_version__upstream_release_candidate_number() {
	[[ -n "${KERNELBRANCH}" ]] && return 0           # if already set, don't touch it; that way other hooks can run in any order
	if [[ "${KERNEL_MAJOR_MINOR}" == "6.19" ]]; then # @TODO: roll over to next MAJOR.MINOR and MAJOR.MINOR-rc1 when it is released
		declare -g KERNELBRANCH="tag:v6.19-rc4"
		display_alert "mainline-kernel: upstream release candidate" "Using KERNELBRANCH='${KERNELBRANCH}' for KERNEL_MAJOR_MINOR='${KERNEL_MAJOR_MINOR}'" "info"
	fi
}

### Later than normal hooks, for emergencies / locking versions for release / etc. Use mainline_kernel_decide_version__600 or higher.

## Example: "6.6.7 was recently released with changes that break our drivers/patches/souls. Let's Lock 6.6 to 6.6.6 until we've time to fix it."
#function mainline_kernel_decide_version__600_lock_6.6_to_6.6.6() {
#	[[ "${KERNEL_MAJOR_MINOR}" != "6.6" ]] && return 0 # only for 6.6
#	declare -g KERNELBRANCH="tag:v6.6.6"
#	display_alert "mainline-kernel: locked version for 6.6 kernel" "Using fixed version for 6.6 KERNELBRANCH='${KERNELBRANCH}'" "info"
#}

### Later-than-usual hooks, for changing parameters after the hooks above have run. use mainline_kernel_decide_version__750 or higher.

# # Example: 6.7-rc7 was released by Linus, but kernel.org git and google git mirrors took a while to catch up; change the source to pull directly from Linus.
# # This was necessary for a few days in late December 2023, but no longer; tag was pushed on 28/Dec/2023.
# function mainline_kernel_decide_version__750_use_torvalds_for_6.7-rc7() {
# 	if [[ "${KERNELBRANCH}" == 'tag:v6.7-rc7' ]]; then
# 		display_alert "Using Linus kernel repo for 6.7-rc7" "${KERNELBRANCH}" "warn"
# 		declare -g KERNELSOURCE="https://github.com/torvalds/linux.git"
# 		display_alert "mainline-kernel: missing torvalds tag on 6.7-rc7" "Using KERNELSOURCE='${KERNELSOURCE}' for KERNELBRANCH='${KERNELBRANCH}'" "info"
# 	fi
# }

### Last hooks, defaults to branch if not set by previous hooks. Use mainline_kernel_decide_version__900 or higher.
function mainline_kernel_decide_version__900_defaults() {
	[[ -n "${KERNELBRANCH}" ]] && return 0                         # if already set, don't touch it; that way other hooks can run in any order
	declare -g KERNELBRANCH="branch:linux-${KERNEL_MAJOR_MINOR}.y" # default to stable branch
	display_alert "mainline-kernel: default to branch / rolling stable version" "Using KERNELBRANCH='${KERNELBRANCH}' for KERNEL_MAJOR_MINOR='${KERNEL_MAJOR_MINOR}'" "info"
}
