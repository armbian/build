# SPDX-License-Identifier: GPL-2.0
dtbo-$(CONFIG_ARCH_MESON) += \
	meson-i2cA.dtbo \
	meson-i2cB.dtbo \
	meson-uartA.dtbo \
	meson-uartC.dtbo \
	meson-w1-gpio.dtbo \
	meson-w1AB-gpio.dtbo \
	meson-g12-gxl-cma-pool-896MB.dtbo

scr-$(CONFIG_ARCH_MESON) += \
       meson-fixup.scr

dtbotxt-$(CONFIG_ARCH_MESON) += \
       README.meson-overlays

targets += $(dtbo-y) $(scr-y) $(dtbotxt-y)

always         := $(dtbo-y) $(scr-y) $(dtbotxt-y)
clean-files    := *.dtbo *.scr
