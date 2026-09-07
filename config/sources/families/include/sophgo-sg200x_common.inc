#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2026 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/
#
# Common configuration for the Sophgo SG200x families. Sourced from both
# sophgo-sg200x-arm64.conf and sophgo-sg200x-riscv64.conf, which set ARCH and
# LINUXFAMILY first.
#

declare -g GOVERNOR="performance"
declare -g SERIALCON="ttyS0"

# ---------------------------------------------------------------------------
# Kernel
# ---------------------------------------------------------------------------

# Mainline plus the out-of-tree Sophgo patch series; one series for both
# architectures.
case "${BRANCH}" in

	edge)
		declare -g KERNEL_MAJOR_MINOR="7.1"
		declare -g LINUXCONFIG="linux-${LINUXFAMILY}-edge"
		;;

	bleedingedge)
		declare -g KERNEL_MAJOR_MINOR="7.2"
		declare -g LINUXCONFIG="linux-${LINUXFAMILY}-bleedingedge"
		;;

	*)
		exit_with_error "sophgo-sg200x: unsupported BRANCH" "${BRANCH}"
		;;

esac

declare -g KERNELPATCHDIR="archive/sophgo-sg200x-${KERNEL_MAJOR_MINOR}" # Don't use symlinks.

# Wi-Fi comes from the sophgo-sg200x-aic8800 extension.
declare -g EXTRAWIFI="no"

declare -g OVERLAY_PREFIX="sg2000"

# ---------------------------------------------------------------------------
# Bootloader sources
# ---------------------------------------------------------------------------

# Vendor U-Boot. The BootROM only loads a file named fip.bin from the first FAT
# partition.
declare -g BOOTSOURCE="https://github.com/sophgo/u-boot-2021.10"
declare -g BOOTDIR="u-boot-sophgo-sg200x"
declare -g BOOTBRANCH="commit:bb7496c2dfded43921695bf49c23da28381f8960" # sg200x-dev, 2026-06-30
declare -g BOOTPATCHDIR="u-boot-sophgo-sg200x"

# The FSBL needs u-boot.bin, so it is built from uboot_custom_postprocess()
# rather than compile_atf(), which runs first.
declare -g ATFSOURCE="none"

declare -g SOPHGO_FSBL_REPO="${SOPHGO_FSBL_REPO:-https://github.com/sophgo/fsbl}"
declare -g SOPHGO_FSBL_REF="${SOPHGO_FSBL_REF:-commit:3c47dfc743ad6cee06bca7161b352673e5c63356}" # sg200x-dev, 2026-06-30

# RISC-V only: fills fip.bin's monitor slot, where ARM uses a prebuilt bl31.bin.
declare -g SOPHGO_OPENSBI_REPO="${SOPHGO_OPENSBI_REPO:-https://github.com/sophgo/opensbi}"
declare -g SOPHGO_OPENSBI_REF="${SOPHGO_OPENSBI_REF:-commit:6766e9cc96df51cde91540f9a15f291bf843b682}" # sg200x-dev, 2025-01-24

# Builds the FSBL for 1050MHz instead of the 850MHz default, and folds the
# setting into the u-boot artifact hash so both can share the cache.
declare -g SOPHGO_CPU_OVERDRIVE="${SOPHGO_CPU_OVERDRIVE:-yes}"
declare -g UBOOT_HASH_EXTRA="${UBOOT_HASH_EXTRA:-} sophgo-cpu-overdrive-${SOPHGO_CPU_OVERDRIVE}"

# The destination has to be boot.cmd: the framework runs mkimage only
# "if [[ -f /boot/boot.cmd ]]".
declare -g BOOTSCRIPT="boot-sophgo-sg200x.cmd:boot.cmd"

# ---------------------------------------------------------------------------
# Vendor SDK identity
# ---------------------------------------------------------------------------

# The duo-buildroot-sdk-v2 project whose board files we vendored.
declare -g SOPHGO_CVI_CHIP="sg2000"
declare -g SOPHGO_CVI_CHIP_ARCH="CV181X"
declare -g SOPHGO_CVI_DDR_CFG="ddr3_1866_x16"
declare -g SOPHGO_CVI_PANEL="MIPI_panel_milkv_8hd"

