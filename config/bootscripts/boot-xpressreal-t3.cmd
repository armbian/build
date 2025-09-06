setenv load_addr "0x09000000"
setenv kernel_addr_r "0x08000000"
setenv ramdisk_addr_r "0x20000000"
setenv fdt_addr_r "0x02100000"

setenv rootfstype "ext4"
setenv rootdev "/dev/mmcblk0p1"
setenv fdtfile "realtek/rtd1619b-bleedingedge-4gb.dtb"

setenv console "both"
setenv bootlogo "false"
setenv verbosity "1"
setenv earlycon "off"
setenv docker_optimizations "off"
setenv extraboardargs "uio_pdrv_genirq.of_id=generic-uio firmware_class.path=/lib/firmware/realtek/rtd1619b/ pd_ignore_unused clk_ignore_unused video=HDMI-A-1:1920x1080@30"

test -n "${distro_bootpart}" || distro_bootpart=1
echo "Boot script loaded from ${devtype} ${devnum}:${distro_bootpart}"

if test -e ${devtype} ${devnum}:${distro_bootpart} ${prefix}armbianEnv.txt; then
	load ${devtype} ${devnum}:${distro_bootpart} ${load_addr} ${prefix}armbianEnv.txt
	env import -t ${load_addr} ${filesize}
fi

if test "${console}" = "display" || test "${console}" = "both"; then setenv consoleargs "console=tty1"; fi
if test "${console}" = "serial" || test "${console}" = "both"; then setenv consoleargs "console=ttyS0,460800 ${consoleargs}"; fi
if test "${earlycon}" = "on"; then setenv consoleargs "earlycon=uart8250,mmio32,0x98007800 ${consoleargs}"; fi
if test "${bootlogo}" = "true"; then
	setenv consoleargs "splash plymouth.ignore-serial-consoles ${consoleargs}"
else
	setenv consoleargs "splash=verbose ${consoleargs}"
fi

# get PARTUUID of first partition on SD/eMMC the boot script was loaded from
if test "${devtype}" = "mmc"; then part uuid mmc ${devnum}:${distro_bootpart} partuuid; fi

setenv bootargs "root=${rootdev} rootwait rootfstype=${rootfstype} ${consoleargs} consoleblank=0 loglevel=${verbosity} ubootpart=${partuuid} usb-storage.quirks=${usbstoragequirks} ${extraargs} ${extraboardargs}"

if test "${docker_optimizations}" = "on"; then setenv bootargs "${bootargs} cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory"; fi

load ${devtype} ${devnum}:${distro_bootpart} ${kernel_addr_r} ${prefix}Image
load ${devtype} ${devnum}:${distro_bootpart} ${ramdisk_addr_r} ${prefix}uInitrd
load ${devtype} ${devnum}:${distro_bootpart} ${fdt_addr_r} ${prefix}dtb/${fdtfile}

booti ${kernel_addr_r} ${ramdisk_addr_r} ${fdt_addr_r}

# Recompile with:
# mkimage -C none -A arm -T script -d /boot/boot.cmd /boot/boot.scr
