# Amlogic A311D 2/4GB RAM eMMC GBE USB3 M.2
BOARD_NAME="Khadas VIM3"
BOARDFAMILY="meson-g12b"
BOARD_MAINTAINER="NicoD-SBC rpardini"
BOOTCONFIG="khadas-vim3_defconfig"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
MODULES_BLACKLIST="simpledrm" # SimpleDRM conflicts with Panfrost on the VIM3
FULL_DESKTOP="yes"
SERIALCON="ttyAML0"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="amlogic/meson-g12b-a311d-khadas-vim3.dtb" # there is also a s922x dtb, but vim3 is a311d only
ASOUND_STATE="asound.state.khadas-vim3"

BOOTBRANCH_BOARD="tag:v2024.01"
BOOTPATCHDIR="v2024.01" # this has 'board_khadas-vim3' which has a patch to boot USB/NVMe/SCSI first

declare -g KHADAS_OOWOW_BOARD_ID="VIM3" # for use with EXT=output-image-oowow

# To enable the SPI NOR the -spi .dtb is required, because eMMC shares a pin with SPI on the VIM3. To use it:
# fdtfile=amlogic/meson-g12b-a311d-khadas-vim3-spinor.dtb # in armbianEnv.txt and reboot, then run armbian-install
# After deploying to SPI-NOR/MTD, return back to the normal DTB, otherwise eMMC speed is impaired.
UBOOT_TARGET_MAP="u-boot-dtb.img;;u-boot.bin.sd.bin:u-boot.bin u-boot-dtb.img u-boot.bin:u-boot-spi.bin"

# Smarter/faster/better to-spi writer using flashcp (hopefully with --partition)
function write_uboot_platform_mtd() {
	declare -a extra_opts_flashcp=("--verbose")
	if flashcp -h | grep -q -e '--partition'; then
		echo "Confirmed flashcp supports --partition -- read and write only changed blocks." >&2
		extra_opts_flashcp+=("--partition")
	else
		echo "flashcp does not support --partition, will write full SPI flash blocks." >&2
	fi
	flashcp "${extra_opts_flashcp[@]}" "${1}/u-boot-spi.bin" /dev/mtd0
}

# Khadas provided fixed FIP blobs for SPI, so we can now use the same blobs for both SPI and eMMC booting.
# See https://github.com/armbian/build/pull/5386#issuecomment-1752400874
# See https://github.com/LibreELEC/amlogic-boot-fip/pull/21
function post_uboot_custom_postprocess__khadas_vim3_uboot() {
	display_alert "Signing u-boot FIP" "${BOARD}" "info"
	uboot_g12_postprocess "${SRC}"/cache/sources/amlogic-boot-fip/khadas-vim3 g12b
}

# Enable extra u-boot .config options, this way we avoid patching defconfig
function post_config_uboot_target__extra_configs_for_khadas_vim3() {
	display_alert "u-boot for ${BOARD}" "u-boot: enable more compression support" "info"
	run_host_command_logged scripts/config --enable CONFIG_LZO
	run_host_command_logged scripts/config --enable CONFIG_BZIP2
	run_host_command_logged scripts/config --enable CONFIG_ZSTD
	display_alert "u-boot for ${BOARD}" "u-boot: enable kaslrseed support" "info"
	run_host_command_logged scripts/config --enable CONFIG_CMD_KASLRSEED
	display_alert "u-boot for ${BOARD}" "u-boot: enable gpio LED support" "info"
	run_host_command_logged scripts/config --enable CONFIG_LED
	run_host_command_logged scripts/config --enable CONFIG_LED_GPIO
	display_alert "u-boot for ${BOARD}" "u-boot: enable networking cmds" "info"
	run_host_command_logged scripts/config --enable CONFIG_CMD_NFS
	run_host_command_logged scripts/config --enable CONFIG_CMD_WGET
	run_host_command_logged scripts/config --enable CONFIG_CMD_DNS
	run_host_command_logged scripts/config --enable CONFIG_PROT_TCP
	run_host_command_logged scripts/config --enable CONFIG_PROT_TCP_SACK
}
