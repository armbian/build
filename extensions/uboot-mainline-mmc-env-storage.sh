# @description Gives SPI-less boards a persistent mainline U-Boot environment on the eMMC/SD card, plus a working
# `/etc/fw_env.config` so `fw_printenv`/`fw_setenv` work from Linux. The eMMC counterpart of what boards like
# `nanopct6` and `rock-5b` already do in SPI NOR. Targets recent (2026+) mainline u-boot only.
# Two storage modes, selected with `UBOOT_MMC_ENV_MODE`:
#
#   hwpart (default on rockchip) -- one env copy in each of the eMMC hardware boot areas, boot0 and boot1.
#     U-Boot does this natively: with CONFIG_ENV_REDUNDANT=y, hw partition 1, and ENV_OFFSET == ENV_OFFSET_REDUND,
#     mmc_env_is_redundant_in_both_boot_hwparts() (env/mmc.c) stores copy 0 in boot0 and copy 1 in boot1.
#     Those areas live entirely outside the partition table, so the env survives repartitioning, armbian-install,
#     and a full re-image of the user area -- not just a u-boot reflash. Rockchip's BROM loads the IDB from the
#     user area at sector 64, and nothing in Armbian writes rockchip boot0/boot1, so they are free real estate.
#
#   offset (default on meson64) -- a raw offset in the reserved gap ahead of partition 1, two copies.
#     Used where the boot areas are not free: the Amlogic BROM *does* boot from boot0/boot1, and Armbian's own
#     jethub family dd's u-boot into them, so hwpart mode is not safe there.
#     Offsets are picked so no write_uboot_platform() variant can overwrite them:
#       rockchip64/rk35xx/rockchip-rk3588 (OFFSET=16 MiB): 0xE00000 (14 MiB) + redundant at 0xE20000.
#         idbloader lands at 32 KiB, u-boot.itb/uboot.img at 8 MiB, trust.bin at 12 MiB. On binman boards the
#         single u-boot-rockchip.bin is written at 32 KiB and is 0xff-padded up to CONFIG_SPL_PAD_TO (0x7f8000
#         on rk3588), so it spans 32 KiB -> ~9.5 MiB. That is why mainline's own ENV_OFFSET default for
#         ARCH_ROCKCHIP && ENV_IS_IN_MMC (0x3f8000) is not used: it would be erased on every u-boot reflash.
#       meson64 (OFFSET=4 MiB, MBR): 0x300000 (3 MiB) + redundant at 0x320000.
#         u-boot.bin is written from LBA 1 and runs ~0.8-1 MiB contiguously.
#
# Refuses to run on boards that have SPI NOR (BOOT_SUPPORT_SPI=yes, an SPI target in UBOOT_TARGET_MAP, or a
# defconfig that already sets CONFIG_ENV_IS_IN_SPI_FLASH) -- those should keep their env in SPI.
#
# Overridable per board/build: UBOOT_MMC_ENV_MODE (hwpart|offset), UBOOT_MMC_ENV_OFFSET, UBOOT_MMC_ENV_SIZE,
# UBOOT_MMC_ENV_OFFSET_REDUND, UBOOT_MMC_ENV_HW_PARTITION, UBOOT_MMC_ENV_FWENV_MODE (follow|fixed, offset mode
# only), UBOOT_MMC_ENV_DEVICE_INDEX, UBOOT_MMC_ENV_FORCE.
#
# CAVEAT: once `saveenv` has run, the stored environment shadows the compiled-in default forever. A later u-boot
# upgrade that changes BOOT_TARGETS/bootcmd/bootargs will NOT take effect until you run `env default -a; saveenv`
# in the u-boot console (or `fw_setenv` from Linux). Same tradeoff the SPI-env boards already carry.
#
# CAVEAT (hwpart mode): SD cards have no hardware boot areas. On rockchip, mmc_get_env_dev() follows the device
# SPL booted from, so booting the same image from SD makes the hwpart switch fail and u-boot falls back to its
# built-in default env (non-fatal, but there is no persistent env in that case). Use offset mode if that matters.
function extension_prepare_config__uboot_mainline_mmc_env_storage() {
	declare -g UBOOT_MMC_ENV_SKIP="no"

	display_alert "Extension: ${EXTENSION}" "u-boot environment in MMC for ${BOARD}" "info"

	# Known-good settings per family. Anything else must opt in explicitly by setting UBOOT_MMC_ENV_OFFSET.
	declare table_storage="" table_offset="" table_redund="" table_fwenv=""
	case "${BOARDFAMILY}" in
		rockchip64 | rk35xx | rockchip-rk3588)
			# BROM reads the IDB from the user area, so boot0/boot1 are unused: default to hwpart.
			# The offset-mode fallback values assume the 16 MiB gap; everything u-boot writes ends below ~13 MiB.
			# rockchip's mmc_get_env_dev() (arch/arm/mach-rockchip/board.c) makes u-boot follow the device SPL
			# booted from, so userspace must too.
			table_storage="hwpart"
			table_offset="0xE00000"
			table_redund="0xE20000"
			table_fwenv="follow"
			;;

		meson-gxbb | meson-gxl | meson-g12a | meson-g12b | meson-sm1 | meson-axg | meson-s4t7 | jethub)
			# The Amlogic BROM boots from the eMMC boot areas (jethub dd's u-boot into boot0/boot1), so they are
			# NOT free here -- offset mode only. 4 MiB gap by default; u-boot.bin from LBA 1. meson has no
			# mmc_get_env_dev() override, so u-boot always uses the fixed device index and userspace must match.
			table_storage="offset"
			table_offset="0x300000"
			table_redund="0x320000"
			table_fwenv="fixed"
			;;

		*)
			if [[ -z "${UBOOT_MMC_ENV_OFFSET:-}" ]]; then
				exit_with_error "${EXTENSION} has no known-good env location for BOARDFAMILY='${BOARDFAMILY}'" \
					"set UBOOT_MMC_ENV_OFFSET (and optionally UBOOT_MMC_ENV_SIZE, UBOOT_MMC_ENV_OFFSET_REDUND, UBOOT_MMC_ENV_FWENV_MODE, UBOOT_MMC_ENV_DEVICE_INDEX) to opt in explicitly"
			fi
			table_storage="offset"
			table_fwenv="fixed"
			;;
	esac

	declare -g UBOOT_MMC_ENV_MODE="${UBOOT_MMC_ENV_MODE:-"${table_storage}"}"
	declare -g UBOOT_MMC_ENV_SIZE="${UBOOT_MMC_ENV_SIZE:-"0x20000"}"
	declare -g UBOOT_MMC_ENV_DEVICE_INDEX="${UBOOT_MMC_ENV_DEVICE_INDEX:-"0"}"

	case "${UBOOT_MMC_ENV_MODE}" in
		hwpart)
			declare -g UBOOT_MMC_ENV_HW_PARTITION="${UBOOT_MMC_ENV_HW_PARTITION:-"1"}"
			# Both copies at the same offset is what triggers u-boot's one-copy-per-boot-area mode.
			declare -g UBOOT_MMC_ENV_OFFSET="${UBOOT_MMC_ENV_OFFSET:-"0x0"}"
			declare -g UBOOT_MMC_ENV_OFFSET_REDUND="${UBOOT_MMC_ENV_OFFSET_REDUND:-"${UBOOT_MMC_ENV_OFFSET}"}"

			if [[ "${UBOOT_MMC_ENV_HW_PARTITION}" == "1" ]]; then
				# u-boot only spreads the copies across boot0/boot1 when the two offsets are identical.
				if [[ $((UBOOT_MMC_ENV_OFFSET)) -ne $((UBOOT_MMC_ENV_OFFSET_REDUND)) ]]; then
					exit_with_error "${EXTENSION}: hwpart mode needs both env offsets identical" \
						"got ${UBOOT_MMC_ENV_OFFSET} and ${UBOOT_MMC_ENV_OFFSET_REDUND}; equal offsets are what puts copy 0 in boot0 and copy 1 in boot1"
				fi
			else
				# Any other hw partition keeps both copies in that one area, so they must not overlap.
				if [[ $((UBOOT_MMC_ENV_OFFSET)) -eq $((UBOOT_MMC_ENV_OFFSET_REDUND)) ]]; then
					exit_with_error "${EXTENSION}: hw partition ${UBOOT_MMC_ENV_HW_PARTITION} keeps both env copies in one boot area" \
						"they would overlap at ${UBOOT_MMC_ENV_OFFSET}; use UBOOT_MMC_ENV_HW_PARTITION=1 for the boot0+boot1 split, or give distinct offsets"
				fi
			fi

			display_alert "${EXTENSION}" "env in eMMC boot areas (hw partition ${UBOOT_MMC_ENV_HW_PARTITION}) at ${UBOOT_MMC_ENV_OFFSET}, size ${UBOOT_MMC_ENV_SIZE}" "info"
			;;

		offset)
			declare -g UBOOT_MMC_ENV_OFFSET="${UBOOT_MMC_ENV_OFFSET:-"${table_offset}"}"
			declare -g UBOOT_MMC_ENV_FWENV_MODE="${UBOOT_MMC_ENV_FWENV_MODE:-"${table_fwenv}"}"
			# Default the redundant copy to sit immediately after the primary one, if not given by table or user.
			declare -g UBOOT_MMC_ENV_OFFSET_REDUND="${UBOOT_MMC_ENV_OFFSET_REDUND:-"${table_redund:-$(printf "0x%X" $((UBOOT_MMC_ENV_OFFSET + UBOOT_MMC_ENV_SIZE)))}"}"

			if [[ "${UBOOT_MMC_ENV_FWENV_MODE}" != "follow" && "${UBOOT_MMC_ENV_FWENV_MODE}" != "fixed" ]]; then
				exit_with_error "${EXTENSION}: UBOOT_MMC_ENV_FWENV_MODE must be 'follow' or 'fixed'" "got '${UBOOT_MMC_ENV_FWENV_MODE}'"
			fi

			# Both env copies must fit inside the gap ahead of partition 1. OFFSET is in MiB (see main-config.sh).
			declare -i gap_bytes=$((OFFSET * 1024 * 1024))
			declare -i env_end=$((UBOOT_MMC_ENV_OFFSET_REDUND + UBOOT_MMC_ENV_SIZE))
			declare -i env_primary_end=$((UBOOT_MMC_ENV_OFFSET + UBOOT_MMC_ENV_SIZE))
			[[ ${env_primary_end} -gt ${env_end} ]] && env_end=${env_primary_end}
			if [[ ${env_end} -gt ${gap_bytes} ]]; then
				exit_with_error "${EXTENSION}: env does not fit in the ${OFFSET} MiB gap before partition 1" \
					"env ends at $(printf "0x%X" "${env_end}") but the gap ends at $(printf "0x%X" "${gap_bytes}"); lower UBOOT_MMC_ENV_OFFSET or raise OFFSET"
			fi
			if [[ $((UBOOT_MMC_ENV_OFFSET_REDUND)) -lt ${env_primary_end} && $((UBOOT_MMC_ENV_OFFSET_REDUND)) -ge $((UBOOT_MMC_ENV_OFFSET)) ]]; then
				exit_with_error "${EXTENSION}: redundant env overlaps the primary env" \
					"primary $(printf "0x%X" $((UBOOT_MMC_ENV_OFFSET)))+${UBOOT_MMC_ENV_SIZE}, redundant $(printf "0x%X" $((UBOOT_MMC_ENV_OFFSET_REDUND)))"
			fi

			display_alert "${EXTENSION}" "env at ${UBOOT_MMC_ENV_OFFSET} (redundant ${UBOOT_MMC_ENV_OFFSET_REDUND}), size ${UBOOT_MMC_ENV_SIZE}, fw_env mode '${UBOOT_MMC_ENV_FWENV_MODE}'" "info"
			;;

		*)
			exit_with_error "${EXTENSION}: UBOOT_MMC_ENV_MODE must be 'hwpart' or 'offset'" "got '${UBOOT_MMC_ENV_MODE}'"
			;;
	esac

	# libubootenv-tool provides fw_printenv and fw_setenv, for talking to the U-Boot environment.
	# Note hwpart mode *requires* libubootenv specifically: its fileprotect() clears /sys/class/block/*/force_ro
	# around writes to /dev/mmcblkNbootM. u-boot's own tools/env/fw_env.c has no such handling.
	add_packages_to_image libubootenv-tool
}

