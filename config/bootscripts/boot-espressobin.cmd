
setenv boot_interface mmc
setenv image_name boot/Image
setenv fdt_name boot/dtb/marvell/armada-3720-community.dtb
setenv rootdev "/dev/mmcblk0p1"
setenv rootfstype "ext4"
setenv verbosity "1"
setenv initrd_image "boot/initrd.img-4.4.8-mvebu64"
setenv ethaddr "F0:AD:4E:03:64:7F"
setenv bootcmd 'mmc dev 0; ext4load mmc 0:1 $kernel_addr $image_name;ext4load mmc 0:1 $initrd_addr $initrd_image; ext4load mmc 0:1 $fdt_addr $fdt_name;setenv bootargs $console root=$rootdev rw rootwait; booti $kernel_addr - $fdt_addr'