# Under BOOTPATCHDIR, every file of which artifact-uboot.sh hashes into the
# u-boot artifact version.
declare -g SOPHGO_CVI_FILES_DIR="${SRC}/patch/u-boot/${BOOTPATCHDIR}/cvitek-board-files"

# One image serves both media: the SD bootloader ships as /boot/fip.bin, the
# eMMC one beside it as fip-emmc.bin, which nothing boots.

# The vendored board files are named after the core. The _sd/_emmc suffix is
# appended per u-boot target by sophgo_sg200x_select_build_storage().
case "${ARCH}" in

	arm64)
		declare -g SOPHGO_CVI_PROJECT_PREFIX="sg2000_milkv_duos_glibc_arm64"
		declare -g SOPHGO_CVI_BOARD_PREFIX="milkv_duos_glibc_arm64"
		declare -g SOPHGO_CVI_FILES_VARIANT="arm64"
		# U-Boot 2021.10 has no arch/arm64.
		declare -g SOPHGO_CVI_UBOOT_DTS_DIR="arch/arm/dts"
		declare -g SOPHGO_CVI_UBOOT_ARCH="arm64"
		# Also selects the prebuilt bl31.bin for fip.bin's monitor slot.
		declare -g SOPHGO_FSBL_ARCH="arm64"
		;;

	riscv64)
		# musl is the SDK's naming; the Armbian userspace is glibc either way.
		declare -g SOPHGO_CVI_PROJECT_PREFIX="sg2000_milkv_duos_musl_riscv64"
		declare -g SOPHGO_CVI_BOARD_PREFIX="milkv_duos_musl_riscv64"
		declare -g SOPHGO_CVI_FILES_VARIANT="riscv64"
		declare -g SOPHGO_CVI_UBOOT_DTS_DIR="arch/riscv/dts"
		# "riscv", not "riscv64": the SDK and the FSBL Makefile expect the short name.
		declare -g SOPHGO_CVI_UBOOT_ARCH="riscv"
		# Also selects OpenSBI for fip.bin's monitor slot.
		declare -g SOPHGO_FSBL_ARCH="riscv"
		;;

	*)
		exit_with_error "sophgo-sg200x: unsupported ARCH" "${ARCH}"
		;;

esac

# ---------------------------------------------------------------------------
# U-Boot build
# ---------------------------------------------------------------------------

# The FSBL packs fip.bin from u-boot.bin plus a monitor. Its TOC header names one
# core, so fip.bin has to match the board's slide switch.

# Both bootloaders are built every time and the package carries both.
declare -g -a SOPHGO_CVI_STORAGE_VARIANTS=(sd emmc)

# Sets everything that names a storage type. Called once per u-boot target.
function sophgo_sg200x_select_build_storage() {
	declare storage="${1}"
	declare -g SOPHGO_CVI_TARGET_STORAGE="${storage}"
	declare -g SOPHGO_CVI_PROJECT="${SOPHGO_CVI_PROJECT_PREFIX}_${storage}"
	declare -g SOPHGO_CVI_BOARD="${SOPHGO_CVI_BOARD_PREFIX}_${storage}"
	declare -g BOOTCONFIG="cvitek_${SOPHGO_CVI_PROJECT}_defconfig"
}

# Has to be a constant: BOOTCONFIG is the first entry in artifact-uboot.sh's
# vars_to_hash.
sophgo_sg200x_select_build_storage "${SOPHGO_CVI_STORAGE_VARIANTS[0]}"

# One entry per storage variant. The "src:dst" form renames the outputs apart in
# the .deb; fip.bin comes from uboot_custom_postprocess() below.
declare -g UBOOT_TARGET_MAP=";;u-boot.bin:u-boot-sd.bin fip.bin:fip-sd.bin
;;u-boot.bin:u-boot-emmc.bin fip.bin:fip-emmc.bin"

