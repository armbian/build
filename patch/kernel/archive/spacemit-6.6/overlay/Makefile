# SPDX-License-Identifier: GPL-2.0
dtbo-$(CONFIG_ARCH_RV64I) += \
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

targets += dtbs dtbs_install
targets += $(dtbo-y)

always-y	:= $(dtbo-y)
clean-files	:= *.dtbo
