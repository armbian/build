// SPDX-License-Identifier: GPL-2.0-only
/*
 * LP5812 LED driver
 *
 * Copyright (C) 2025 Texas Instruments
 *
 * Author: Jared Zhou <jared-zhou@ti.com>
 */

#include <linux/delay.h>
#include <linux/i2c.h>
#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/led-class-multicolor.h>
#include <linux/leds.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/sysfs.h>
#include <linux/types.h>

#include "leds-lp5812.h"

static const struct lp5812_mode_mapping chip_mode_map[] = {
	{"direct_mode", 0, 0, 0, 0, 0, 0},
	{"tcm:1:0", 1, 0, 0, 0, 0, 0},
	{"tcm:1:1", 1, 1, 0, 0, 0, 0},
	{"tcm:1:2", 1, 2, 0, 0, 0, 0},
	{"tcm:1:3", 1, 3, 0, 0, 0, 0},
	{"tcm:2:0:1", 2, 0, 1, 0, 0, 0},
	{"tcm:2:0:2", 2, 0, 2, 0, 0, 0},
	{"tcm:2:0:3", 2, 0, 3, 0, 0, 0},
	{"tcm:2:1:2", 2, 1, 2, 0, 0, 0},
	{"tcm:2:1:3", 2, 1, 3, 0, 0, 0},
	{"tcm:2:2:3", 2, 2, 3, 0, 0, 0},
	{"tcm:3:0:1:2", 3, 0, 1, 2, 0, 0},
	{"tcm:3:0:1:3", 3, 0, 1, 3, 0, 0},
	{"tcm:3:0:2:3", 3, 0, 2, 3, 0, 0},
	{"tcm:4:0:1:2:3", 4, 0, 1, 2, 3, 0},
	{"mix:1:0:1", 5, 1, 0, 0, 0, 0},
	{"mix:1:0:2", 5, 2, 0, 0, 0, 0},
	{"mix:1:0:3", 5, 3, 0, 0, 0, 0},
	{"mix:1:1:0", 5, 0, 0, 0, 0, 1},
	{"mix:1:1:2", 5, 2, 0, 0, 0, 1},
	{"mix:1:1:3", 5, 3, 0, 0, 0, 1},
	{"mix:1:2:0", 5, 0, 0, 0, 0, 2},
	{"mix:1:2:1", 5, 1, 0, 0, 0, 2},
	{"mix:1:2:3", 5, 3, 0, 0, 0, 2},
	{"mix:1:3:0", 5, 0, 0, 0, 0, 3},
	{"mix:1:3:1", 5, 1, 0, 0, 0, 3},
	{"mix:1:3:2", 5, 2, 0, 0, 0, 3},
	{"mix:2:0:1:2", 6, 1, 2, 0, 0, 0},
	{"mix:2:0:1:3", 6, 1, 3, 0, 0, 0},
	{"mix:2:0:2:3", 6, 2, 3, 0, 0, 0},
	{"mix:2:1:0:2", 6, 0, 2, 0, 0, 1},
	{"mix:2:1:0:3", 6, 0, 3, 0, 0, 1},
	{"mix:2:1:2:3", 6, 2, 3, 0, 0, 1},
	{"mix:2:2:0:1", 6, 0, 1, 0, 0, 2},
	{"mix:2:2:0:3", 6, 0, 3, 0, 0, 2},
	{"mix:2:2:1:3", 6, 1, 3, 0, 0, 2},
	{"mix:2:3:0:1", 6, 0, 1, 0, 0, 3},
	{"mix:2:3:0:2", 6, 0, 2, 0, 0, 3},
	{"mix:2:3:1:2", 6, 1, 2, 0, 0, 3},
	{"mix:3:0:1:2:3", 7, 1, 2, 3, 0, 0},
	{"mix:3:1:0:2:3", 7, 0, 2, 3, 0, 1},
	{"mix:3:2:0:1:3", 7, 0, 1, 3, 0, 2},
	{"mix:3:3:0:1:2", 7, 0, 1, 2, 0, 3}
};

