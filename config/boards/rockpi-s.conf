# Rockchip RK3308 quad core 256-512MB SoC WiFi
BOARD_NAME="Rockpi S"
BOARDFAMILY="rockchip64"
BOARD_MAINTAINER="brentr"
BOOTCONFIG="rock-pi-s-rk3308_defconfig"

DEFAULT_CONSOLE="serial"
MODULES_LEGACY="g_serial"
SERIALCON="ttyS0"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current,edge"
BOOT_FDT_FILE="rockchip/rk3308-rock-pi-s.dtb"
MODULES_BLACKLIST="rockchipdrm analogix_dp dw_mipi_dsi dw_hdmi gpu_sched lima hantro_vpu panfrost"
HAS_VIDEO_OUTPUT="no"
BOOTBRANCH_BOARD="tag:v2022.04"
BOOTPATCHDIR="u-boot-rockchip64-v2022.04"

OVERLAY_PREFIX='rk3308'

#comment out line below for an image that will NOT boot from the built-in SDNAND
IDBLOADER_BLOB=$SRC/packages/blobs/rockchip/rk3308_idbloader_ddr589MHz_uart0_m0_v2.06.136sd.bin

#The SDNAND capabilty IDBLOADER_BLOB requires the U-Boot and Linux serial console on UART0
#Linux will hang on reboot if the console remains on UART2

#Note:  IDBLOADER_BLOB is derived from
#  https://dl.radxa.com/rockpis/images/loader/rk3308_loader_ddr589MHz_uart0_m0_v2.06.136sd.bin
#by using the rkdeveloptool to "upgrade" the previous DDR_BLOB loader on the SDNAND
#To recreate it, build the image with IDBLOADER_BLOB unset and boot Rock PI-S in MASKROM mode
#On your host (connected to the RockPi-S's USB-C port):
#  rdeveloptool db rk3308_loader_ddr589MHz_uart0_m0_v2.06.136sd.bin
#  rdeveloptool wl 0 newly_built_image.img
#  rdeveloptool ul rk3308_loader_ddr589MHz_uart0_m0_v2.06.136sd.bin  #this writes 280 sectors

#Then, reset the RockPi-S to boot from SDNAND.  Using that running image:
#  dd if=/dev/mmcblk0 of=rk3308_idbloader_ddr589MHz_uart0_m0_v2.06.136sd.bin skip=64 count=280

function post_family_config___uboot_config() {

	display_alert "$BOARD" "u-boot ${BOOTBRANCH_BOARD} overrides" "info"
	unset uboot_custom_postprocess family_tweaks_bsp # disable stuff from rockchip64_common

	BOOTSCRIPT=boot-rockpis.cmd:boot.cmd
	BOOTENV_FILE='rockpis.txt'

	uboot_custom_postprocess() {

		# TODO: remove this diversion from common caused by different loaderimage params
		run_host_x86_binary_logged $RKBIN_DIR/tools/loaderimage --pack --uboot ./u-boot-dtb.bin uboot.img 0x600000 --size 1024 1 &&
			if [ -r "$IDBLOADER_BLOB" ]; then
				echo "Installing $IDBLOADER_BLOB"
				echo "Capable of booting from built-in SDNAND"
				cp $IDBLOADER_BLOB idbloader.bin
			else
				[ "$IDBLOADER_BLOB" ] && echo "Missing $IDBLOADER_BLOB"
				echo "WARNING:  This image will not boot from built-in SDNAND"
				tools/mkimage -n rk3308 -T rksd -d $RKBIN_DIR/$DDR_BLOB idbloader.bin &&
					cat $RKBIN_DIR/$MINILOADER_BLOB >> idbloader.bin
			fi &&
			run_host_x86_binary_logged $RKBIN_DIR/tools/trust_merger --replace bl31.elf $RKBIN_DIR/$BL31_BLOB trust.ini
	}

	family_tweaks_bsp() { #Install udev script that derives fixed, unique MAC addresses for net interfaces

		#that are assigned random ones -- like RockPI-S's WiFi network interfaces
		bsp=$SRC/packages/bsp/rockpis
		rules=etc/udev/rules.d

		install -m 755 $bsp/lib/udev/fixEtherAddr $destination/lib/udev &&
			install -m 644 $bsp/$rules/05-fixMACaddress.rules $destination/$rules
	}

}
