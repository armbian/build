BOARD_NAME="Khadas VIM3"
BOARDFAMILY="vim"
BOOTCONFIG="khadas-vim3_defconfig"
MODULES=""
MODULES_NEXT=""
KERNEL_TARGET="dev"
FULL_DESKTOP="yes"

uboot_g12b_postprocess()
{
	mv u-boot.bin bl33.bin

	$1/$2/blx_fix.sh $1/$2/bl30.bin \
				$1/$2/zero_tmp \
				$1/$2/bl30_zero.bin \
				$1/$2/bl301.bin \
				$1/$2/bl301_zero.bin \
				$1/$2/bl30_new.bin \
				bl30

	$1/$2/blx_fix.sh $1/$2/bl2.bin \
				$1/$2/zero_tmp \
				$1/$2/bl2_zero.bin \
				$1/$2/acs.bin \
				$1/$2/bl21_zero.bin \
				$1/$2/bl2_new.bin \
				bl2

	$1/$2/aml_encrypt_g12b --bl30sig --input $1/$2/bl30_new.bin \
					--output $1/$2/bl30_new.bin.g12a.enc \
					--level v3
	$1/$2/aml_encrypt_g12b --bl3sig --input $1/$2/bl30_new.bin.g12a.enc \
					--output $1/$2/bl30_new.bin.enc \
					--level v3 --type bl30
	$1/$2/aml_encrypt_g12b --bl3sig --input $1/$2/bl31.img \
					--output $1/$2/bl31.img.enc \
					--level v3 --type bl31
	$1/$2/aml_encrypt_g12b --bl3sig --input bl33.bin --compress lz4 \
					--output $1/$2/bl33.bin.enc \
					--level v3 --type bl33 --compress lz4
	$1/$2/aml_encrypt_g12b --bl2sig --input $1/$2/bl2_new.bin \
					--output $1/$2/bl2.n.bin.sig
	$1/$2/aml_encrypt_g12b --bootmk \
					--output u-boot.bin \
					--bl2 $1/$2/bl2.n.bin.sig \
					--bl30 $1/$2/bl30_new.bin.enc \
					--bl31 $1/$2/bl31.img.enc \
					--bl33 $1/$2/bl33.bin.enc \
					--ddrfw1 $1/$2/ddr4_1d.fw \
					--ddrfw2 $1/$2/ddr4_2d.fw \
					--ddrfw3 $1/$2/ddr3_1d.fw \
					--ddrfw4 $1/$2/piei.fw \
					--ddrfw5 $1/$2/lpddr4_1d.fw \
					--ddrfw6 $1/$2/lpddr4_2d.fw \
					--ddrfw7 $1/$2/diag_lpddr4.fw \
					--ddrfw8 $1/$2/aml_ddr.fw \
					--ddrfw9 $1/$2/lpddr3_1d.fw \
					--level v3
}

uboot_custom_postprocess()
{
	uboot_g12b_postprocess $SRC/cache/sources/khadas-blobs/ vim3
}

write_uboot_platform()
{
	dd if=$1/u-boot.bin of=$2 conv=fsync,notrunc bs=512 skip=1 seek=1 > /dev/null 2>&1
	dd if=$1/u-boot.bin of=$2 conv=fsync,notrunc bs=1 count=444 > /dev/null 2>&1
}