static int lp5812_write(struct lp5812_chip *chip, u16 reg, u8 val)
{
	struct device *dev = &chip->client->dev;
	struct i2c_msg msg;
	u8 buf[LP5812_DATA_LENGTH];
	u8 reg_addr_bit8_9;
	int ret;

	/* Extract register address bits 9 and 8 for Address Byte 1 */
	reg_addr_bit8_9 = (reg >> LP5812_REG_ADDR_HIGH_SHIFT) & LP5812_REG_ADDR_BIT_8_9_MASK;

	/* Prepare payload: Address Byte 2 (bits [7:0]) and value to write */
	buf[LP5812_DATA_BYTE_0_IDX] = (u8)(reg & LP5812_REG_ADDR_LOW_MASK);
	buf[LP5812_DATA_BYTE_1_IDX] = val;

	/* Construct I2C message for a write operation */
	msg.addr = (chip->client->addr << LP5812_CHIP_ADDR_SHIFT) | reg_addr_bit8_9;
	msg.flags = 0;
	msg.len = sizeof(buf);
	msg.buf = buf;

	ret = i2c_transfer(chip->client->adapter, &msg, 1);
	if (ret == 1)
		return 0;

	dev_err(dev, "I2C write error, ret=%d\n", ret);
	return ret < 0 ? ret : -EIO;
}

static int lp5812_read(struct lp5812_chip *chip, u16 reg, u8 *val)
{
	struct device *dev = &chip->client->dev;
	struct i2c_msg msgs[LP5812_READ_MSG_LENGTH];
	u8 ret_val;
	u8 reg_addr_bit8_9;
	u8 converted_reg;
	int ret;

	/* Extract register address bits 9 and 8 for Address Byte 1 */
	reg_addr_bit8_9 = (reg >> LP5812_REG_ADDR_HIGH_SHIFT) & LP5812_REG_ADDR_BIT_8_9_MASK;

	/* Lower 8 bits go in Address Byte 2 */
	converted_reg = (u8)(reg & LP5812_REG_ADDR_LOW_MASK);

	/* Prepare I2C write message to set register address */
	msgs[LP5812_MSG_0_IDX].addr =
		(chip->client->addr << LP5812_CHIP_ADDR_SHIFT) | reg_addr_bit8_9;
	msgs[LP5812_MSG_0_IDX].flags = 0;
	msgs[LP5812_MSG_0_IDX].len = 1;
	msgs[LP5812_MSG_0_IDX].buf = &converted_reg;

	/* Prepare I2C read message to retrieve register value */
	msgs[LP5812_MSG_1_IDX].addr =
		(chip->client->addr << LP5812_CHIP_ADDR_SHIFT) | reg_addr_bit8_9;
	msgs[LP5812_MSG_1_IDX].flags = I2C_M_RD;
	msgs[LP5812_MSG_1_IDX].len = 1;
	msgs[LP5812_MSG_1_IDX].buf = &ret_val;

	ret = i2c_transfer(chip->client->adapter, msgs, LP5812_READ_MSG_LENGTH);
	if (ret == LP5812_READ_MSG_LENGTH) {
		*val = ret_val;
		return 0;
	}

	dev_err(dev, "I2C read error, ret=%d\n", ret);
	*val = 0;
	return ret < 0 ? ret : -EIO;
}

static int lp5812_read_tsd_config_status(struct lp5812_chip *chip, u8 *reg_val)
{
	return lp5812_read(chip, chip->cfg->reg_tsd_config_status.addr, reg_val);
}

static int lp5812_update_regs_config(struct lp5812_chip *chip)
{
	u8 reg_val;
	int ret;

	ret = lp5812_write(chip, chip->cfg->reg_cmd_update.addr, LP5812_UPDATE_CMD_VAL);
	if (ret)
		return ret;

	ret = lp5812_read_tsd_config_status(chip, &reg_val);
	if (ret)
		return ret;

	return reg_val & LP5812_CFG_ERR_STATUS_MASK;
}

