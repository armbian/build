# Agilex 5 boot script.
# U-Boot SPL (programmed into QSPI) loads u-boot.itb from this FAT partition,
# then U-Boot sources this script from a fixed DRAM address.
#
# Optional: copy the design's core fabric image to ghrd.core.rbf on this
# partition. It is loaded and the bridges are enabled before Linux starts.

setenv kernel_addr_r 0x82000000
setenv fdt_addr_r 0x88000000
setenv ramdisk_addr_r 0x90000000
setenv env_addr_r 0x8e000000

setenv rootdev "/dev/mmcblk0p2"
setenv rootfstype "ext4"
setenv verbosity "1"
setenv console "serial"
setenv bootlogo "false"
setenv earlycon "on"
setenv fdtfile "intel/socfpga_agilex5_socdk.dtb"
setenv docker_optimizations "on"

if fatload mmc 0:1 ${env_addr_r} armbianEnv.txt; then
	env import -t ${env_addr_r} ${filesize}
fi

if fatload mmc 0:1 ${kernel_addr_r} ghrd.core.rbf; then
	echo "Configuring FPGA core from ghrd.core.rbf"
	fpga load 0 ${kernel_addr_r} ${filesize}
	bridge enable
fi

setenv consoleargs ""
if test "${console}" = "serial" || test "${console}" = "both"; then
	setenv consoleargs "console=ttyS0,115200"
fi
if test "${earlycon}" = "on"; then
	setenv consoleargs "earlycon ${consoleargs}"
fi

setenv bootargs "root=${rootdev} rootwait rootfstype=${rootfstype} ${consoleargs} consoleblank=0 loglevel=${verbosity} ${extraargs} ${extraboardargs}"

if test "${docker_optimizations}" = "on"; then
	setenv bootargs "${bootargs} cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory"
fi

echo "Booting Agilex 5 with ${bootargs}"

fatload mmc 0:1 ${kernel_addr_r} Image
if fatload mmc 0:1 ${ramdisk_addr_r} uInitrd; then
	setenv ramdisk_arg "${ramdisk_addr_r}:${filesize}"
else
	echo "No uInitrd, continuing without an initramfs"
	setenv ramdisk_arg "-"
fi
fatload mmc 0:1 ${fdt_addr_r} dtb/${fdtfile}
booti ${kernel_addr_r} ${ramdisk_arg} ${fdt_addr_r}
