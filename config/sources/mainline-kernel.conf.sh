#
# SPDX-License-Identifier: GPL-2.0
# Copyright (c) 2023 Ricardo Pardini <ricardo@pardini.net>
# This file is a part of the Armbian Build Framework https://github.com/armbian/build/
#

# Shared versioning logic for Armbian mainline kernels.
function mainline_kernel_decide_version__upstream_release_candidate_number() {
	[[ -n "${KERNELBRANCH}" ]] && return 0          # if already set, don't touch it; that way other hooks can run in any order
	if [[ "${KERNEL_MAJOR_MINOR}" == "6.7" ]]; then # @TODO: roll over to 6.8 and v6.8-rc1 when it is released, which should be around Sunday, 2024-01-21 - see https://deb.tandrin.de/phb-crystal-ball.htm
		declare -g KERNELBRANCH="tag:v6.7-rc7"
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

# This is a _special case_ handling for a specific kernel -rc release problem during end-of-year vacations.
# It should be removed once the problem is fixed at kernel.org / google git mirrors.
# https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git is missing 6.7-rc7 tag; use Linus GH repo instead.
# Attention: this does not support/respect git mirror... hopefully kernel.org catches up soon and we can remove this.
function mainline_kernel_decide_version__750_use_torvalds_for_6.7-rc7() {
	if [[ "${KERNELBRANCH}" == 'tag:v6.7-rc7' ]]; then
		display_alert "Using Linus kernel repo for 6.7-rc7" "${KERNELBRANCH}" "warn"
		declare -g KERNELSOURCE="https://github.com/torvalds/linux.git"
		display_alert "mainline-kernel: missing torvalds tag on 6.7-rc7" "Using KERNELSOURCE='${KERNELSOURCE}' for KERNELBRANCH='${KERNELBRANCH}'" "info"
	fi
}

### Last hooks, defaults to branch if not set by previous hooks. Use mainline_kernel_decide_version__900 or higher.
function mainline_kernel_decide_version__900_defaults() {
	[[ -n "${KERNELBRANCH}" ]] && return 0                         # if already set, don't touch it; that way other hooks can run in any order
	declare -g KERNELBRANCH="branch:linux-${KERNEL_MAJOR_MINOR}.y" # default to stable branch
	display_alert "mainline-kernel: default to branch / rolling stable version" "Using KERNELBRANCH='${KERNELBRANCH}' for KERNEL_MAJOR_MINOR='${KERNEL_MAJOR_MINOR}'" "info"
}
