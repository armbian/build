BOARD_NAME="Khadas VIM2"
BOARDFAMILY="vim"
BOOTCONFIG="khadas-vim2_defconfig"
MODULES=""
MODULES_NEXT=""
KERNEL_TARGET="dev"
FULL_DESKTOP="yes"

uboot_gxm_postprocess()
{
	mv u-boot.bin bl33.bin

	$1/$2/blx_fix.sh 	$1/$2/bl30.bin \
					$1/$2/zero_tmp \
					$1/$2/bl30_zero.bin \
					$1/$2/bl301.bin \
					$1/$2/bl301_zero.bin \
					$1/$2/bl30_new.bin \
					bl30

	python $1/acs_tool.pyc $1/$2/bl2.bin $1/$2/bl2_acs.bin $1/$2/acs.bin 0

	$1/$2/blx_fix.sh	$1/$2/bl2_acs.bin \
					$1/$2/zero_tmp \
					$1/$2/bl2_zero.bin \
					$1/$2/bl21.bin \
					$1/$2/bl21_zero.bin \
					$1/$2/bl2_new.bin \
					bl2

	$1/$2/aml_encrypt_gxl --bl3enc --input $1/$2/bl30_new.bin
	$1/$2/aml_encrypt_gxl --bl3enc --input $1/$2/bl31.img
	$1/$2/aml_encrypt_gxl --bl3enc --input bl33.bin
	$1/$2/aml_encrypt_gxl --bl2sig --input $1/$2/bl2_new.bin --output $1/$2/bl2.n.bin.sig
	$1/$2/aml_encrypt_gxl --bootmk \
						--output u-boot.bin \
						--bl2 $1/$2/bl2.n.bin.sig \
						--bl30 $1/$2/bl30_new.bin.enc \
						--bl31 $1/$2/bl31.img.enc \
						--bl33 bl33.bin.enc
}

uboot_custom_postprocess()
{
	uboot_gxm_postprocess $SRC/cache/sources/khadas-blobs/ vim2
}

write_uboot_platform()
{
	dd if=$1/u-boot.bin of=$2 conv=fsync,notrunc bs=512 skip=1 seek=1 > /dev/null 2>&1
	dd if=$1/u-boot.bin of=$2 conv=fsync,notrunc bs=1 count=444 > /dev/null 2>&1
}
