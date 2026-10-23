#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2026 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/
#

# Rockchip BSP kernel from armbian/linux-rockchip; one place for all families that use it.
# Usage: rockchip_vendor_kernel_config [KERNELPATCHDIR prefix, default rk35xx-vendor]
function rockchip_vendor_kernel_config() {
	case "${BRANCH}" in
		vendor)
			declare -g KERNEL_MAJOR_MINOR="6.1" # Major and minor versions of this kernel.
			declare -g KERNELBRANCH='branch:rk-6.1-rkr7.2'
			;;
		vendor-next)
			declare -g KERNEL_MAJOR_MINOR="6.12" # Major and minor versions of this kernel.
			declare -g KERNELBRANCH='branch:rk-6.12-rkr1'
			;;
		*)
			exit_with_error "rockchip_vendor_kernel_config: unknown vendor BRANCH '${BRANCH}'"
			;;
	esac
	declare -g KERNELSOURCE='https://github.com/armbian/linux-rockchip.git'
	declare -g KERNELPATCHDIR="${1:-"rk35xx-vendor"}-${KERNEL_MAJOR_MINOR}"
	declare -g -i KERNEL_GIT_CACHE_TTL=120 # 2 minutes; this is a high-traffic repo
}
