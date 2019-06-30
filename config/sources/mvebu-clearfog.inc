case $BRANCH in
	default|next|dev)

		BOOTDIR='u-boot-armada'
		BOOTSOURCE='https://github.com/SolidRun/u-boot'
		BOOTBRANCH='branch:v2018.01-solidrun-a38x'
		BOOTSCRIPT='boot-mvebu-next.cmd:boot.cmd'
		BOOTPATCHDIR='u-boot-mvebu'	
		UBOOT_TARGET_MAP=";;*.kwb"
	        UBOOT_USE_GCC='> 7.0'
	        UBOOT_COMPILER='arm-linux-gnueabihf-'

	;;
esac

uboot_custom_postprocess()
{
	# create remaining targets
	targets=( mmc sata spi uart )
	for i in "${targets[@]}"
        do
       
        # More info https://developer.solid-run.com/knowledge-base/a388-u-boot/#compiling-from-source
		
		# adjust target name
		sed -i 's/^CONFIG_MVEBU_UBOOT_DFLT_NAME.*/CONFIG_MVEBU_UBOOT_DFLT_NAME="'u-boot-spl-${i}.kwb'"/g' configs/clearfog_defconfig
		sed -i 's/^CONFIG_MVEBU_SPL_BOOT_DEVICE.*/CONFIG_MVEBU_SPL_BOOT_DEVICE_'${i^^}'=y/g' configs/clearfog_defconfig

        if [[ $BOARD == clearfogbase ]]; then
                sed -i '/^CONFIG_TARGET_CLEARFOG=y/d' configs/clearfog_defconfig
                echo "CONFIG_TARGET_CLEARFOG_BASE=y" >> configs/clearfog_defconfig
		fi

		make clearfog_defconfig
        make $CTHREADS
done
}

write_uboot_platform()
{
	dd if=$1/u-boot-spl-sdhc.kwb of=$2 bs=512 seek=1 status=noxfer > /dev/null 2>&1
}
