// SPDX-License-Identifier: GPL-2.0+
/*
 * (C) Copyright 2020 Aditya Prayoga (aditya@kobol.io)
 */

#include <init.h>
#include <stdio.h>
#include <dm.h>
#include <env.h>
#include <log.h>
#include <led.h>
#include <pci.h>
#include <power/regulator.h>
#include <scsi.h>
#include <spl_gpio.h>
#include <syscon.h>
#include <usb.h>
#include <linux/delay.h>
#include <asm/io.h>
#include <asm/gpio.h>
#include <asm/arch-rockchip/clock.h>
#include <asm/arch-rockchip/gpio.h>
#include <asm/arch-rockchip/grf_rk3399.h>
#include <asm/arch-rockchip/hardware.h>
#include <asm/arch-rockchip/boot_mode.h>
#include <asm/arch-rockchip/periph.h>

#include "sys_otp.h"

int rockchip_cpuid_from_efuse(const u32 cpuid_offset, const u32 cpuid_length,
			      u8 *cpuid);
int rockchip_cpuid_set(const u8 *cpuid, u8 len);
int rockchip_setup_macaddr(void);

#ifndef CONFIG_TPL_BUILD
int board_early_init_f(void)
{
#ifdef CONFIG_SPL_BUILD
#define GPIO0_BASE      0xff720000
#define GRF_BASE		0xff770000
	struct rk3399_grf_regs * const grf = (void *)GRF_BASE;
	struct rockchip_gpio_regs * const gpio = (void *)GPIO0_BASE;

	/* Turn ON status LED. At this stage, FDT & DM is not initialized yet */
	spl_gpio_output(gpio, GPIO(BANK_B, 4), 1);
#endif
	return 0;
}
#endif

#ifndef CONFIG_SPL_BUILD
int board_early_init_r(void)
{
	read_otp_data();
	return 0;
}
#endif

#ifdef CONFIG_MISC_INIT_R
#define GRF_IO_VSEL_BT565_SHIFT		0
#define GRF_IO_VSEL_AUDIO_SHIFT		1
#define GRF_IO_VSEL_SDMMC_SHIFT		2
#define GRF_IO_VSEL_GPIO1830_SHIFT	3

#define PMUGRF_CON0_VSEL_SHIFT		8
#define PMUGRF_CON0_PMU1830_VOL_SHIFT   9
static void setup_iodomain(void)
{
	struct rk3399_grf_regs *grf =
		syscon_get_first_range(ROCKCHIP_SYSCON_GRF);
	struct rk3399_pmugrf_regs *pmugrf =
		syscon_get_first_range(ROCKCHIP_SYSCON_PMUGRF);

	/* BT565 is in 1.8v domain */
	rk_setreg(&grf->io_vsel, 1 << GRF_IO_VSEL_BT565_SHIFT);

	/* AUDIO is in 1.8v domain */
	rk_setreg(&grf->io_vsel, 1 << GRF_IO_VSEL_AUDIO_SHIFT);

	/* SDMMC is in 3.0v domain */
	rk_setreg(&grf->io_vsel, 0 << GRF_IO_VSEL_SDMMC_SHIFT);

	/* GPIO1830 is in 3.0v domain */
	rk_setreg(&grf->io_vsel, 0 << GRF_IO_VSEL_GPIO1830_SHIFT);

	/* Set GPIO1 1.8v/3.0v source select to PMU1830_VOL */
	rk_setreg(&pmugrf->soc_con0, 1 << PMUGRF_CON0_VSEL_SHIFT);
	rk_setreg(&pmugrf->soc_con0, 0 << PMUGRF_CON0_PMU1830_VOL_SHIFT);
}

static void init_vdd_center(void)
{
	struct udevice *regulator;
	struct dm_regulator_uclass_plat *uc_pdata;
	int ret;

	ret = regulator_get_by_platname("vdd_center", &regulator);
	if (ret)
		return;

	uc_pdata = dev_get_uclass_plat(regulator);
	ret = regulator_set_value(regulator, uc_pdata->init_uV);
	if (ret)
		debug("%s vdd_center init fail! ret %d\n", __func__, ret);
}

/*
 * Swap mmc0 and mmc1 in boot_targets if booted from SD-Card.
 *
 * If bootsource is uSD-card we can assume that we want to use the
 * SD-Card instead of the eMMC as first boot_target for distroboot.
 * We only want to swap the defaults and not any custom environment a
 * user has set. We exit early if a changed boot_targets environment
 * is detected.
 */
