setenv boot_interface mmc
setenv image_name boot/Image
setenv fdt_name boot/dtb/marvell/armada-3720-community.dtb
setenv rootdev "/dev/mmcblk0p1"
setenv rootfstype "ext4"
setenv verbosity "1"
setenv initrd_image boot/uInitrd
setenv bootcmd 'mmc dev 0; ext4load mmc 0:1 $kernel_addr $image_name;ext4load mmc 0:1 $initrd_addr $initrd_image; ext4load mmc 0:1 $fdt_addr $fdt_name;setenv bootargs $console root=$rootdev rw rootwait; ext4load ${boot_interface} 0:1 ${loadaddr} boot/armbianEnv.txt; env import -t ${loadaddr} ${filesize};  booti $kernel_addr - $fdt_addr'
