# u-boot patches for the rafaello7 nanopi3 2016.01 fork (S5P6818)

Intentionally empty. The rafaello7 fork (BOOTSOURCE in
config/sources/families/s5p6818.conf, tag v1.2) is the known-good bootloader
and needs no Armbian patches. The boot image (NSIH + BL1 + u-boot.bin) is
assembled by uboot_custom_postprocess() in the family conf.
