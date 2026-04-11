# SPDX-License-Identifier: GPL-2.0
dtbo-$(CONFIG_SOC_SPACEMIT_K1X) += \
	k1-can0.dtbo \
	k1-i2c3.dtbo \
	k1-i2c4.dtbo \
	k1-lcd.dtbo \
	k1-pwm7.dtbo \
	k1-pwm9.dtbo \
	k1-spi3-cs0-spidev.dtbo \
	k1-uart5.dtbo \
	k1-uart8.dtbo \
	k1-uart9.dtbo \
	k1-spacemit-disable-qspi.dtbo \
	k1-spacemit-i2c4-pwm7-spi3-uart5.dtbo

scr-$(CONFIG_SOC_SPACEMIT_K1X) += \
       spacemit-fixup.scr

dtb-y += $(dtbo-y) $(scr-y) $(dtbotxt-y)

clean-files    := *.dtbo *.scr