function fetch_custom_uboot__sophgo_sg200x_fsbl() {
	display_alert "Sophgo SG200x" "fetching FSBL sources" "info"
	fetch_from_repo "${SOPHGO_FSBL_REPO}" "sophgo-fsbl" "${SOPHGO_FSBL_REF}" "yes"
	declare fsbl_subdir
	fsbl_subdir="$(branch2dir "${SOPHGO_FSBL_REF}")"
	declare -g SOPHGO_FSBL_DIR="${SRC}/cache/sources/sophgo-fsbl/${fsbl_subdir}"

	sophgo_sg200x_apply_patches "fsbl/sophgo-sg200x" "${SOPHGO_FSBL_DIR}" "FSBL"

	[[ "${SOPHGO_FSBL_ARCH}" == "riscv" ]] || return 0

	display_alert "Sophgo SG200x" "fetching OpenSBI sources" "info"
	fetch_from_repo "${SOPHGO_OPENSBI_REPO}" "sophgo-opensbi" "${SOPHGO_OPENSBI_REF}" "yes"
	declare opensbi_subdir
	opensbi_subdir="$(branch2dir "${SOPHGO_OPENSBI_REF}")"
	declare -g SOPHGO_OPENSBI_DIR="${SRC}/cache/sources/sophgo-opensbi/${opensbi_subdir}"

	sophgo_sg200x_apply_patches "opensbi/sophgo-sg200x" "${SOPHGO_OPENSBI_DIR}" "OpenSBI"
}

