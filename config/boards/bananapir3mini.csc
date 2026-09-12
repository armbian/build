# MediaTek MT7986A quad core Cortex-A53 2GB DDR4 8GB eMMC dual 2.5GbE
BOARD_NAME="Banana Pi R3 Mini"
BOARD_VENDOR="sinovoip"
BOARDFAMILY="filogic"
BOARD_MAINTAINER="SuperKali"
INTRODUCED="2026"
KERNEL_TARGET="current"
KERNEL_TEST_TARGET="current"
BOOT_SOC="mt7986"
ATF_BOOT_DEVICE="emmc"
BOOTCONFIG="mt7986a_bpi-r3-mini-emmc_defconfig"
BOOT_FDT_FILE="mediatek/mt7986a-bananapi-bpi-r3-mini.dtb"
SRC_EXTLINUX="yes"
SRC_CMDLINE="console=ttyS0,115200n8 rootwait loglevel=8 swiotlb=512 cgroup_enable=memory"
HAS_VIDEO_OUTPUT="no"
PACKAGE_LIST_BOARD="mtd-utils nvme-cli" # SPI-NAND recovery medium and the M.2 M-key slot

function post_family_config_branch_current__bananapir3mini_kernel() {
	declare -g LINUXFAMILY="filogic-mt7986"
	declare -g KERNEL_MAJOR_MINOR="6.18"
	declare -g KERNELSOURCE=""
	declare -g KERNELBRANCH=""
	declare -g KERNEL_PATCH_ARCHIVE_BASE="filogic-mt7986"
	declare -g KERNELPATCHDIR="archive/filogic-mt7986-6.18"
	declare -g LINUXCONFIG="linux-filogic-mt7986-current"
}

# BL2 lives in the eMMC boot0 hardware partition, which a disk image cannot carry
function post_family_config__bananapir3mini_uboot_platform() {
	# mtk-gpt.bin ships in the package because write_uboot_platform also runs board-side
	declare -g UBOOT_TARGET_MAP=";;u-boot.bin u-boot_sdmmc.fip bl2.img mtk-gpt.bin"

	write_uboot_platform() {
		dd if=$1/u-boot_sdmmc.fip of=$2 bs=512 seek=13312 status=noxfer > /dev/null 2>&1

		# drop any u-boot environment inherited from a previous OpenWrt install
		dd if=/dev/zero of=$2 bs=512 seek=8192 count=1024 conv=notrunc status=noxfer > /dev/null 2>&1

		# backup gpt table
		LAST_START=$(parted "$2" unit s print | grep -v "^$" | tail -n 1 | awk '{print $2}' | tr -d 's')
		LAST_SIZE=$(parted "$2" unit s print | grep -v "^$" | tail -n 1 | awk '{print $4}' | tr -d 's')
		# write mtk gpt table
		dd if="$1/mtk-gpt.bin" of="$2" conv=notrunc
		# append armbian rootfs info
		echo "${LAST_START},${LAST_SIZE}" | sfdisk --no-reread --append "$2"
		# retype the FIP slot so systemd does not treat it as an ESP
		sfdisk --no-reread --part-type "$2" 4 0FC63DAF-8483-4772-8E79-3D69D8477DE4
		# distro_bootcmd scans only bootable partitions, and the template flags the unused bl2 slot
		sfdisk --no-reread --part-attrs "$2" 1 RequiredPartition
		sfdisk --no-reread --part-attrs "$2" 5 LegacyBIOSBootable
	}
}

# uboot_custom_postprocess() runs in the u-boot build dir, drop the template where UBOOT_TARGET_MAP finds it
function post_uboot_custom_postprocess__bananapir3mini_ship_gpt_template() {
	display_alert "u-boot for ${BOARD}" "shipping MediaTek GPT template in the package" "info"
	run_host_command_logged cp -v "${SRC}/packages/blobs/filogic/gpt" "$(pwd)/mtk-gpt.bin"
}

# U-Boot needs the EN8811H firmware before the network comes up, keep a copy in the initramfs
function post_family_tweaks_bsp__bananapir3mini_network_firmware_in_initrd() {
	display_alert "Adding to bsp-cli" "${BOARD}: Airoha firmware in initramfs" "info"

	declare file_added_to_bsp_destination
	add_file_from_stdin_to_bsp_destination "/etc/initramfs-tools/hooks/bpi-r3-mini-firmware" <<- 'FIRMWARE_HOOK'
		#!/bin/bash
		[[ "$1" == "prereqs" ]] && exit 0
		. /usr/share/initramfs-tools/hook-functions
		add_firmware "airoha/EthMD32.dm.bin" || true
		add_firmware "airoha/EthMD32.DSP.bin" || true
	FIRMWARE_HOOK
	run_host_command_logged chmod -v +x "${file_added_to_bsp_destination}"
}