# Refuse to run on boards that have usable SPI NOR: they should keep their env there instead.
# Runs as extension_finish_config so UBOOT_TARGET_MAP/BOOT_SUPPORT_SPI are final (late_family_config already ran).
# There is no single "board has SPI" flag in the tree, so check every signal boards actually use:
#   - BOOT_SUPPORT_SPI=yes         rockchip convention (~40 boards)
#   - an spi entry in UBOOT_TARGET_MAP   e.g. odroidhc4/odroidn2 'armbian_target=spi', or a *-spi.bin output
# Note write_uboot_platform_mtd() is NOT a usable signal: rockchip64_common defines it for every board,
# including the SPI-less ones this extension exists for.
function extension_finish_config__uboot_mainline_mmc_env_storage() {
	[[ "${UBOOT_MMC_ENV_SKIP:-no}" == "yes" ]] && return 0
	[[ "${UBOOT_MMC_ENV_FORCE:-}" == "yes" ]] && return 0

	declare spi_reason=""
	if [[ "${BOOT_SUPPORT_SPI}" == "yes" ]]; then
		spi_reason="BOOT_SUPPORT_SPI=yes"
	elif [[ "${UBOOT_TARGET_MAP}" == *spi* ]]; then
		spi_reason="UBOOT_TARGET_MAP has an SPI target"
	fi

	if [[ -n "${spi_reason}" ]]; then
		exit_with_error "${EXTENSION}: ${BOARD} has SPI flash (${spi_reason})" \
			"this extension is for SPI-less boards; put the env in SPI instead (see nanopct6/rock-5b), or set UBOOT_MMC_ENV_FORCE=yes"
	fi
}