static ssize_t parse_drive_mode(struct lp5812_chip *chip, const char *str)
{
	int i;

	chip->u_drive_mode.s_drive_mode.mix_sel_led_0 = false;
	chip->u_drive_mode.s_drive_mode.mix_sel_led_1 = false;
	chip->u_drive_mode.s_drive_mode.mix_sel_led_2 = false;
	chip->u_drive_mode.s_drive_mode.mix_sel_led_3 = false;

	if (sysfs_streq(str, LP5812_MODE_DIRECT_NAME)) {
		chip->u_drive_mode.s_drive_mode.led_mode = LP5812_MODE_DIRECT_VALUE;
		return 0;
	}

	for (i = 0; i < ARRAY_SIZE(chip_mode_map); i++) {
		if (sysfs_streq(str, chip_mode_map[i].mode_name)) {
			chip->u_drive_mode.s_drive_mode.led_mode = chip_mode_map[i].mode;
			chip->u_scan_order.s_scan_order.scan_order_0 =
				chip_mode_map[i].scan_order_0;
			chip->u_scan_order.s_scan_order.scan_order_1 =
				chip_mode_map[i].scan_order_1;
			chip->u_scan_order.s_scan_order.scan_order_2 =
				chip_mode_map[i].scan_order_2;
			chip->u_scan_order.s_scan_order.scan_order_3 =
				chip_mode_map[i].scan_order_3;

			switch (chip_mode_map[i].selection_led) {
			case LP5812_MODE_MIX_SELECT_LED_0:
				chip->u_drive_mode.s_drive_mode.mix_sel_led_0 = true;
				break;
			case LP5812_MODE_MIX_SELECT_LED_1:
				chip->u_drive_mode.s_drive_mode.mix_sel_led_1 = true;
				break;
			case LP5812_MODE_MIX_SELECT_LED_2:
				chip->u_drive_mode.s_drive_mode.mix_sel_led_2 = true;
				break;
			case LP5812_MODE_MIX_SELECT_LED_3:
				chip->u_drive_mode.s_drive_mode.mix_sel_led_3 = true;
				break;
			default:
				return -EINVAL;
			}

			return 0;
		}
	}

	return -EINVAL;
}

static int lp5812_set_drive_mode_scan_order(struct lp5812_chip *chip)
{
	u8 val;
	int ret;

	/* Set led mode */
	val = chip->u_drive_mode.drive_mode_val;
	ret = lp5812_write(chip, chip->cfg->reg_dev_config_1.addr, val);
	if (ret)
		return ret;

	/* Setup scan order */
	val = chip->u_scan_order.scan_order_val;
	ret = lp5812_write(chip, chip->cfg->reg_dev_config_2.addr, val);

	return ret;
}

static int lp5812_set_led_mode(struct lp5812_chip *chip, int led_number,
			       enum control_mode mode)
{
	u8 reg_val;
	u16 reg;
	int ret;

	if (led_number < LP5812_NUMBER_LED_IN_REG)
		reg = chip->cfg->reg_dev_config_3.addr;
	else
		reg = chip->cfg->reg_dev_config_4.addr;

	ret = lp5812_read(chip, reg, &reg_val);
	if (ret)
		return ret;

	if (mode == LP5812_MODE_MANUAL)
		reg_val &= ~(1 << (led_number % LP5812_NUMBER_LED_IN_REG));
	else
		reg_val |= (1 << (led_number % LP5812_NUMBER_LED_IN_REG));

	ret = lp5812_write(chip, reg, reg_val);
	if (ret)
		return ret;

	ret = lp5812_update_regs_config(chip);

	return ret;
}

static int lp5812_manual_dc_pwm_control(struct lp5812_chip *chip, int led_number,
					u8 val, enum dimming_type dimming_type)
{
	u16 led_base_reg;
	int ret;

	if (dimming_type == LP5812_DIMMING_ANALOG)
		led_base_reg = chip->cfg->reg_manual_dc_base.addr;
	else
		led_base_reg = chip->cfg->reg_manual_pwm_base.addr;
	ret = lp5812_write(chip, led_base_reg + led_number, val);

	return ret;
}

static int lp5812_auto_dc(struct lp5812_chip *chip,
			  int led_number, u8 val)
{
	return lp5812_write(chip, chip->cfg->reg_auto_dc_base.addr + led_number, val);
}

static int lp5812_multicolor_brightness(struct lp5812_led *led)
{
	int ret, i;
	struct lp5812_chip *chip = led->chip;

	guard(mutex)(&chip->lock);
	for (i = 0; i < led->mc_cdev.num_colors; i++) {
		ret = lp5812_manual_dc_pwm_control(chip, led->mc_cdev.subled_info[i].channel,
						   led->mc_cdev.subled_info[i].brightness,
						   LP5812_DIMMING_PWM);
		if (ret)
			return ret;
	}

	return 0;
}

static int lp5812_led_brightness(struct lp5812_led *led)
{
	struct lp5812_chip *chip = led->chip;
	struct lp5812_led_config *led_cfg;
	int ret;

	led_cfg = &chip->led_config[led->chan_nr];

	guard(mutex)(&chip->lock);
	ret = lp5812_manual_dc_pwm_control(chip, led_cfg->led_id[0],
					   led->brightness, LP5812_DIMMING_PWM);

	return ret;
}

