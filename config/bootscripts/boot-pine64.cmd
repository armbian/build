
setenv rootdev "/dev/mmcblk0p1"

if ext4load mmc 0 0x00000000 /boot/.next || fatload mmc 0 0x00000000 .next || ext4load mmc 0 0x00000000 .next; then
	setenv bootargs "console=ttyS0,115200 root=${rootdev} rootwait rootfstype=ext4 panic=10 consoleblank=0 enforcing=0 loglevel=1"
	load mmc 0 ${fdt_addr_r} /boot/dtb/allwinner/${fdtfile} || load mmc 0 ${fdt_addr_r} /dtb/allwinner/${fdtfile}
	load mmc 0 ${ramdisk_addr_r} /boot/uInitrd || load mmc 0 ${ramdisk_addr_r} uInitrd
	load mmc 0 ${kernel_addr_r} /boot/Image || load mmc 0 ${kernel_addr_r} Image
	booti ${kernel_addr_r} ${ramdisk_addr_r} ${fdt_addr_r}
else
	setenv bootargs "console=ttyS0,115200n8 no_console_suspend earlycon=uart,mmio32,0x01c28000 mac_addr=${ethaddr} root=${rootdev} rootwait panic=10 consoleblank=0 enforcing=0 loglevel=2 ${extraargs}"
	ext4load mmc 0 ${fdt_addr} /boot/${pine64_model}.dtb || fatload mmc 0 ${fdt_addr} ${pine64_model}.dtb || ext4load mmc 0 ${fdt_addr} ${pine64_model}.dtb
	ext4load mmc 0 ${initrd_addr} /boot/uInitrd || fatload mmc 0 ${initrd_addr} uInitrd || ext4load mmc 0 ${initrd_addr} uInitrd || setenv initrd_addr "-"
	ext4load mmc 0 ${kernel_addr} /boot/Image || fatload mmc 0 ${kernel_addr} Image || ext4load mmc 0 ${kernel_addr} Image

	# set display resolution from uEnv.txt or other environment file
	# default to 720p60
	if test "${disp_mode}" = "480i"; then setenv fdt_disp_mode "<0x00000000>"
	elif test "${disp_mode}" = "576i"; then setenv fdt_disp_mode "<0x00000001>"
	elif test "${disp_mode}" = "480p"; then setenv fdt_disp_mode "<0x00000002>"
	elif test "${disp_mode}" = "576p"; then setenv fdt_disp_mode "<0x00000003>"
	elif test "${disp_mode}" = "720p50"; then setenv fdt_disp_mode "<0x00000004>"
	elif test "${disp_mode}" = "720p60"; then setenv fdt_disp_mode "<0x00000005>"
	elif test "${disp_mode}" = "1080i50"; then setenv fdt_disp_mode "<0x00000006>"
	elif test "${disp_mode}" = "1080i60"; then setenv fdt_disp_mode "<0x00000007>"
	elif test "${disp_mode}" = "1080p24"; then setenv fdt_disp_mode "<0x00000008>"
	elif test "${disp_mode}" = "1080p50"; then setenv fdt_disp_mode "<0x00000009>"
	elif test "${disp_mode}" = "1080p60"; then setenv fdt_disp_mode "<0x0000000a>"
	elif test "${disp_mode}" = "2160p30"; then setenv fdt_disp_mode "<0x0000001c>"
	elif test "${disp_mode}" = "2160p25"; then setenv fdt_disp_mode "<0x0000001d>"
	elif test "${disp_mode}" = "2160p24"; then setenv fdt_disp_mode "<0x0000001e>"
	else setenv fdt_disp_mode "<0x00000005>"
	fi

	fdt addr ${fdt_addr}
	fdt resize
	fdt set /soc@01c00000/disp@01000000 screen0_output_mode ${fdt_disp_mode}
	#fdt set /soc@01c00000/disp@01000000 screen1_output_mode ${fdt_disp_mode}

	# DVI compatibility
	if test ${disp_dvi_compat} = 1 || test ${disp_dvi_compat} = on; then
		fdt set /soc@01c00000/hdmi@01ee0000 hdmi_hdcp_enable "<0x00000000>"
		fdt set /soc@01c00000/hdmi@01ee0000 hdmi_cts_compatibility "<0x00000001>"
	fi

	booti ${kernel_addr} ${initrd_addr} ${fdt_addr}
fi

# Recompile with:
# mkimage -C none -A arm -T script -d /boot/boot.cmd /boot/boot.scr