# 900_ prefix so this runs *after* any board-level post_config_uboot_target__* (implicitly 500_) that might
# also touch env config. Runs per u-boot target, with .config present, right before the framework's olddefconfig.
function post_config_uboot_target__900_uboot_mainline_mmc_env_storage() {
	[[ "${UBOOT_MMC_ENV_SKIP:-no}" == "yes" ]] && return 0

	# SPI targets have their own env story; leave them alone.
	if [[ "${target_make}" == *spi* || "${BOOTCONFIG}" == *spi* ]]; then
		display_alert "u-boot for ${BOARD}/${BRANCH}" "${EXTENSION}: skipping SPI target '${target_make}'" "info"
		return 0
	fi

	if [[ ! -f scripts/config ]]; then
		exit_with_error "${EXTENSION} requires recent mainline u-boot (2026+)" \
			"BOOTBRANCH='${BOOTBRANCH}' for ${BOARD} has no scripts/config at all; set a modern BOOTBRANCH/BOOTBRANCH_BOARD"
	fi

	# Last net, for SPI boards that extension_finish_config could not spot from the board config alone.
	if grep -q "^CONFIG_ENV_IS_IN_SPI_FLASH=y" .config && [[ "${UBOOT_MMC_ENV_FORCE:-}" != "yes" ]]; then
		exit_with_error "${EXTENSION}: ${BOARD} already stores its u-boot env in SPI flash" \
			"this extension is meant for SPI-less boards; set UBOOT_MMC_ENV_FORCE=yes to move the env to MMC anyway"
	fi

	display_alert "u-boot for ${BOARD}/${BRANCH}" "${EXTENSION}: env in MMC, mode '${UBOOT_MMC_ENV_MODE}'" "info"
	run_host_command_logged scripts/config --disable CONFIG_ENV_IS_IN_SPI_FLASH
	run_host_command_logged scripts/config --disable CONFIG_ENV_IS_NOWHERE
	run_host_command_logged scripts/config --enable CONFIG_ENV_IS_IN_MMC
	run_host_command_logged scripts/config --enable CONFIG_ENV_OVERWRITE
	run_host_command_logged scripts/config --enable CONFIG_ENV_REDUNDANT
	run_host_command_logged scripts/config --set-val CONFIG_ENV_OFFSET "${UBOOT_MMC_ENV_OFFSET}"
	run_host_command_logged scripts/config --set-val CONFIG_ENV_OFFSET_REDUND "${UBOOT_MMC_ENV_OFFSET_REDUND}"
	run_host_command_logged scripts/config --set-val CONFIG_ENV_SIZE "${UBOOT_MMC_ENV_SIZE}"
	run_host_command_logged scripts/config --set-val CONFIG_ENV_MMC_DEVICE_INDEX "${UBOOT_MMC_ENV_DEVICE_INDEX}"

	# CONFIG_ENV_MMC_EMMC_HW_PARTITION is the post-v2025.10 name (it was CONFIG_SYS_MMC_ENV_PART before).
	# We only support 2026+, so require the current name and use its absence as the "too old" signal.
	if ! grep -q "^config ENV_MMC_EMMC_HW_PARTITION" env/Kconfig; then
		exit_with_error "${EXTENSION} requires recent mainline u-boot (2026+)" \
			"BOOTBRANCH='${BOOTBRANCH}' for ${BOARD} predates CONFIG_ENV_MMC_EMMC_HW_PARTITION (renamed from SYS_MMC_ENV_PART in v2025.10); set a modern BOOTBRANCH/BOOTBRANCH_BOARD"
	fi

	if [[ "${UBOOT_MMC_ENV_MODE}" == "hwpart" ]]; then
		# One copy per boot area needs mmc_env_is_redundant_in_both_boot_hwparts(), added in v2025.07.
		# Without it, our two identical offsets would put both copies in the SAME place -- no redundancy at all.
		if [[ "${UBOOT_MMC_ENV_HW_PARTITION}" == "1" ]] && ! grep -q "mmc_env_is_redundant_in_both_boot_hwparts" env/mmc.c; then
			exit_with_error "${EXTENSION}: this u-boot cannot split the env across boot0 and boot1" \
				"BOOTBRANCH='${BOOTBRANCH}' for ${BOARD}; use UBOOT_MMC_ENV_MODE=offset, or a newer BOOTBRANCH/BOOTBRANCH_BOARD"
		fi

		display_alert "u-boot for ${BOARD}/${BRANCH}" "${EXTENSION}: env in eMMC boot areas (boot0 + boot1)" "info"
		run_host_command_logged scripts/config --set-val CONFIG_ENV_MMC_EMMC_HW_PARTITION "${UBOOT_MMC_ENV_HW_PARTITION}"
	else
		# User area; be explicit that we do not want a hw boot area.
		run_host_command_logged scripts/config --set-val CONFIG_ENV_MMC_EMMC_HW_PARTITION "0"
	fi

	# Sanity: the symbols must actually be in .config. olddefconfig runs right after us and may still drop
	# them if a dependency is unmet (e.g. CONFIG_MMC disabled), but that would be a broken board config anyway.
	grep -q "^CONFIG_ENV_IS_IN_MMC=y" .config ||
		exit_with_error "${EXTENSION}: CONFIG_ENV_IS_IN_MMC did not stick in .config" "${BOARD}/${BRANCH} target '${target_make}'"
}