# ATFSOURCE is "none", so compile_atf() and advanced_patch() never run and these
# two trees have no patch machinery behind them. The argument is the path
# under patch/.
function sophgo_sg200x_apply_patches() {
	declare patch_dir="${SRC}/patch/${1}"
	declare target_dir="${2}"
	declare label="${3}"
	[[ -d "${patch_dir}" ]] || return 0

	declare patch
	for patch in "${patch_dir}"/*.patch; do
		[[ -f "${patch}" ]] || continue
		if git -C "${target_dir}" apply --check "${patch}" &> /dev/null; then
			display_alert "Sophgo SG200x" "${label} patch: $(basename "${patch}")" "info"
			run_host_command_logged git -C "${target_dir}" apply "${patch}"
		elif git -C "${target_dir}" apply --reverse --check "${patch}" &> /dev/null; then
			display_alert "Sophgo SG200x" "${label} patch already applied: $(basename "${patch}")" "info"
		else
			exit_with_error "${label} patch does not apply" "$(basename "${patch}")"
		fi
	done
}

# Runs after patching, which resets the tree, and before 'make <defconfig>'.
function pre_config_uboot_target__sophgo_sg200x_board_files() {
	declare files="${SOPHGO_CVI_FILES_DIR}"
	declare variant="${SOPHGO_CVI_FILES_VARIANT}"

	# uboot_target_counter is 1-based and indexed against UBOOT_TARGET_MAP.
	declare storage="${SOPHGO_CVI_STORAGE_VARIANTS[$((uboot_target_counter - 1))]:-}"
	[[ -n "${storage}" ]] ||
		exit_with_error "sophgo-sg200x: no storage variant for u-boot target ${uboot_target_counter}" \
			"SOPHGO_CVI_STORAGE_VARIANTS and UBOOT_TARGET_MAP disagree"
	sophgo_sg200x_select_build_storage "${storage}"

	display_alert "Sophgo SG200x" \
		"u-boot target ${uboot_target_counter} of ${#SOPHGO_CVI_STORAGE_VARIANTS[@]}: ${storage} (${BOOTCONFIG})" "info"

	display_alert "Sophgo SG200x" "installing cvitek board files (${variant})" "info"

	run_host_command_logged cp -v "${files}/common/dts/"*.dtsi "${SOPHGO_CVI_UBOOT_DTS_DIR}/"
	run_host_command_logged cp -v "${files}/${variant}/dts/"* "${SOPHGO_CVI_UBOOT_DTS_DIR}/"
	run_host_command_logged cp -v "${files}/${variant}/configs/"* "configs/"
	run_host_command_logged cp -v "${files}/${variant}/board/cvi_board_init.c" "board/cvitek/"
	run_host_command_logged mkdir -p "include/cvitek"
	run_host_command_logged cp -v "${files}/${variant}/include/cvitek.h" "include/cvitek/"
	run_host_command_logged cp -v "${files}/${variant}/include/cvi_board_memmap.h" "include/"

	# Fixed names, per-storage contents, so these two are copied per target.
	run_host_command_logged cp -v "${files}/${variant}/include/${storage}/cvipart.h" "include/"
	run_host_command_logged cp -v "${files}/${variant}/include/${storage}/imgs.h" "include/"

	# Covers 'make <defconfig>' and 'make olddefconfig'; the compile runs under
	# 'env -i' and is handled by the uboot_make_config hook below.
	sophgo_sg200x_export_cvitek_env
}

# The vendor build environment. Fills the caller's `sophgo_cvitek_env` array by
# dynamic scoping, so no `declare -g` here.
function sophgo_sg200x_cvitek_env_array() {
	sophgo_cvitek_env=(
		"ARCH=${SOPHGO_CVI_UBOOT_ARCH}"
		"CHIP=${SOPHGO_CVI_CHIP}"
		"CHIP_ARCH=${SOPHGO_CVI_CHIP_ARCH}"
		"CVIBOARD=${SOPHGO_CVI_BOARD}"
		"STORAGE_TYPE=${SOPHGO_CVI_TARGET_STORAGE}"
		"PANEL_TUNING_PARAM=${SOPHGO_CVI_PANEL}"
		"CONFIG_SKIP_RAMDISK=y"
		"CONFIG_USE_DEFAULT_ENV=y"
		"RELEASE=0"
		"UBOOT_VBOOT=0"
	)
}

function sophgo_sg200x_export_cvitek_env() {
	# The vendor build wants ARCH=riscv/arm64. uboot_custom_postprocess() puts
	# Armbian's back before the .deb is built.
	declare -g SOPHGO_SAVED_ARCH="${ARCH}"

	declare -a sophgo_cvitek_env
	sophgo_sg200x_cvitek_env_array
	declare kv
	for kv in "${sophgo_cvitek_env[@]}"; do
		export "${kv?}"
	done
}

function uboot_make_config__sophgo_sg200x_cvitek_env() {
	declare -a sophgo_cvitek_env
	sophgo_sg200x_cvitek_env_array
	# outer scope array, consumed by 'env -i "${uboot_make_envs[@]}"'
	uboot_make_envs+=("${sophgo_cvitek_env[@]}")
}

function post_config_uboot_target__sophgo_sg200x_cflags() {
	# U-Boot 2021.10 predates gcc 13's -Wenum-int-mismatch.
	# outer scope array, from compile_uboot_target()
	uboot_cflags_array+=("-Wno-error=enum-int-mismatch")
}

# Produces fip.bin, which UBOOT_TARGET_MAP packages into the .deb.
function uboot_custom_postprocess() {
	: "${SOPHGO_FSBL_DIR:?SOPHGO_FSBL_DIR is not set - did fetch_custom_uboot run?}"

	# Back to Armbian's ARCH, for the .deb's Architecture field.
	if [[ -n "${SOPHGO_SAVED_ARCH}" && "${ARCH}" != "${SOPHGO_SAVED_ARCH}" ]]; then
		display_alert "Sophgo SG200x" "restoring ARCH=${SOPHGO_SAVED_ARCH} (was ${ARCH})" "info"
		export ARCH="${SOPHGO_SAVED_ARCH}"
	fi

	declare uboot_dir
	uboot_dir="$(pwd)"

	# The name the FSBL expects.
	run_host_command_logged cp -v "${uboot_dir}/u-boot.bin" "${uboot_dir}/u-boot-raw.bin"

	# The FSBL Makefile has -Ibuild, so the memory map has to land there.
	run_host_command_logged mkdir -p "${SOPHGO_FSBL_DIR}/build"
	run_host_command_logged cp -v \
		"${SOPHGO_CVI_FILES_DIR}/${SOPHGO_CVI_FILES_VARIANT}/include/cvi_board_memmap.h" \
		"${SOPHGO_FSBL_DIR}/build/"

	declare fsbl_out="${SOPHGO_FSBL_DIR}/build/${SOPHGO_CVI_PROJECT}"
	declare od_clk_sel="n"
	[[ "${SOPHGO_CPU_OVERDRIVE}" == "yes" ]] && od_clk_sel="y"

	# bl31.bin on ARM, found by the FSBL itself; OpenSBI built here on RISC-V.
	declare -a fsbl_monitor=()
	if [[ "${SOPHGO_FSBL_ARCH}" == "riscv" ]]; then
		sophgo_sg200x_build_opensbi "${uboot_dir}"
		fsbl_monitor=("MONITOR_PATH=${SOPHGO_OPENSBI_FW_DYNAMIC}")
	fi

	display_alert "Sophgo SG200x" \
		"building FSBL and packing ${SOPHGO_CVI_TARGET_STORAGE} fip.bin (OD_CLK_SEL=${od_clk_sel})" "info"

	# CHIP_ARCH has to go through the environment: the FSBL Makefile lowercases it
	# into the platform directory name, and a make command-line variable is
	# immutable. CROSS_COMPILE is deliberately not passed; the Makefile derives it,
	# BOOT_CPU and ARCH from the per-arch variable. LDFLAGS silences the RWX segment
	# warning binutils >= 2.39 emits against the FSBL's --fatal-warnings.
	run_host_command_logged env \
		"ARCH=${SOPHGO_FSBL_ARCH}" \
		"CROSS_COMPILE_64=${UBOOT_COMPILER}" \
		"CROSS_COMPILE_GLIBC_RISCV64=${UBOOT_COMPILER}" \
		"CHIP_ARCH=${SOPHGO_CVI_CHIP_ARCH}" \
		"CHIP=${SOPHGO_CVI_CHIP}" \
		"DDR_CFG=${SOPHGO_CVI_DDR_CFG}" \
		"STORAGE=${SOPHGO_CVI_TARGET_STORAGE}" \
		"STORAGE_TYPE=${SOPHGO_CVI_TARGET_STORAGE}" \
		"OD_CLK_SEL=${od_clk_sel}" \
		"PROJECT_FULLNAME=${SOPHGO_CVI_PROJECT}" \
		make -C "${SOPHGO_FSBL_DIR}" \
		"O=${fsbl_out}" \
		"LOG_LEVEL=2" \
		"BLCP_2ND_PATH=" \
		"LOADER_2ND_PATH=${uboot_dir}/u-boot-raw.bin" \
		"LDFLAGS=--no-warn-rwx-segments" \
		"${fsbl_monitor[@]}" \
		"${CTHREADS}"

	[[ -f "${fsbl_out}/fip.bin" ]] || exit_with_error "FSBL did not produce fip.bin" "${fsbl_out}"

	# UBOOT_TARGET_MAP renames it on the way into the .deb.
	run_host_command_logged cp -v "${fsbl_out}/fip.bin" "${uboot_dir}/fip.bin"
	display_alert "Sophgo SG200x" \
		"${SOPHGO_CVI_TARGET_STORAGE} fip.bin is $(stat -c %s "${uboot_dir}/fip.bin") bytes" "info"
}

# RISC-V only. Builds the OpenSBI for fip.bin's monitor slot and sets
# SOPHGO_OPENSBI_FW_DYNAMIC. Runs after u-boot, whose device tree it embeds.
function sophgo_sg200x_build_opensbi() {
	declare uboot_dir="${1}"
	: "${SOPHGO_OPENSBI_DIR:?SOPHGO_OPENSBI_DIR is not set - did fetch_custom_uboot run?}"

	declare fdt="${uboot_dir}/arch/riscv/dts/${SOPHGO_CVI_CHIP}_${SOPHGO_CVI_BOARD}.dtb"
	[[ -f "${fdt}" ]] || exit_with_error "u-boot did not produce a device tree for OpenSBI" "${fdt}"

	display_alert "Sophgo SG200x" "building OpenSBI (monitor for fip.bin)" "info"

	# FW_FDT_PATH is required. OpenSBI 0.9 predates the binutils split of zicsr and
	# zifencei out of 'i', so PLATFORM_RISCV_ISA spells them out. platform-cflags-y
	# silences a gcc 13 false positive; firmware-cflags-y would clobber -fPIE -pie.
	run_host_command_logged make -C "${SOPHGO_OPENSBI_DIR}" \
		"PLATFORM=generic" \
		"CROSS_COMPILE=${UBOOT_COMPILER}" \
		"CHIP_ARCH=${SOPHGO_CVI_CHIP_ARCH}" \
		"OPENSBI_PATH=${SOPHGO_OPENSBI_DIR}" \
		"PLATFORM_RISCV_ISA=rv64imafdc_zicsr_zifencei" \
		"platform-cflags-y=-Wno-error=maybe-uninitialized" \
		"FW_PAYLOAD_PATH=${uboot_dir}/u-boot-raw.bin" \
		"FW_FDT_PATH=${fdt}" \
		"${CTHREADS}"

	declare -g SOPHGO_OPENSBI_FW_DYNAMIC="${SOPHGO_OPENSBI_DIR}/build/platform/generic/firmware/fw_dynamic.bin"
	[[ -f "${SOPHGO_OPENSBI_FW_DYNAMIC}" ]] ||
		exit_with_error "OpenSBI did not produce fw_dynamic.bin" "${SOPHGO_OPENSBI_FW_DYNAMIC}"

	display_alert "Sophgo SG200x" \
		"OpenSBI fw_dynamic.bin is $(stat -c %s "${SOPHGO_OPENSBI_FW_DYNAMIC}") bytes" "info"
}

# ---------------------------------------------------------------------------
# Image layout
# ---------------------------------------------------------------------------

# MBR, with a bootable FAT16 (0x0c) p1 the BootROM can read fip.bin out of by
# name - not the 0xea type Armbian would use by default. 128MiB matches the
# vendor image.
declare -g BOOTFS_TYPE="fat"
declare -g BOOTSIZE="128"

function pre_prepare_partitions__sophgo_sg200x_msdos_layout() {
	# riscv64.conf declares GPT, arm64 defaults to msdos; set both the same.
	declare -g IMAGE_PARTITION_TABLE="msdos"
	# 1MiB, matching the vendor and upstream Milk-V images.
	declare -g OFFSET="1"
}

function post_create_partitions__sophgo_sg200x_boot_partition_flags() {
	display_alert "Sophgo SG200x" "marking boot partition FAT (0x0c) and bootable" "info"
	run_host_command_logged sfdisk --part-type "${SDCARD}.raw" 1 c
	run_host_command_logged sfdisk --activate "${SDCARD}.raw" 1
}

# ---------------------------------------------------------------------------
# Bootloader installation
# ---------------------------------------------------------------------------

# The eMMC bootloader lives in a hardware boot partition that no image write can
# reach, so the u-boot package's postinst has to install it.
declare -g FORCE_UBOOT_UPDATE="yes"

# Installs fip.bin: as a file into the FAT partition always, and raw into
# mmcblkXboot0 at sectors 0 and 2048 when the target is an eMMC. Called from
# write_uboot_to_loop_image() during an image build, from uboot_postinst_base()
# on a package install, and from armbian-install.
#
# Comments inside the body are dropped by the `declare -f` that copies this into
# the package.
function write_uboot_platform() {
	declare dir="${1}" device="${2}"
	declare devname="${device##*/}"
	declare rc=0

	# An eMMC has a boot0; a card and a loop device have not.
	declare boot0="/dev/${devname}boot0"
	declare medium="sd"
	if [[ -b "${boot0}" ]]; then
		medium="emmc"
	elif [[ "${devname}" == loop* ]]; then
		medium="image"
	fi

	# The wrong variant is silently fatal either way. An image always gets the SD
	# one; sophgo-emmc-install swaps in the eMMC one later.
	declare storage="${medium}"
	if [[ "${medium}" == "image" ]]; then
		storage="sd"
	fi

	declare fip="${dir}/fip-${storage}.bin"
	if [[ ! -f "${fip}" ]]; then
		echo "sophgo-sg200x: no ${fip##*/} in ${dir}; this package has no ${storage} bootloader" >&2
		return 1
	fi

	# What the vendor U-Boot's cvi_update does. PARTITION_CONFIG is left alone.
	if [[ "${medium}" == "emmc" ]]; then
		declare force_ro="/sys/block/${devname}boot0/force_ro"
		declare fip_bytes boot0_bytes
		fip_bytes="$(stat -c %s "${fip}")"
		boot0_bytes="$(blockdev --getsize64 "${boot0}")"

		# Each copy gets a fixed 0x800 sectors from cvi_update, so a fip.bin past a
		# megabyte would have the second dd overwrite the tail of the first. The
		# read-back further down sees it, but only once boot0 already holds a
		# bootloader that cannot start.
		if [[ "${fip_bytes}" -gt $((2048 * 512)) ]]; then
			echo "sophgo-sg200x: ${fip##*/} is ${fip_bytes} bytes; over $((2048 * 512)), the copy at sector 2048 overwrites the one at sector 0" >&2
			return 1
		fi

		# The backup copy goes a megabyte in, so boot0 has to hold that much plus
		# the file.
		if [[ $((2048 * 512 + fip_bytes)) -gt "${boot0_bytes}" ]]; then
			echo "sophgo-sg200x: ${boot0} is only $((boot0_bytes / 1024))KB; ${fip_bytes} bytes at sector 2048 will not fit" >&2
			return 1
		fi
		if [[ ! -w "${force_ro}" ]]; then
			echo "sophgo-sg200x: cannot write ${force_ro}; ${boot0} stays read-only" >&2
			return 1
		fi

		echo "sophgo-sg200x: installing fip.bin into ${boot0} (sectors 0 and 2048)"
		echo 0 > "${force_ro}" || return 1
		dd if="${fip}" of="${boot0}" bs=512 seek=0 conv=fsync status=none || rc=1
		dd if="${fip}" of="${boot0}" bs=512 seek=2048 conv=fsync status=none || rc=1
		sync
		echo 1 > "${force_ro}" || echo "sophgo-sg200x: could not restore read-only on ${boot0}" >&2

		# The calling postinst runs under `set +e` and always exits 0, so verify
		# rather than trust dd's exit status.
		if [[ "${rc}" -eq 0 ]]; then
			cmp -s -n "${fip_bytes}" "${fip}" "${boot0}" || rc=1
			cmp -s -i "0:$((2048 * 512))" -n "${fip_bytes}" "${fip}" "${boot0}" || rc=1
		fi

		if [[ "${rc}" -ne 0 ]]; then
			echo "sophgo-sg200x: FAILED to write ${boot0}; the eMMC bootloader was NOT updated" >&2
			return 1
		fi
		echo "sophgo-sg200x: ${boot0} verified against the packaged fip.bin"
	fi

	# Already mounted in both real cases, so ask where rather than assume.
	declare part1="${device}p1"
	[[ -b "${part1}" ]] || part1="${device}1"
	if [[ ! -b "${part1}" ]]; then
		echo "sophgo-sg200x: no first partition on ${device}; nowhere to put fip.bin" >&2
		return 1
	fi

	declare bootdir="" tmpmnt=""
	bootdir="$(findmnt --first-only --noheadings --output TARGET --source "${part1}" 2> /dev/null)" || bootdir=""
	if [[ -z "${bootdir}" ]]; then
		tmpmnt="$(mktemp -d)" || return 1
		if ! mount "${part1}" "${tmpmnt}"; then
			rmdir "${tmpmnt}"
			echo "sophgo-sg200x: could not mount ${part1}" >&2
			return 1
		fi
		bootdir="${tmpmnt}"
	fi

	echo "sophgo-sg200x: installing the ${storage} fip.bin into ${bootdir}"
	cp "${fip}" "${bootdir}/fip.bin" || rc=1

	# Nothing boots this from here; it is what lets sophgo-emmc-install and the
	# installer-card extension flash an eMMC from a plain FAT partition.
	if [[ -f "${dir}/fip-emmc.bin" ]]; then
		cp "${dir}/fip-emmc.bin" "${bootdir}/fip-emmc.bin" || rc=1
	else
		echo "sophgo-sg200x: no fip-emmc.bin in ${dir}; this medium cannot flash an eMMC" >&2
		rc=1
	fi

	# Informational; sophgo-emmc-install reports it.
	echo "${storage}" > "${bootdir}/sophgo-storage.txt" || rc=1
	sync

	if [[ -n "${tmpmnt}" ]]; then
		umount "${tmpmnt}" || rc=1
		rmdir "${tmpmnt}" 2> /dev/null || true
	fi

	if [[ "${rc}" -ne 0 ]]; then
		echo "sophgo-sg200x: FAILED to install fip.bin into ${bootdir}" >&2
	fi

	return "${rc}"
}