# U-Boot reads the EN8811H firmware from eMMC boot1, which a disk image cannot populate
function post_family_tweaks_bsp__bananapir3mini_phy_firmware_helper() {
	display_alert "Adding to bsp-cli" "${BOARD}: EN8811H firmware installer" "info"

	declare file_added_to_bsp_destination
	add_file_from_stdin_to_bsp_destination "/usr/sbin/bpi-r3-mini-install-phy-firmware" <<- 'PHY_FW_INSTALLER'
		#!/bin/bash
		# Writes the Airoha EN8811H MD32 firmware into eMMC boot1, where U-Boot looks for it.
		# Linux does not need this, it loads the same blobs from /lib/firmware.
		set -e

		dm="/lib/firmware/airoha/EthMD32.dm.bin"
		dsp="/lib/firmware/airoha/EthMD32.DSP.bin"
		dev="/dev/mmcblk0boot1"
		force_ro="/sys/block/mmcblk0boot1/force_ro"

		[[ ${EUID} -eq 0 ]] || { echo "must run as root" >&2; exit 1; }
		[[ -b ${dev} ]] || { echo "${dev} not present" >&2; exit 1; }
		for f in "${dm}" "${dsp}"; do
			[[ -f ${f} ]] || { echo "missing ${f}" >&2; exit 1; }
		done
		[[ $(stat -c%s "${dm}") -eq 16384 ]] || { echo "unexpected size for ${dm}" >&2; exit 1; }
		[[ $(stat -c%s "${dsp}") -eq 131072 ]] || { echo "unexpected size for ${dsp}" >&2; exit 1; }

		if [[ ${1} != "--yes" ]]; then
			echo "This overwrites the first 144 KiB of ${dev}."
			echo "Only U-Boot reads it, Linux is unaffected either way."
			echo "Re-run with --yes to proceed."
			exit 0
		fi

		echo 0 > "${force_ro}"
		dd if="${dm}" of="${dev}" bs=16384 count=1 conv=fsync status=none
		dd if="${dsp}" of="${dev}" bs=16384 seek=1 conv=fsync status=none
		echo 1 > "${force_ro}"
		echo "Airoha EN8811H firmware written to ${dev}"
	PHY_FW_INSTALLER
	run_host_command_logged chmod -v +x "${file_added_to_bsp_destination}"
}

