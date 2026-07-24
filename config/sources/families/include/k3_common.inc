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
declare -g CLEAN_LEVEL="make-atf,make-uboot"

declare -g INSTALL_HEADERS="yes"

[[ -v "TI_PACKAGES" ]] || declare -g TI_PACKAGES=()
if [[ "${CC33XX_SUPPORT}" == "yes" ]]; then
	if [[ "${RELEASE}" == "trixie" || "${RELEASE}" == "noble" ]]; then
		TI_PACKAGES+=("cc33xx-fw" "cc33xx-target-scripts" "cc33conf" "cc33calibrator")
	fi
fi

enable_extension "ti-debpkgs"
enable_extension "apa"

case "${BRANCH}" in

	edge) # experimental (limited testing): uses latest bleeding-edge upstream mainline version

		# KERNELSOURCE defined in mainline-config.sh
		# KERNELBRANCH defined in mainline-kernel.conf.sh
		declare -g KERNEL_MAJOR_MINOR="6.18" # needs updating with each minor kernel release
		declare -g KERNEL_DESCRIPTION="Latest upstream mainline kernel"
		declare -g ATFBRANCH="branch:master"
		declare -g OPTEE_BRANCH="branch:master"
		declare -g TI_LINUX_FIRMWARE_BRANCH="branch:ti-linux-firmware"
		declare -g BOOTSOURCE="https://github.com/u-boot/u-boot"
		declare -g BOOTBRANCH="branch:master"
		;;

esac

ATF_TARGET_MAP="PLAT=${ATF_PLAT} TARGET_BOARD=${ATF_BOARD} SPD=opteed ${ATF_ARGS} all;;build/${ATF_PLAT}/${ATF_BOARD}/release/bl31.bin:bl31.bin ${EXTRA_ATF_TARGETS}"