# ---------------------------------------------------------------------------
# Userspace
# ---------------------------------------------------------------------------

# NetworkManager needs dnsmasq to hand the USB gadget's peer an address. Set here
# because the framework freezes PACKAGE_LIST_FAMILY after sourcing the family.
if [[ "${NETWORKING_STACK}" == "network-manager" ]]; then
	declare -g PACKAGE_LIST_FAMILY="${PACKAGE_LIST_FAMILY} dnsmasq-base"
fi

# Everything the post_family_tweaks_bsp hooks below install comes out of
# packages/bsp/sophgo-sg200x.
declare -g -a BSP_CLI_EXTRA_HASH_DIRS
BSP_CLI_EXTRA_HASH_DIRS+=("${SRC}/packages/bsp/sophgo-sg200x")

# Shipped on both storage variants; it refuses to touch its own root device.
function post_family_tweaks_bsp__sophgo_sg200x_emmc_install_tool() {
	display_alert "Sophgo SG200x" "installing eMMC install helper" "info"

	run_host_command_logged install -d -m 0755 "${destination}/usr/sbin"
	run_host_command_logged install -m 0755 \
		"${SRC}/packages/bsp/sophgo-sg200x/usr/sbin/sophgo-emmc-install" \
		"${destination}/usr/sbin/sophgo-emmc-install"
}