static int lp5812_set_brightness(struct led_classdev *cdev,
				 enum led_brightness brightness)
{
	struct lp5812_led *led = container_of(cdev, struct lp5812_led, cdev);

	led->brightness = (u8)brightness;
	return lp5812_led_brightness(led);
}

static int lp5812_set_mc_brightness(struct led_classdev *cdev,
				    enum led_brightness brightness)
{
	struct led_classdev_mc *mc_dev = lcdev_to_mccdev(cdev);
	struct lp5812_led *led = container_of(mc_dev, struct lp5812_led, mc_cdev);

	led_mc_calc_color_components(&led->mc_cdev, brightness);
	return lp5812_multicolor_brightness(led);
}

static int lp5812_init_led(struct lp5812_led *led, struct lp5812_chip *chip, int chan)
{
	struct device *dev = &chip->client->dev;
	struct mc_subled *mc_led_info;
	struct led_classdev *led_cdev;
	int i, ret;

	if (chip->led_config[chan].name) {
		led->cdev.name = chip->led_config[chan].name;
	} else {
		led->cdev.name = devm_kasprintf(dev, GFP_KERNEL, "%s:channel%d",
						chip->label ? : chip->client->name, chan);
		if (!led->cdev.name)
			return -ENOMEM;
	}

	if (!chip->led_config[chan].is_sc_led) {
		mc_led_info = devm_kcalloc(dev,
					   chip->led_config[chan].num_colors,
					   sizeof(*mc_led_info), GFP_KERNEL);
		if (!mc_led_info)
			return -ENOMEM;

		led_cdev = &led->mc_cdev.led_cdev;
		led_cdev->name = led->cdev.name;
		led_cdev->brightness_set_blocking = lp5812_set_mc_brightness;
		led->mc_cdev.num_colors = chip->led_config[chan].num_colors;
		for (i = 0; i < led->mc_cdev.num_colors; i++) {
			mc_led_info[i].color_index =
					chip->led_config[chan].color_id[i];
			mc_led_info[i].channel =
					chip->led_config[chan].led_id[i];
		}

		led->mc_cdev.subled_info = mc_led_info;
	} else {
		led->cdev.brightness_set_blocking = lp5812_set_brightness;
	}

	led->chan_nr = chan;

	if (chip->led_config[chan].is_sc_led) {
		ret = devm_led_classdev_register(dev, &led->cdev);
		if (ret == 0)
			led->cdev.dev->platform_data = led;
	} else {
		ret = devm_led_classdev_multicolor_register(dev, &led->mc_cdev);
		if (ret == 0)
			led->mc_cdev.led_cdev.dev->platform_data = led;
	}

	return ret;
}

static int lp5812_register_leds(struct lp5812_led *led, struct lp5812_chip *chip)
{
	struct lp5812_led *each;
	int num_channels = chip->num_channels;
	u8 reg_val;
	u16 reg;
	int ret, i, j;

	for (i = 0; i < num_channels; i++) {
		each = led + i;
		ret = lp5812_init_led(each, chip, i);
		if (ret)
			goto err_init_led;

		each->chip = chip;

		for (j = 0; j < chip->led_config[i].num_colors; j++) {
			ret = lp5812_auto_dc(chip, chip->led_config[i].led_id[j],
					     chip->led_config[i].max_current[j]);
			if (ret)
				goto err_init_led;

			ret = lp5812_manual_dc_pwm_control(chip, chip->led_config[i].led_id[j],
							   chip->led_config[i].max_current[j],
							   LP5812_DIMMING_ANALOG);
			if (ret)
				goto err_init_led;

			ret = lp5812_set_led_mode(chip, chip->led_config[i].led_id[j],
						  LP5812_MODE_MANUAL);
			if (ret)
				goto err_init_led;

			reg = (chip->led_config[i].led_id[j] < LP5812_NUMBER_LED_IN_REG) ?
				chip->cfg->reg_led_en_1.addr :
				chip->cfg->reg_led_en_2.addr;

			ret = lp5812_read(chip, reg, &reg_val);
			if (ret)
				goto err_init_led;

			reg_val |= (1 << (chip->led_config[i].led_id[j] %
				LP5812_NUMBER_LED_IN_REG));

			ret = lp5812_write(chip, reg, reg_val);
			if (ret)
				goto err_init_led;
		}
	}

	return 0;

err_init_led:
	return ret;
}