# Called once per produced u-boot binary. In offset mode, verify the binary we're about to ship does not reach
# into the env window. Not applicable in hwpart mode: the env lives outside the user area entirely.
# ${binfile} / ${base_binfile} come from the hook (lib/functions/compilation/uboot.sh).
function check_uboot_produced_binary_file__uboot_mainline_mmc_env_storage() {
	[[ "${UBOOT_MMC_ENV_SKIP:-no}" == "yes" ]] && return 0
	[[ "${UBOOT_MMC_ENV_MODE}" != "offset" ]] && return 0

	declare -i write_offset
	case "${base_binfile}" in
		u-boot-rockchip.bin | idbloader.img | idbloader.bin | rksd_loader.img) write_offset=$((0x8000)) ;;
		u-boot.itb | uboot.img) write_offset=$((0x800000)) ;;
		trust.bin) write_offset=$((0xC00000)) ;;
		u-boot.bin | u-boot.bin.sd.bin | u-boot.bin.sd.bin.signed) write_offset=$((0x200)) ;;
		*) return 0 ;; # SPI images (u-boot-rockchip-spi.bin, rkspi_loader*.img) and anything unknown: not our business
	esac

	declare -i binfile_size
	binfile_size="$(wc -c < "${binfile}")"
	declare -i binfile_end=$((write_offset + binfile_size))

	if [[ ${binfile_end} -gt $((UBOOT_MMC_ENV_OFFSET)) ]]; then
		exit_with_error "${EXTENSION}: '${base_binfile}' would overwrite the u-boot environment" \
			"it is written at $(printf "0x%X" "${write_offset}") and ends at $(printf "0x%X" "${binfile_end}"), past the env at ${UBOOT_MMC_ENV_OFFSET}"
	fi

	display_alert "${EXTENSION}" "'${base_binfile}' ends at $(printf "0x%X" "${binfile_end}"), clear of env at ${UBOOT_MMC_ENV_OFFSET}" "debug"
}