# The board stores no MAC anywhere, so derive stable per-unit ones from the eMMC CID
function post_family_tweaks_bsp__bananapir3mini_stable_macs() {
	display_alert "Adding to bsp-cli" "${BOARD}: stable MAC addresses from eMMC CID" "info"

	declare file_added_to_bsp_destination
	add_file_from_stdin_to_bsp_destination "/usr/lib/armbian/bpi-r3-mini-macaddr" <<- 'MACADDR_SCRIPT'
		#!/bin/bash
		# Derive stable per-unit MAC addresses for the two GMACs from the eMMC CID.
		# This board carries no MAC anywhere: the i2c 24c02 ships blank and neither
		# factory region holds one, so the kernel makes up a random MAC every boot.
		set -u

		cid_file="/sys/block/mmcblk0/device/cid"
		[[ -r ${cid_file} ]] || exit 0
		cid="$(< "${cid_file}")"
		[[ -n ${cid} ]] || exit 0

		hash="$(printf '%s' "${cid}" | sha256sum | cut -d' ' -f1)"

		derive_mac() {
			local off=$(( $1 * 12 )) first mac k
			# clear the multicast bit and set the locally administered bit
			printf -v first '%02x' $(( 0x${hash:${off}:2} & 0xfe | 0x02 ))
			mac="${first}"
			for k in 1 2 3 4 5; do
				mac+=":${hash:$(( off + k * 2 )):2}"
			done
			printf '%s' "${mac}"
		}

		for ifpath in /sys/class/net/*; do
			ifname="${ifpath##*/}"
			of_name="$(udevadm info -q property -p "${ifpath}" 2>/dev/null | sed -n 's/^OF_FULLNAME=//p')"
			case "${of_name}" in
				*/ethernet@15100000/mac@0) index=0 ;;
				*/ethernet@15100000/mac@1) index=1 ;;
				*) continue ;;
			esac

			want="$(derive_mac "${index}")"
			have="$(< "${ifpath}/address")"
			[[ ${want} == "${have}" ]] && continue

			# mtk_eth_soc refuses a MAC change while the interface is administratively up
			was_up=""
			[[ $(< "${ifpath}/flags") ]] && (( 0x$(sed 's/^0x//' "${ifpath}/flags") & 0x1 )) && was_up=yes
			[[ -n ${was_up} ]] && ip link set dev "${ifname}" down

			if ip link set dev "${ifname}" address "${want}" 2>/dev/null; then
				echo "${ifname}: MAC set to ${want}"
			else
				echo "${ifname}: failed to set MAC ${want}" >&2
			fi

			[[ -n ${was_up} ]] && ip link set dev "${ifname}" up
		done
	MACADDR_SCRIPT
	run_host_command_logged chmod -v +x "${file_added_to_bsp_destination}"

	add_file_from_stdin_to_bsp_destination "/lib/systemd/system/bpi-r3-mini-macaddr.service" <<- 'MACADDR_SERVICE'
		[Unit]
		Description=Stable MAC addresses for the BPI-R3 Mini GMACs
		After=local-fs.target
		Wants=network-pre.target
		Before=network-pre.target

		[Service]
		Type=oneshot
		RemainAfterExit=yes
		ExecStart=/usr/lib/armbian/bpi-r3-mini-macaddr

		[Install]
		WantedBy=multi-user.target
	MACADDR_SERVICE

	mkdir -p "${destination}/etc/systemd/system/multi-user.target.wants"
	ln -sf "/lib/systemd/system/bpi-r3-mini-macaddr.service" \
		"${destination}/etc/systemd/system/multi-user.target.wants/bpi-r3-mini-macaddr.service"
}

# The EN8811H port LEDs come up with no trigger, the device tree keeps their reset state
function post_family_tweaks_bsp__bananapir3mini_phy_leds() {
	display_alert "Adding to bsp-cli" "${BOARD}: EN8811H port LED triggers" "info"

	declare file_added_to_bsp_destination
	add_file_from_stdin_to_bsp_destination "/usr/lib/armbian/bpi-r3-mini-phy-leds" <<- 'PHY_LEDS_SCRIPT'
		#!/bin/bash
		# Point the EN8811H port LEDs at their own interface. The PHY offloads both
		# rules in hardware, so the yellow one blinks on traffic and the green one
		# stays lit at gigabit and above without any CPU involvement.
		set -u

		configure_leds() {
			local ifpath ifname leds led found=1
			for ifpath in /sys/class/net/*; do
				ifname="${ifpath##*/}"
				leds="${ifpath}/phydev/leds"
				[[ -d ${leds} ]] || continue
				found=0
				for led in "${leds}"/*; do
					[[ -d ${led} ]] || continue
					echo netdev > "${led}/trigger" 2>/dev/null || continue
					echo "${ifname}" > "${led}/device_name"
					case "${led##*/}" in
						*:yellow:*)
							echo 1 > "${led}/link"
							echo 1 > "${led}/tx"
							echo 1 > "${led}/rx"
							;;
						*:green:*)
							echo 1 > "${led}/link_1000"
							echo 1 > "${led}/link_2500"
							;;
					esac
				done
			done
			return ${found}
		}

		# the phy only attaches when the interface is opened, so give it a moment
		for _ in $(seq 30); do
			configure_leds && exit 0
			sleep 1
		done
		exit 0
	PHY_LEDS_SCRIPT
	run_host_command_logged chmod -v +x "${file_added_to_bsp_destination}"

	add_file_from_stdin_to_bsp_destination "/lib/systemd/system/bpi-r3-mini-phy-leds.service" <<- 'PHY_LEDS_SERVICE'
		[Unit]
		Description=Port LED triggers for the BPI-R3 Mini Airoha PHYs
		After=network.target

		[Service]
		Type=oneshot
		RemainAfterExit=yes
		ExecStart=/usr/lib/armbian/bpi-r3-mini-phy-leds

		[Install]
		WantedBy=multi-user.target
	PHY_LEDS_SERVICE

	mkdir -p "${destination}/etc/systemd/system/multi-user.target.wants"
	ln -sf "/lib/systemd/system/bpi-r3-mini-phy-leds.service" \
		"${destination}/etc/systemd/system/multi-user.target.wants/bpi-r3-mini-phy-leds.service"
}