static int setup_boottargets(void)
{
	const char *boot_device =
		ofnode_read_chosen_string("u-boot,spl-boot-device");
	char *env_default, *env;

	if (!boot_device) {
		debug("%s: /chosen/u-boot,spl-boot-device not set\n",
		      __func__);
		return -1;
	}
	debug("%s: booted from %s\n", __func__, boot_device);

	env_default = env_get_default("boot_targets");
	env = env_get("boot_targets");
	if (!env) {
		debug("%s: boot_targets does not exist\n", __func__);
		return -1;
	}
	debug("%s: boot_targets current: %s - default: %s\n",
		__func__, env, env_default);

	if (strcmp(env_default, env) != 0) {
		debug("%s: boot_targets not default, don't change it\n",
			__func__);
		return 0;
	}

	/*
	 * Only run, if booting from mmc1 (i.e. /mmc@fe320000) and
	 * only consider cases where the default boot-order first
	 * tries to boot from mmc0 (eMMC) and then from mmc1
	 * (i.e. external SD).
	 *
	 * In other words: the SD card will be moved to earlier in the
	 * order, if U-Boot was also loaded from the SD-card.
	 */
	if (!strcmp(boot_device, "/mmc@fe320000")) {
		char *mmc0, *mmc1;

		debug("%s: booted from SD-Card\n", __func__);
		mmc0 = strstr(env, "mmc0");
		mmc1 = strstr(env, "mmc1");

		if (!mmc0 || !mmc1) {
			debug("%s: only one mmc boot_target found\n", __func__);
			return -1;
		}

		/*
		 * If mmc0 comes first in the boot order, we need to change
		 * the strings to make mmc1 first.
		 */
		if (mmc0 < mmc1) {
			mmc0[3] = '1';
			mmc1[3] = '0';
			debug("%s: set boot_targets to: %s\n", __func__, env);
			env_set("boot_targets", env);
		}
	}

	return 0;
}

static void setup_leds(void)
{
	struct udevice *dev;

	led_get_by_label("helios64::status", &dev);
	led_set_state(dev, LEDST_OFF);
	mdelay(250);
	led_set_state(dev, LEDST_ON);
}

int misc_init_r(void)
{
	const u32 cpuid_offset = 0x7;
	const u32 cpuid_length = 0x10;
	u8 cpuid[cpuid_length];
	int ret;

	setup_iodomain();
	init_vdd_center();
	set_board_info();

	ret = rockchip_cpuid_from_efuse(cpuid_offset, cpuid_length, cpuid);
	if (ret)
		return ret;

	ret = rockchip_cpuid_set(cpuid, cpuid_length);
	if (ret)
		return ret;

	if (mac_read_from_otp())
		ret = rockchip_setup_macaddr();

	setup_boottargets();
	setup_leds();

	return ret;
}
#endif

#ifdef CONFIG_ROCKCHIP_ADVANCED_RECOVERY
void rockchip_prepare_download_mode(void)
{
	struct gpio_desc *enable, *mux;

	if (gpio_hog_lookup_name("USB_MUX_OE#", &enable)) {
		debug("Fail to get USB_MUX_OE\n");
		return;
	}

	if (gpio_hog_lookup_name("USB_MUX_HS", &mux)) {
		debug("Fail to get USB_MUX_HS\n");
		return;
	}

	dm_gpio_set_value(enable, 0);
	mdelay(100);
	dm_gpio_set_value(mux, 1);
	mdelay(100);
	dm_gpio_set_value(enable, 1);
}
#endif

#ifdef CONFIG_LAST_STAGE_INIT
static void auto_power_enable(void)
{
	struct gpio_desc *enable, *clock;

	if (gpio_hog_lookup_name("AUTO_ON_EN_D", &enable)) {
		debug("Fail to get AUTO_ON_EN_D\n");
		return;
	}

	if (gpio_hog_lookup_name("AUTO_ON_EN_CLK", &clock)) {
		debug("Fail to get AUTO_ON_EN_CLK\n");
		return;
	}

	dm_gpio_set_value(enable, 1);
	dm_gpio_set_value(clock, 1);
	mdelay(10);
	dm_gpio_set_value(clock, 0);
}

static void sata_power_enable(void)
{
	struct udevice *rail_a, *rail_b;
	int ret;

	ret = regulator_get_by_platname("hdd_a_power", &rail_a);
	if (!ret) {
		ret = regulator_set_enable(rail_a, true);
		if (!ret)
			/* Wait for HDD spinup before SCSI scan */
			mdelay(10000);
	}

	ret = regulator_get_by_platname("hdd_b_power", &rail_b);
	if (!ret)
		ret = regulator_set_enable(rail_b, true);

}

int last_stage_init(void)
{
	auto_power_enable();
	sata_power_enable();

#ifdef CONFIG_PCI
	scsi_scan(true);
#endif

	return 0;
}
#endif

#if defined(CONFIG_DISPLAY_BOARDINFO_LATE)
int checkboard(void)
{
	int major, minor;

	printf("Revision: ");

	if (!get_revision(&major, &minor))
		printf("%i.%i - %s\n", major, minor, get_variant());
	else
		printf("UNKNOWN\n");

	return 0;
}
#endif

#if defined(CONFIG_OF_LIBFDT) && defined(CONFIG_OF_BOARD_SETUP)
int ft_board_setup(void *blob, struct bd_info *bd)
{
	char *env;

	env = env_get("board_rev");
	if (env)
		fdt_setprop_string(blob, fdt_path_offset(blob, "/"),
			"kobol,board-rev", env);

	env = env_get("cpuid#");
	if (env)
		fdt_setprop_string(blob, fdt_path_offset(blob, "/"),
			"kobol,cpu-id", env);

	return 0;
}
#endif
