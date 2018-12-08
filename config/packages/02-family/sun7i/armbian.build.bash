#!/bin/bash
#

arm-linux-gnueabihf-gcc $SRC/packages/bsp/sunxi-temp/sunxi_tp_temp.c -o $destination/usr/bin/sunxi_tp_temp
# convert and add fex files
mkdir -p ${upperdir}/boot/bin

for i in $(ls -w1 $SRC/config/fex/*.fex | xargs -n1 basename); do
	fex2bin $SRC/config/fex/${i%*.fex}.fex ${upperdir}/boot/bin/${i%*.fex}.bin
done
