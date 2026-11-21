# Allwinner H616 quad core 512MB/1GB RAM SoC WiFi SPI USB-C
BOARD_NAME="Orange Pi Zero2"
BOARD_VENDOR="xunlong"
BOARDFAMILY="sun50iw9"
BOARD_MAINTAINER=""
INTRODUCED="2020"
BOOTCONFIG="orangepi_zero2_defconfig"
BOOT_LOGO="desktop"
OVERLAY_PREFIX="sun50i-h616"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
FORCE_BOOTSCRIPT_UPDATE="yes"

enable_extension "uwe5622-allwinner"

# SPI NOR: same image, offset 0; $2 is /dev/mtdblockN
function write_uboot_platform_mtd() {
	local img="$1/u-boot-sunxi-with-spl.bin" mtd="${2/mtdblock/mtd}"
	if command -v flashcp > /dev/null && [[ -c $mtd ]]; then
		flashcp -v "$img" "$mtd"
	else
		dd if="$img" of="$2" conv=fsync,notrunc status=none
	fi
}

# The U-Boot environment is in the 2 MiB SPI NOR at 0xf0000 (64 KiB), above the bootloader
# that armbian-install writes to the start of the flash. fw_printenv/fw_setenv (libubootenv)
# use the same location; the SPI NOR is the board's only MTD device, so it is mtd0.
declare -g EXTRA_BSPDEPS="libubootenv-tool"

function post_family_tweaks_bsp__orangepizero2_fw_env_config() {
	cat <<- EOF > "${destination}"/etc/fw_env.config
		# Device	Offset	Env size	Sector size
		/dev/mtd0	0xf0000	0x10000	0x10000
	EOF
}

# The SPI NOR image must end below the environment, or saveenv and armbian-install
# would overwrite each other.
function post_uboot_custom_postprocess__orangepizero2_env_offset_guard() {
	grep -q '^CONFIG_ENV_IS_IN_SPI_FLASH=y' .config || return 0
	local env_offset bin_size
	env_offset=$(sed -n 's/^CONFIG_ENV_OFFSET=//p' .config)
	bin_size=$(stat -c %s u-boot-sunxi-with-spl.bin)
	if ((bin_size > env_offset)); then
		exit_with_error "u-boot-sunxi-with-spl.bin (${bin_size} bytes) overlaps the SPI flash environment at ${env_offset}"
	fi
	display_alert "u-boot-sunxi-with-spl.bin ends below the SPI flash environment" "${bin_size} <= ${env_offset}" "info"
}

# fw_printenv/fw_setenv need the default environment while the SPI NOR holds no saved one
# (blank flash, or after an erase); ship the one this U-Boot build was compiled with.
function post_uboot_custom_postprocess__orangepizero2_initial_env() {
	run_host_command_logged "env" "-i" "${uboot_make_envs[@]}" pipetty make u-boot-initial-env "$CTHREADS" "${cross_compile}"
	run_host_command_logged install -D -m 0644 u-boot-initial-env "${uboottempdir}/etc/u-boot-initial-env"
}