# Install the userspace side: a boot-time generator for /etc/fw_env.config, plus a build-time version of the same
# file so fw_printenv works before the unit has ever run.
function post_family_tweaks__uboot_mainline_mmc_env_storage() {
	[[ "${UBOOT_MMC_ENV_SKIP:-no}" == "yes" ]] && return 0

	display_alert "Configuring fw_printenv and fw_setenv" "${EXTENSION}: mode '${UBOOT_MMC_ENV_MODE}' for ${BOARD}" "info"

	mkdir -p "${SDCARD}/usr/lib/armbian" "${SDCARD}/etc/systemd/system"

	declare generator="${SDCARD}/usr/lib/armbian/armbian-uboot-mmc-env-config"

	# In hwpart mode the device resolution is its own thing; otherwise it follows UBOOT_MMC_ENV_FWENV_MODE.
	declare generator_mode="${UBOOT_MMC_ENV_FWENV_MODE:-fixed}"
	[[ "${UBOOT_MMC_ENV_MODE}" == "hwpart" ]] && generator_mode="hwpart"

	# Header carries the build-time values; the body below is literal.
	cat <<- FWENV_GENERATOR_HEADER > "${generator}"
		#!/bin/sh
		# armbian-uboot-mmc-env-config -- installed by build/extensions/uboot-mainline-mmc-env-storage.sh
		#
		# Writes /etc/fw_env.config pointing at the raw u-boot environment stored on the MMC device.
		#
		# MODE=hwpart: env lives in the eMMC hardware boot areas, one copy in boot0 and one in boot1.
		#              libubootenv clears force_ro on those for us; plain u-boot-tools fw_setenv cannot.
		# MODE=follow: u-boot's mmc_get_env_dev() returns the device SPL booted from, so we resolve the same
		#              device from ubootpart=<PARTUUID> on the kernel cmdline (set by Armbian's boot script).
		# MODE=fixed:  u-boot always uses CONFIG_ENV_MMC_DEVICE_INDEX, and Linux mmcblk numbering follows the
		#              same DT 'mmc<N>' aliases, so the index maps straight across.
		MODE="${generator_mode}"
		FALLBACK_DEV="/dev/mmcblk${UBOOT_MMC_ENV_DEVICE_INDEX}"
		ENV_OFFSET="${UBOOT_MMC_ENV_OFFSET}"
		ENV_OFFSET_REDUND="${UBOOT_MMC_ENV_OFFSET_REDUND}"
		ENV_SIZE="${UBOOT_MMC_ENV_SIZE}"
	FWENV_GENERATOR_HEADER

	cat <<- 'FWENV_GENERATOR_BODY' >> "${generator}"

		set -e

		# Resolve the device u-boot booted from, via ubootpart=<PARTUUID> on the cmdline.
		# Same trick as setup_write_uboot_platform() in the u-boot package.
		resolve_boot_mmc_device() {
		    cmdline=$(cat /proc/cmdline)
		    case "${cmdline}" in
		        *ubootpart=*) ;;
		        *) return 1 ;;
		    esac

		    uuid=${cmdline##*ubootpart=}
		    uuid=${uuid%% *}
		    [ -n "${uuid}" ] || return 1

		    part=$(findfs "PARTUUID=${uuid}" 2> /dev/null) || return 1
		    [ -n "${part}" ] || return 1

		    dev=$(lsblk -n -o PKNAME "${part}" 2> /dev/null | head -1) || return 1
		    [ -n "${dev}" ] || return 1

		    # Only MMC devices carry the raw env; if we landed on NVMe/USB, fall back instead of
		    # pointing fw_setenv at a disk that has no environment on it.
		    case "${dev}" in
		        mmcblk*) ;;
		        *) return 1 ;;
		    esac

		    echo "/dev/${dev}"
		}

		# Find the MMC device that actually has hardware boot areas -- i.e. the eMMC. Prefer the one u-boot
		# booted from; SD cards have no boot areas, so fall back to whichever eMMC is present.
		resolve_hwpart_mmc_device() {
		    dev=$(resolve_boot_mmc_device) || dev=""
		    if [ -n "${dev}" ] && [ -b "${dev}boot0" ]; then
		        echo "${dev}"
		        return 0
		    fi
		    for d in /dev/mmcblk[0-9]; do
		        [ -b "${d}boot0" ] || continue
		        echo "${d}"
		        return 0
		    done
		    return 1
		}

		DEV=""
		DEV_REDUND=""
		case "${MODE}" in
		    hwpart)
		        base=$(resolve_hwpart_mmc_device) || base="${FALLBACK_DEV}"
		        DEV="${base}boot0"
		        DEV_REDUND="${base}boot1"
		        ;;
		    follow)
		        DEV=$(resolve_boot_mmc_device) || DEV=""
		        ;;
		esac
		[ -n "${DEV}" ] || DEV="${FALLBACK_DEV}"
		[ -n "${DEV_REDUND}" ] || DEV_REDUND="${DEV}"

		TMP=$(mktemp /etc/fw_env.config.XXXXXX)
		{
		    echo "# Generated by armbian-uboot-mmc-env-config. Do not edit; edit the extension instead."
		    echo "# Raw u-boot environment, two redundant copies."
		    echo "# Device	Device offset	Env. size"
		    printf '%s\t%s\t%s\n' "${DEV}" "${ENV_OFFSET}" "${ENV_SIZE}"
		    printf '%s\t%s\t%s\n' "${DEV_REDUND}" "${ENV_OFFSET_REDUND}" "${ENV_SIZE}"
		} > "${TMP}"
		chmod 0644 "${TMP}"

		if cmp -s "${TMP}" /etc/fw_env.config; then
		    rm -f "${TMP}"
		else
		    mv -f "${TMP}" /etc/fw_env.config
		fi
	FWENV_GENERATOR_BODY

	chmod 0755 "${generator}"

	cat <<- 'FWENV_SERVICE' > "${SDCARD}/etc/systemd/system/armbian-uboot-mmc-env-config.service"
		[Unit]
		Description=Point fw_printenv/fw_setenv at the u-boot environment on MMC
		Documentation=https://github.com/armbian/build/blob/main/extensions/uboot-mainline-mmc-env-storage.sh
		# needs /proc/cmdline and the block devices; writes to /etc
		After=local-fs.target

		[Service]
		Type=oneshot
		ExecStart=/usr/lib/armbian/armbian-uboot-mmc-env-config
		RemainAfterExit=yes

		[Install]
		WantedBy=multi-user.target
	FWENV_SERVICE

	# Build-time copy, so fw_printenv works on the very first boot before the unit has run.
	declare fwenv_dev="/dev/mmcblk${UBOOT_MMC_ENV_DEVICE_INDEX}"
	declare fwenv_dev_redund="${fwenv_dev}"
	if [[ "${UBOOT_MMC_ENV_MODE}" == "hwpart" ]]; then
		fwenv_dev="/dev/mmcblk${UBOOT_MMC_ENV_DEVICE_INDEX}boot0"
		fwenv_dev_redund="/dev/mmcblk${UBOOT_MMC_ENV_DEVICE_INDEX}boot1"
	fi
	{
		echo "# Raw u-boot environment, two redundant copies."
		echo "# Regenerated at boot by armbian-uboot-mmc-env-config.service."
		printf '# %s\t%s\t%s\n' "Device" "Device offset" "Env. size"
		printf '%s\t%s\t%s\n' "${fwenv_dev}" "${UBOOT_MMC_ENV_OFFSET}" "${UBOOT_MMC_ENV_SIZE}"
		printf '%s\t%s\t%s\n' "${fwenv_dev_redund}" "${UBOOT_MMC_ENV_OFFSET_REDUND}" "${UBOOT_MMC_ENV_SIZE}"
	} > "${SDCARD}/etc/fw_env.config"

	chroot_sdcard "systemctl enable armbian-uboot-mmc-env-config.service" ||
		display_alert "Could not enable armbian-uboot-mmc-env-config.service in chroot" "${EXTENSION}" "warn"
}
