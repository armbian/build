#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/
#

declare -g ARCH="arm64"
declare -g OVERLAY_DIR="/boot/dtb/ti/overlay"
declare -g BOOTSCRIPT="boot-k3.cmd:uEnv.txt"
declare -g SPD_OPTEED="SPD=opteed"

declare -g INSTALL_HEADERS="yes"

declare -g TI_PACKAGES=()
if [[ "${CC33XX_SUPPORT}" == "yes" ]] ; then
	if [[ "${RELEASE}" == "trixie" || "${RELEASE}" == "noble" ]] ; then
		TI_PACKAGES+=("cc33xx-fw" "cc33xx-target-scripts" "cc33conf" "cc33calibrator")
	fi
fi

enable_extension "ti-debpkgs"
enable_extension "apa"

case "${BRANCH}" in

	edge)	# experimental (limited testing): uses latest bleeding-edge upstream mainline version

		# KERNELSOURCE defined in mainline-config.sh
		# KERNELBRANCH defined in mainline-kernel.conf.sh
		declare -g KERNEL_MAJOR_MINOR="6.18"							# needs updating with each minor kernel release
		declare -g KERNEL_DESCRIPTION="Latest upstream mainline kernel"
		declare -g ATFBRANCH="branch:master"
		declare -g OPTEE_BRANCH="branch:master"
		declare -g TI_LINUX_FIRMWARE_BRANCH="branch:ti-linux-firmware"
		declare -g BOOTSOURCE="https://github.com/u-boot/u-boot"
		declare -g BOOTBRANCH="branch:master"
		;;

esac

ATF_PLAT="k3"
ATF_TARGET_MAP="PLAT=$ATF_PLAT TARGET_BOARD=$ATF_BOARD ${SPD_OPTEED} ${ATF_ARGS} all;;build/$ATF_PLAT/$ATF_BOARD/release/bl31.bin:bl31.bin ${EXTRA_ATF_TARGETS}"

UBOOT_TARGET_MAP="BL31=bl31.bin ${EXTRA_BOOT_ARGS} TEE=${SRC}/cache/sources/optee-os/out/arm-plat-k3/core/tee-raw.bin BINMAN_INDIRS=${SRC}/cache/sources/ti-linux-firmware all;;tiboot3.bin ${SYSFW_FILE:+sysfw.itb} tispl.bin u-boot.img"

# To match what our current SDK produces
BOOT_FS_LABEL="boot"
ROOT_FS_LABEL="root"

function add_host_dependencies__k3_python3_dep() {
	display_alert "Preparing K3 U-Boot host-side dependencies" "${EXTENSION}" "info"
	declare -g EXTRA_BUILD_DEPS="${EXTRA_BUILD_DEPS} python3-yaml python3-jsonschema yamllint python3-cryptography python3-pyelftools python3-setuptools"
}

function compile_k3_bootgen() {
	# Source code checkout
	(fetch_from_repo "https://github.com/TexasInstruments/ti-linux-firmware" "ti-linux-firmware" ${TI_LINUX_FIRMWARE_BRANCH})

	if [[ "${BOOT_SOC}" != "am62l" ]]; then
		pushd ${SRC}/cache/sources/u-boot-worktree/${BOOTDIR}/${BOOTBRANCH##*:} || exit
		run_host_command_logged make -j$(nproc) CROSS_COMPILE=arm-linux-gnueabi- ARCH=arm O=build-r5 ${TIBOOT3_BOOTCONFIG}
		run_host_command_logged make -j$(nproc) CROSS_COMPILE=arm-linux-gnueabi- ARCH=arm O=build-r5 BINMAN_INDIRS=${SRC}/cache/sources/ti-linux-firmware
		popd
	fi
}

function compile_k3_optee() {
	(fetch_from_repo "https://github.com/OP-TEE/optee_os.git" "optee-os" ${OPTEE_BRANCH})
	pushd ${SRC}/cache/sources/optee-os || exit
	run_host_command_logged make -j$(nproc) CROSS_COMPILE=arm-linux-gnueabihf- CFG_ARM64_core=y PLATFORM=${OPTEE_PLATFORM} ${OPTEE_ARGS}
	popd
}

function pre_config_uboot_target__build_first_stage() {
	# Compile first stage bootloader
	compile_k3_optee
	compile_k3_bootgen

	if [[ "${BOOT_SOC}" != "am62l" ]]; then
		cp ${SRC}/cache/sources/u-boot-worktree/${BOOTDIR}/${BOOTBRANCH##*:}/build-r5/${TIBOOT3_FILE} tiboot3.bin
		cp ${SRC}/cache/sources/u-boot-worktree/${BOOTDIR}/${BOOTBRANCH##*:}/build-r5/${SYSFW_FILE} sysfw.itb || true
	fi
}

function post_uboot_custom_postprocess__update_uboot_names() {
	cp ${TISPL_FILE} tispl.bin || true
	cp ${UBOOT_FILE} u-boot.img || true
}

function pre_prepare_partitions() {
	# Filesystem must fill partition regardless of alignment
	mkopts[fat]='-a'
}

function post_create_partitions() {
	display_alert "Setting boot partition flags on" "${SDCARD}.raw" "debug"

	# ROM is very particular about boot flags
	run_host_command_logged parted "${SDCARD}".raw set 1 boot on
	run_host_command_logged parted "${SDCARD}".raw set 1 bls_boot off
}

function format_partitions() {
	# ROM is very particular about partition IDs
	run_host_command_logged sfdisk --part-type ${LOOP} 1 e
}

function write_uboot_platform() {
	cp $1/tiboot3.bin ${MOUNT}/boot
	cp $1/sysfw.itb ${MOUNT}/boot || true
	cp $1/tispl.bin ${MOUNT}/boot
	cp $1/u-boot.img ${MOUNT}/boot
}