static int lp5812_init_device(struct lp5812_chip *chip)
{
	int ret;

	usleep_range(LP5812_WAIT_DEVICE_STABLE_MIN, LP5812_WAIT_DEVICE_STABLE_MAX);

	ret = lp5812_write(chip, chip->cfg->reg_chip_en.addr, (u8)1);
	if (ret) {
		dev_err(&chip->client->dev, "lp5812_enable_disable failed\n");
		return ret;
	}

	ret = lp5812_write(chip, chip->cfg->reg_dev_config_12.addr, LP5812_LSD_LOD_START_UP);
	if (ret) {
		dev_err(&chip->client->dev, "write 0x0B to DEV_CONFIG12 failed\n");
		return ret;
	}

	ret = parse_drive_mode(chip, chip->scan_mode);
	if (ret)
		return ret;

	ret = lp5812_set_drive_mode_scan_order(chip);
	if (ret)
		return ret;

	ret = lp5812_update_regs_config(chip);
	if (ret) {
		dev_err(&chip->client->dev, "lp5812_update_regs_config failed\n");
		return ret;
	}

	return 0;
}

static void lp5812_deinit_device(struct lp5812_chip *chip)
{
	lp5812_write(chip, chip->cfg->reg_led_en_1.addr, 0);
	lp5812_write(chip, chip->cfg->reg_led_en_2.addr, 0);
	lp5812_write(chip, chip->cfg->reg_chip_en.addr, 0);
}

static int lp5812_parse_led_channel(struct device_node *np,
				    struct lp5812_led_config *cfg,
				    int color_number)
{
	int color_id = 0, reg, ret;
	u32 max_cur = 0;

	ret = of_property_read_u32(np, "reg", &reg);
	if (ret)
		return ret;

	cfg->led_id[color_number] = reg;

	of_property_read_u32(np, "led-max-microamp", &max_cur);
	cfg->max_current[color_number] = max_cur / 100;

	of_property_read_u32(np, "color", &color_id);
	cfg->color_id[color_number] = color_id;

	return 0;
}

static int lp5812_parse_led(struct device_node *np,
			    struct lp5812_led_config *cfg,
			    int led_index)
{
	int num_colors = 0, ret;

	of_property_read_string(np, "label", &cfg[led_index].name);

	ret = of_property_read_u32(np, "reg", &cfg[led_index].chan_nr);
	if (ret)
		return ret;

	for_each_available_child_of_node_scoped(np, child) {
		ret = lp5812_parse_led_channel(child, &cfg[led_index], num_colors);
		if (ret)
			return ret;
		num_colors++;
	}

	if (num_colors == 0) {
		ret = lp5812_parse_led_channel(np, &cfg[led_index], 0);
		if (ret)
			return ret;
		num_colors = 1;
		cfg[led_index].is_sc_led = true;
	} else {
		cfg[led_index].is_sc_led = false;
	}

	cfg[led_index].num_colors = num_colors;

	return 0;
}

static int lp5812_of_populate_pdata(struct device *dev,
				    struct device_node *np,
				    struct lp5812_chip *chip)
{
	struct lp5812_led_config *cfg;
	int num_channels, i = 0, ret;

	num_channels = of_get_available_child_count(np);
	if (num_channels == 0) {
		dev_err(dev, "no LED channels\n");
		return -EINVAL;
	}

	cfg = devm_kcalloc(dev, num_channels, sizeof(*cfg), GFP_KERNEL);
	if (!cfg)
		return -ENOMEM;

	chip->led_config = &cfg[0];
	chip->num_channels = num_channels;

	for_each_available_child_of_node_scoped(np, child) {
		ret = lp5812_parse_led(child, cfg, i);
		if (ret)
			return -EINVAL;
		i++;
	}

	ret = of_property_read_string(np, "ti,scan-mode", &chip->scan_mode);
	if (ret)
		chip->scan_mode = LP5812_MODE_DIRECT_NAME;

	of_property_read_string(np, "label", &chip->label);

	return 0;
}

