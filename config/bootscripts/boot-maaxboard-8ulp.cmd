# Avnet MaaXBoard 8ULP uEnv.txt (FAT /boot, partition 1)
# Kernel, DTB, and initrd live on the VFAT boot partition; root is partition 2.
fdt_file=maaxboard-8ulp.dtb
fdt_addr_r=0x84000000
fdt_addr=0x84000000
ramdisk_addr_r=0x85000000
initrd=initrd
# Avnet uEnv pattern: optargs is appended by U-Boot mmcargs
console=ttyLP1,115200 console=tty1
optargs=quiet loglevel=4
mmcdev=0
mmcpart=1
loadkernel=fatload mmc ${mmcdev}:${mmcpart} ${loadaddr} Image
loadfdt=fatload mmc ${mmcdev}:${mmcpart} ${fdt_addr_r} ${fdt_file}
loadinitrd=fatload mmc ${mmcdev}:${mmcpart} ${ramdisk_addr_r} ${initrd}
setuproot=part uuid mmc ${mmcdev}:2 uuid; setenv mmcroot PARTUUID=${uuid}
mmcargs=setenv bootargs console=${console} root=${mmcroot} rootwait rw ${optargs}
boot_os=run setuproot; run mmcargs; run loadkernel; run loadfdt; run loadinitrd; booti ${loadaddr} ${ramdisk_addr_r}:${filesize} ${fdt_addr_r}
