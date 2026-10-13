# Allwinner H5 quad core 1GB RAM Wi-Fi/BT
BOARD_MAINTAINER="julioramos0"
BOARD_NAME="PBS TV Stick"
BOARD_VENDOR="shaghal"
BOARDFAMILY="sun50iw2"
BOOTCONFIG="orangepi_prime_defconfig"
CRUSTCONFIG="orangepi_pc2_defconfig"
DEFAULT_CONSOLE="both"
DEFAULT_OVERLAYS="analog-codec"
HAS_VIDEO_OUTPUT="yes"
FDTFILE="allwinner/sun50i-h5-pbstvstick.dtb"
INTRODUCED="2016"
KERNEL_TARGET="current,edge,legacy"
KERNEL_TEST_TARGET="current"
MODULES="g_serial"
SERIALCON="ttyS0,ttyGS0"
PACKAGE_LIST_BOARD="mmc-utils"

function post_config_uboot_target__pbstvstick() {
	display_alert "$BOARD" "u-boot: DRAM tune (432/ODT) + eMMC boot" "info"
	run_host_command_logged scripts/config --set-val CONFIG_DRAM_CLK "432"
	run_host_command_logged scripts/config --enable CONFIG_DRAM_ODT_EN
	run_host_command_logged scripts/config --disable CONFIG_SPL_SPI_SUNXI
	run_host_command_logged scripts/config --disable CONFIG_SUPPORT_EMMC_BOOT
	run_host_command_logged scripts/config --disable CONFIG_OF_UPSTREAM
	run_host_command_logged scripts/config --disable CONFIG_SPL_WDT
	run_host_command_logged scripts/config --disable CONFIG_WDT
	run_host_command_logged scripts/config --disable CONFIG_WATCHDOG
	run_host_command_logged scripts/config --disable CONFIG_SPL_DM_MMC
	run_host_command_logged scripts/config --enable CONFIG_SPL_MMC_TINY
	run_host_command_logged scripts/config --set-val CONFIG_MMC_SUNXI_SLOT_EXTRA 2
	
	sed -i 's/cfg->f_max = 52000000;/cfg->f_max = 12000000;/g' drivers/mmc/sunxi_mmc.c
	sed -i 's/MMC_MODE_4BIT/0/g' drivers/mmc/sunxi_mmc.c
	

local node_content='
&reg_vcc3v3 {
	u-boot,dm-spl;
};

&mmc0_pins {
	u-boot,dm-spl;
};

&mmc0 {
	u-boot,dm-spl;
	vmmc-supply = <&reg_vcc3v3>;
	bus-width = <4>;
	cap-sd-highspeed;
	broken-cd;	disable-wp;
	no-1-8-v;
	status = "okay";
};

&mmc2 {
	pinctrl-names = "default";
	pinctrl-0 = <&mmc2_8bit_pins>;
	vmmc-supply = <&reg_vcc3v3>;
	bus-width = <4>;
	max-frequency = <25000000>;
	vqmmc-supply = <&reg_vcc3v3>;
	no-1-8-v;
	non-removable;
	cap-mmc-hw-reset;
	status = "okay";
};
'
	if [ -f "arch/arm/dts/sun50i-h5-orangepi-prime.dts" ]; then
		sed -i 's/model = "Xunlong Orange Pi Prime";/model = "PBST314";/g' arch/arm/dts/sun50i-h5-orangepi-prime.dts
		echo "$node_content" >> arch/arm/dts/sun50i-h5-orangepi-prime.dts
	fi
	if [ -f "dts/upstream/src/arm64/allwinner/sun50i-h5-orangepi-prime.dts" ]; then
		sed -i 's/model = "Xunlong Orange Pi Prime";/model = "PBST314";/g' dts/upstream/src/arm64/allwinner/sun50i-h5-orangepi-prime.dts
		echo "$node_content" >> dts/upstream/src/arm64/allwinner/sun50i-h5-orangepi-prime.dts
	fi
}