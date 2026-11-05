# @description Installs the Radxa EDK2 SPI NOR firmware package for Qualcomm Radxa boards (`edk2-<board>` from the Armbian repo, which pulls `edl-ng`) and lets `armbian-install` update it. The NOR is owned by TrustZone, so the bsp-cli loads `mtdblock` and ships a `write_uboot_platform_mtd` that writes through the `qcom_scm_storage` MTD device with `edl-ng`, keeps a backup in `/var/backups` and reads every image back. Needs `CONFIG_MTD_QCOM_SCM_STORAGE` in the kernel.

# The package lives in the Armbian repo, which image builds only enable from this hook on
function post_armbian_repo_customize_image__radxa_edk2_spinor_install() {
	chroot_sdcard_apt_get_install "edk2-${BOARD}"
}

# Runs after the grub cleanup of the BSP so the hook survives it
function post_family_tweaks_bsp__900_radxa_edk2_spinor_update() {
	display_alert "Adding to bsp-cli" "${BOARD}: SPI NOR firmware update hook" "info"
	# armbian-install only lists MTD devices that have an mtdblock node
	add_file_from_stdin_to_bsp_destination "/etc/modules-load.d/${BOARD}-spinor.conf" <<< "mtdblock"
	{
		echo "# Armbian SPI NOR firmware install script for ${BOARD}"
		echo "DIR=/usr/lib/edk2/radxa/${BOARD}"
		echo "BOOTLOADER_NAME=\"EDK2 firmware\""
		declare -f write_uboot_platform_mtd
	} | add_file_from_stdin_to_bsp_destination "/usr/lib/u-boot/platform_install.sh"
}

# Called by armbian-install as: write_uboot_platform_mtd <dir> <device> <log> <mtd_list>
function write_uboot_platform_mtd() {
	declare dir="${1}" log="${3:-/dev/stderr}"
	declare mtd="" sysdev work backup entry file start size
	declare -i verified=0

	# The NOR is owned by TrustZone and only reachable through the SCM storage MTD device
	for sysdev in /sys/class/mtd/mtd*; do
		[[ "${sysdev}" =~ /mtd[0-9]+$ && "$(cat "${sysdev}/name" 2> /dev/null)" == "qcom_scm_storage" ]] || continue
		mtd="/dev/${sysdev##*/}"
		break
	done
	if [[ -z "${mtd}" ]]; then
		echo "SPI NOR not available: no qcom_scm_storage MTD device" >> "${log}"
		return 1
	fi
	if [[ ! -f "${dir}/rawprogram0.xml" || ! -f "${dir}/patch0.xml" ]]; then
		echo "SPI NOR image not found in ${dir}" >> "${log}"
		return 1
	fi
	if ! command -v edl-ng > /dev/null; then
		echo "edl-ng is missing" >> "${log}"
		return 1
	fi

	# patch0.xml rewrites the GPT image in place, so flash from a scratch copy
	work="$(mktemp -d)" || return 1
	cp -rL "${dir}/." "${work}/" || {
		rm -rf "${work}"
		return 1
	}

	mkdir -p /var/backups
	backup="/var/backups/spinor-$(date +%Y%m%d-%H%M%S).bin"
	if ! dd if="${mtd}" of="${backup}" bs=64k status=none; then
		echo "Backup of ${mtd} failed, nothing written" >> "${log}"
		rm -rf "${work}" "${backup}"
		return 1
	fi
	echo "Saved current SPI NOR contents to ${backup}" >> "${log}"

	# edl-ng erases each range it writes
	if ! (cd "${work}" && edl-ng --hostdev-as-target "${mtd}" rawprogram rawprogram0.xml patch0.xml) >> "${log}" 2>&1; then
		echo "Writing ${mtd} failed, do not reboot, retry or restore ${backup} via EDL" >> "${log}"
		rm -rf "${work}"
		return 1
	fi
	sync

	# Read back every image except the GPT, which patch0.xml patches on the device
	while read -r entry; do
		file="$(sed -n 's/.* filename="\([^"]*\)".*/\1/p' <<< "${entry}")"
		start="$(sed -n 's/.* start_sector="\([0-9]*\)".*/\1/p' <<< "${entry}")"
		[[ -n "${file}" && -n "${start}" ]] || continue
		size="$(stat -c %s "${work}/${file}")"
		if ! cmp -s -n "${size}" "${work}/${file}" <(dd if="${mtd}" bs=4096 skip="${start}" count="$(((size + 4095) / 4096))" status=none); then
			echo "Verification of ${file} failed, do not reboot, retry or restore ${backup} via EDL" >> "${log}"
			rm -rf "${work}"
			return 1
		fi
		verified+=1
	done < <(grep -o '<program [^>]*' "${work}/rawprogram0.xml" | grep 'partofsingleimage="false"')
	if ((verified == 0)); then
		echo "No image of rawprogram0.xml was verified, do not reboot, retry or restore ${backup} via EDL" >> "${log}"
		rm -rf "${work}"
		return 1
	fi

	echo "SPI NOR firmware written on ${mtd}, ${verified} images verified" >> "${log}"
	rm -rf "${work}"
	return 0
}