UBOOT_TARGET_MAP="BL31=bl31.bin ${EXTRA_BOOT_ARGS} TEE=${SRC}/cache/sources/optee-os/out/arm-plat-k3/core/tee-pager_v2.bin BINMAN_INDIRS=${SRC}/cache/sources/ti-linux-firmware all;;tiboot3.bin ${SYSFW_FILE:+sysfw.itb} tispl.bin u-boot.img"

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

		# Build the R5 first-stage SPL (tiboot3) with GCC 13. GCC 14 (the Trixie
		# default) produces oversized SPL code that overruns CONFIG_SPL_SIZE_LIMIT
		# on am62p/am62-lp; GCC 13 is smaller and fits. Passed as CC (u-boot Kbuild
		# honours a command-line CC); CROSS_COMPILE stays for binutils. Needs
		# gcc-13-arm-linux-gnueabi (soft-float) in the build image.
		declare r5_cc="CC=arm-linux-gnueabi-gcc-13"
		# Be certain the pinned compiler is present and really is GCC 13: fail
		# early and clearly rather than let a missing binary surface as a cryptic
		# mid-build error, and never silently fall back to the default GCC (which
		# would reintroduce the SPL oversize).
		declare r5_gcc_major
		r5_gcc_major="$(arm-linux-gnueabi-gcc-13 -dumpversion 2>/dev/null | cut -d. -f1 || true)"
		[[ "${r5_gcc_major}" == "13" ]] || exit_with_error "K3 R5 SPL requires arm-linux-gnueabi-gcc-13" "found version '${r5_gcc_major:-none}'"
		display_alert "K3 R5 SPL first-stage compiler" "arm-linux-gnueabi-gcc-13 (GCC ${r5_gcc_major})" "info"
		run_host_command_logged make -j$(nproc) CROSS_COMPILE=arm-linux-gnueabi- ${r5_cc} ARCH=arm O=build-r5 ${TIBOOT3_BOOTCONFIG}

		# Per-config R5 SPL size handling, on top of the GCC 13 build above. The
		# vendor R5 defconfigs overrun CONFIG_SPL_SIZE_LIMIT; the remedy depends on
		# the SoC's SRAM layout (see CONFIG_CUSTOM_SYS_INIT_SP_ADDR vs the limit).
		# Only tiboot3 (R5 first stage) is affected; the A53 SPL and u-boot proper
		# are untouched.
		declare r5_config_changed="no"
		case "${TIBOOT3_BOOTCONFIG}" in
			am62px_evm_r5_defconfig)
				# AM62Px: SPL_SIZE_LIMIT 0x3C000, but the stack pointer (SRAM top)
				# is at 0x43c4a7f0 -> ~58 KB of unused SRAM above the limit. The
				# overrun is only a few KB (excess 0x1bee), so raise the caps into
				# that headroom and keep the (unused-by-us but functional) SPI +
				# SPI-NAND boot paths. New top 0x43c40000 stays below the stack.
				display_alert "$BOARD" "Raising am62p R5 SPL size limit into available SRAM headroom" "info"
				run_host_command_logged scripts/config --file build-r5/.config \
					--set-val CONFIG_SPL_SIZE_LIMIT 0x40000 \
					--set-val CONFIG_SPL_MAX_SIZE 0x3F000
				r5_config_changed="yes"
				;;
			am62x_lpsk_r5_defconfig)
				# AM625: SPL_SIZE_LIMIT (0x3A7F0) already sits at the stack pointer
				# (base+0x3A7F0), with BSS just above at 0x43c3b000 - no SRAM to
				# raise into, and GCC 13 does not reclaim enough (excess ~0x48d0).
				# am62x_lpsk = am62x_evm (which fits) + a SPI-NAND boot stack the
				# board needs, so instead drop the inherited-but-unused SPI-NOR boot
				# stack: Armbian boots tiboot3 from SD/eMMC, and SPI-NAND is kept.
				# The Cadence QSPI controller and MTD_SPI_NAND stay (SPI-NAND still
				# works); only the SPI-NOR chip drivers + spi-nor framework and the
				# YMODEM UART-recovery loader are removed. olddefconfig cascades deps.
				display_alert "$BOARD" "Dropping unused SPI-NOR boot stack from am62-lp R5 SPL to fit SRAM (keeping SPI-NAND)" "info"
				run_host_command_logged scripts/config --file build-r5/.config \
					--disable CONFIG_SPL_SPI_FLASH_SUPPORT \
					--disable CONFIG_SPL_SPI_LOAD \
					--disable CONFIG_SPL_DM_SPI_FLASH \
					--disable CONFIG_SPL_SPI_FLASH_SFDP_SUPPORT \
					--disable CONFIG_DM_SPI_FLASH \
					--disable CONFIG_SPI_FLASH_SFDP_SUPPORT \
					--disable CONFIG_SPI_FLASH_SOFT_RESET \
					--disable CONFIG_SPI_FLASH_SOFT_RESET_ON_BOOT \
					--disable CONFIG_SPI_FLASH_SPANSION \
					--disable CONFIG_SPI_FLASH_S28HX_T \
					--disable CONFIG_SPL_YMODEM_SUPPORT
				r5_config_changed="yes"
				;;
		esac
		if [[ "${r5_config_changed}" == "yes" ]]; then
			run_host_command_logged make -j$(nproc) CROSS_COMPILE=arm-linux-gnueabi- ${r5_cc} ARCH=arm O=build-r5 olddefconfig
		fi

		run_host_command_logged make -j$(nproc) CROSS_COMPILE=arm-linux-gnueabi- ${r5_cc} ARCH=arm O=build-r5 BINMAN_INDIRS=${SRC}/cache/sources/ti-linux-firmware
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
	# Rename a board's override output onto tispl.bin/u-boot.img, but only if it
	# was actually produced, and never let the copy be fatal. Both an absent
	# source and a failing cp trip Armbian's ERR trap, so guard on the file
	# existing (an 'if', not '[[ -f ]] && cp', whose false test returns 1) and
	# keep '|| true' on the cp. This matters because newer u-boot (mainline
	# 2026.07 / recent TI SDK) renamed the GP outputs to ti-spl_unsigned.fit.*
	# (source absent -> skip, fall back to binman's standard tispl.bin), and on
	# GP parts binman can make the *_unsigned image and tispl.bin the same file,
	# so 'cp src dst' errors with "are the same file" (present -> tolerate).
	if [[ -f "${TISPL_FILE}" ]]; then cp "${TISPL_FILE}" tispl.bin || true; fi
	if [[ -f "${UBOOT_FILE}" ]]; then cp "${UBOOT_FILE}" u-boot.img || true; fi
	return 0
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
