#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

#--------------------------------------------------------------------------------------------------------------------------------
# fingerprint_image <out_txt_file> [image_filename]
# Saving build summary to the image
#--------------------------------------------------------------------------------------------------------------------------------
function fingerprint_image() {
	cat <<- EOF > "${1}"
		---------------------------------------------------------------------------
		Generated with Armbian(tm) build framework https://github.com/armbian/build
		---------------------------------------------------------------------------
		Vendor:         ${VENDOR}
		Revision:       $REVISION
		Board:          ${BOARD^}
		Kernel:         Linux ${IMAGE_INSTALLED_KERNEL_VERSION} ($BRANCH)
		Build date:     $(date +'%d.%m.%Y')
		Sources:        ${BUILD_REPOSITORY_URL}
		Sources rev:    ${BUILD_REPOSITORY_COMMIT}
		Authors:        https://www.armbian.com/authors
		Maintainer:     ${MAINTAINER} <$MAINTAINERMAIL>
		Support:        ${VENDORSUPPORT}
	EOF

	if [ -n "$2" ]; then
		cat <<- EOF >> "${1}"
			---------------------------------------------------------------------------
			Partitioning configuration: $IMAGE_PARTITION_TABLE offset: $OFFSET
			Boot partition type: ${BOOTFS_TYPE:-(none)} ${BOOTSIZE:+"(${BOOTSIZE} MB)"}
			Root partition type: $ROOTFS_TYPE ${FIXED_IMAGE_SIZE:+"(${FIXED_IMAGE_SIZE} MB)"}

			CPU configuration: $CPUMIN - $CPUMAX with $GOVERNOR
			---------------------------------------------------------------------------
			Verify GPG signature:
			gpg --verify $2.img.xz.asc

			Verify image file integrity:
			sha256sum --check $2.img.xz.sha

			Prepare SD card (four methods):
			xzcat $2.img.xz | pv | dd of=/dev/mmcblkX bs=1M
			dd if=$2.img of=/dev/mmcblkX bs=1M
			balena-etcher $2.img.xz -d /dev/mmcblkX
			balena-etcher $2.img -d /dev/mmcblkX
		EOF
	fi

	cat <<- EOF >> "${1}"
		---------------------------------------------------------------------------
		$(cat "${SRC}"/LICENSE)
	EOF
}