# Nothing gives the SG200x ethernet a MAC address, so derive one from the chip's
# efuse serial. Shared with the wifi side, whose udev rule
# extensions/sophgo-sg200x-aic8800.sh installs.
function post_family_tweaks_bsp__sophgo_sg200x_stable_mac() {
	display_alert "Sophgo SG200x" "installing stable MAC address helper" "info"

	run_host_command_logged install -d -m 0755 "${destination}/lib/udev" \
		"${destination}/etc/udev/rules.d"
	run_host_command_logged install -m 0755 \
		"${SRC}/packages/bsp/sophgo-sg200x/lib/udev/sg200x-stable-mac" \
		"${destination}/lib/udev/sg200x-stable-mac"
	run_host_command_logged install -m 0644 \
		"${SRC}/packages/bsp/sophgo-sg200x/etc/udev/rules.d/70-sg200x-stable-mac.rules" \
		"${destination}/etc/udev/rules.d/70-sg200x-stable-mac.rules"
}

# The userspace half of the "usb-device" overlay, installed on every image; it is
# inert until a UDC exists. Both network stacks are configured, since which one
# is running is not known here.
function post_family_tweaks_bsp__sophgo_sg200x_usb_gadget() {
	display_alert "Sophgo SG200x" "installing USB CDC-NCM gadget service" "info"

	run_host_command_logged install -d -m 0755 "${destination}/usr/sbin" \
		"${destination}/usr/lib/systemd/system" \
		"${destination}/etc/systemd/network"
	run_host_command_logged install -m 0755 \
		"${SRC}/packages/bsp/sophgo-sg200x/usr/sbin/sg200x-usb-gadget" \
		"${destination}/usr/sbin/sg200x-usb-gadget"
	run_host_command_logged install -m 0644 \
		"${SRC}/packages/bsp/sophgo-sg200x/usr/lib/systemd/system/sg200x-usb-gadget.service" \
		"${destination}/usr/lib/systemd/system/sg200x-usb-gadget.service"
	run_host_command_logged install -m 0644 \
		"${SRC}/packages/bsp/sophgo-sg200x/etc/systemd/network/70-sg200x-usb0.network" \
		"${destination}/etc/systemd/network/70-sg200x-usb0.network"

	# 0600, or NetworkManager will not read it.
	run_host_command_logged install -d -m 0755 "${destination}/etc/NetworkManager/system-connections"
	run_host_command_logged install -m 0600 \
		"${SRC}/packages/bsp/sophgo-sg200x/etc/NetworkManager/system-connections/sg200x-usb0.nmconnection" \
		"${destination}/etc/NetworkManager/system-connections/sg200x-usb0.nmconnection"
}

function post_family_tweaks__sophgo_sg200x_usb_gadget_enable() {
	display_alert "Sophgo SG200x" "enabling USB CDC-NCM gadget service" "info"
	chroot_sdcard systemctl --no-reload enable sg200x-usb-gadget.service
}

# 512MB of RAM: 100% gives a 512MB zram device while MEM_LIMIT_PERCENTAGE stays
# at its 50% default. ZRAM_PERCENTAGE ships commented out, hence the "#\?" in the
# pattern.
function post_family_tweaks__sophgo_sg200x_zram() {
	display_alert "Sophgo SG200x" "tuning zram for 512MB of RAM" "info"

	declare zram_conf="${SDCARD}/etc/default/armbian-zram-config"
	if [[ -f "${zram_conf}" ]]; then
		sed -i 's/^#\?\s*ZRAM_PERCENTAGE=.*/ZRAM_PERCENTAGE=100/' "${zram_conf}"
		grep -q '^ZRAM_PERCENTAGE=100$' "${zram_conf}" ||
			exit_with_error "failed to set ZRAM_PERCENTAGE" "${zram_conf}"
	fi
}
