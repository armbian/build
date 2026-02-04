# SPDX-License-Identifier: GPL-2.0
dtbo-$(CONFIG_SOC_SPACEMIT_K1X) += \
	k1-spacemit-disable-qspi.dtbo \
	k1-spacemit-i2c4-pwm7-spi3-uart5.dtbo

scr-$(CONFIG_SOC_SPACEMIT_K1X) += \
       spacemit-fixup.scr

dtb-y += $(dtbo-y) $(scr-y) $(dtbotxt-y)

clean-files    := *.dtbo *.scr