static int lp5812_probe(struct i2c_client *client)
{
	struct lp5812_chip *chip;
	struct device_node *np = dev_of_node(&client->dev);
	struct lp5812_led *led;
	int ret;

	if (!np)
		return -EINVAL;

	chip = devm_kzalloc(&client->dev, sizeof(*chip), GFP_KERNEL);
	if (!chip)
		return -ENOMEM;

	chip->cfg = i2c_get_match_data(client);
	ret = lp5812_of_populate_pdata(&client->dev, np, chip);
	if (ret)
		return ret;

	led = devm_kcalloc(&client->dev, chip->num_channels, sizeof(*led), GFP_KERNEL);
	if (!led)
		return -ENOMEM;

	chip->client = client;
	mutex_init(&chip->lock);
	i2c_set_clientdata(client, led);

	ret = lp5812_init_device(chip);
	if (ret)
		return ret;

	ret = lp5812_register_leds(led, chip);
	if (ret)
		goto err_out;

	return 0;

err_out:
	lp5812_deinit_device(chip);
	return ret;
}

static void lp5812_remove(struct i2c_client *client)
{
	struct lp5812_led *led = i2c_get_clientdata(client);

	lp5812_deinit_device(led->chip);
}

/* Chip specific configurations */
static const struct lp5812_device_config lp5812_cfg = {
	.reg_reset = {
		.addr = LP5812_REG_RESET,
		.val  = LP5812_RESET
	},
	.reg_chip_en = {
		.addr = LP5812_REG_ENABLE,
		.val  = LP5812_ENABLE_DEFAULT
	},
	.reg_dev_config_0 = {
		.addr = LP5812_DEV_CONFIG0,
		.val  = 0
	},
	.reg_dev_config_1 = {
		.addr = LP5812_DEV_CONFIG1,
		.val  = 0
	},
	.reg_dev_config_2 = {
		.addr = LP5812_DEV_CONFIG2,
		.val  = 0
	},
	.reg_dev_config_3 = {
		.addr = LP5812_DEV_CONFIG3,
		.val  = 0
	},
	.reg_dev_config_4 = {
		.addr = LP5812_DEV_CONFIG4,
		.val  = 0
	},
	.reg_dev_config_5 = {
		.addr = LP5812_DEV_CONFIG5,
		.val  = 0
	},
	.reg_dev_config_6 = {
		.addr = LP5812_DEV_CONFIG6,
		.val  = 0
	},
	.reg_dev_config_7 = {
		.addr = LP5812_DEV_CONFIG7,
		.val  = 0
	},
	.reg_dev_config_12 = {
		.addr = LP5812_DEV_CONFIG12,
		.val  = LP5812_DEV_CONFIG12_DEFAULT
	},
	.reg_cmd_update = {
		.addr = LP5812_CMD_UPDATE,
		.val  = 0
	},
	.reg_tsd_config_status = {
		.addr = LP5812_TSD_CONFIG_STATUS,
		.val  = 0
	},
	.reg_led_en_1 = {
		.addr = LP5812_LED_EN_1,
		.val  = 0
	},
	.reg_led_en_2 = {
		.addr = LP5812_LED_EN_2,
		.val  = 0
	},
	.reg_fault_clear = {
		.addr = LP5812_FAULT_CLEAR,
		.val  = 0
	},
	.reg_manual_dc_base  = {
		.addr = LP5812_MANUAL_DC_BASE,
		.val  = 0
	},
	.reg_auto_dc_base  = {
		.addr = LP5812_AUTO_DC_BASE,
		.val  = 0
	},
	.reg_manual_pwm_base  = {
		.addr = LP5812_MANUAL_PWM_BASE,
		.val  = 0
	},
	.reg_lod_status_base  = {
		.addr = LP5812_LOD_STATUS,
		.val  = 0
	},
	.reg_lsd_status_base  = {
		.addr = LP5812_LSD_STATUS,
		.val  = 0
	}
};

static const struct of_device_id of_lp5812_match[] = {
	{ .compatible = "ti,lp5812", .data = &lp5812_cfg },
	{/* NULL */}
};

MODULE_DEVICE_TABLE(of, of_lp5812_match);

static struct i2c_driver lp5812_driver = {
	.driver = {
		.name   = "lp5812",
		.of_match_table = of_lp5812_match,
	},
	.probe		= lp5812_probe,
	.remove		= lp5812_remove,
};

module_i2c_driver(lp5812_driver);

MODULE_DESCRIPTION("Texas Instruments LP5812 LED Driver");
MODULE_AUTHOR("Jared Zhou");
MODULE_LICENSE("GPL");
