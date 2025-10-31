# Rockchip RK3582 SoC
BOARD_NAME="Radxa E54C"
BOARDFAMILY="rockchip-rk3588"
BOARD_MAINTAINER="kamilsaigol"
BOOTCONFIG="radxa-e54c-rk3588s_defconfig"
KERNEL_TARGET="vendor"
BOOT_FDT_FILE="rockchip/rk3588s-radxa-e54c.dtb"
BOOT_SCENARIO="spl-blobs"
BOOT_SOC="rk3588"
IMAGE_PARTITION_TABLE="gpt"


# The kernel config hooks are always called twice, once without being in kernel directory and once with current directory being the kernel work directory.
# Enable the distributed switch architecture to expose the individual LAN and WAN interfaces.
function custom_kernel_config__radxa_e54c_enable_ethernet_switch_arch() {
	if [[ ! -f .config ]]; then
		# kernel_config_modifying_hashes is only needed during first call of this function to calculate kernel artifact version string. It serves no purpose whatsoever during second call.
		kernel_config_modifying_hashes+=("CONFIG_NET_DSA=m" "CONFIG_NET_DSA_REALTEK=m" "CONFIG_NET_DSA_REALTEK_MDIO=m" "CONFIG_NET_DSA_REALTEK_SMI=m" "CONFIG_NET_DSA_REALTEK_RTL8365MB=m" "CONFIG_NET_DSA_REALTEK_RTL8366RB=m")
	else
		display_alert "$BOARD" "Enable Realtek Distributed Switch" "info"
		kernel_config_set_m NET_DSA
		kernel_config_set_m NET_DSA_REALTEK
		kernel_config_set_m NET_DSA_REALTEK_MDIO
        kernel_config_set_m NET_DSA_REALTEK_SMI
        kernel_config_set_m NET_DSA_REALTEK_RTL8365MB
        kernel_config_set_m NET_DSA_REALTEK_RTL8366RB
	fi
}

# Enable system and network LEDs
function post_family_tweaks_bsp__radxa_e54c_enable_leds() {
	display_alert "$BOARD" "Creating Board Support LED Config" "info"
	cat <<- EOF > "${destination}"/etc/armbian-leds.conf
	    [/sys/class/leds/lan1-led]
		trigger=netdev
		interval=52
		brightness=1
		link=1
		tx=0
		rx=1
		device_name=lan1@end1

        [/sys/class/leds/lan2-led]
		trigger=netdev
		interval=52
		brightness=1
		link=1
		tx=0
		rx=1
		device_name=lan2@end1

        [/sys/class/leds/lan3-led]
		trigger=netdev
		interval=52
		brightness=1
		link=1
		tx=0
		rx=1
		device_name=lan3@end1
		
		[/sys/class/leds/wan-led]
		trigger=netdev
		interval=52
		brightness=1
		link=1
		tx=0
		rx=1
		device_name=wan@end1
		
		[/sys/class/leds/mmc0::]
		trigger=mmc0
		brightness=0
		
		[/sys/class/leds/sys-led]
		trigger=heartbeat
		brightness=0
		invert=0
	EOF
}
