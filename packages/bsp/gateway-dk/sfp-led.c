// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * SFP LED Control Platform Driver (Passive Monitor)
 *
 * Controls SFP port LEDs based on module presence and link state.
 * This driver passively monitors I2C and netdev state without interfering
 * with the SFP subsystem or MAC driver.
 *
 * Design principle:
 *   This driver does NOT interact with the kernel's SFP state machine.
 *   This avoids conflicts with MAC drivers that use fixed-link configuration
 *   (like NXP DPAA SDK).
 *
 * Detection method:
 *   - Module presence: Probe I2C EEPROM at 0x50
 *   - Link state: Check netdev operstate (for DAC) or I2C DDM (for fiber)
 *   - Activity: Poll netdev tx/rx packet counters
 *
 * LED behavior:
 *
 *   State                      | Green (Link) | Orange (Activity)
 *   ---------------------------|--------------|-------------------
 *   No module                  | OFF          | OFF
 *   Module present, no link    | OFF          | ON (solid)
 *   Module present, link up    | ON           | Blinks on traffic
 *
 * Module type detection:
 *   - Fiber SFP: Uses I2C DDM (A2h byte 110 LOS bit) for link detection
 *   - DAC cable: Uses netdev operstate (DAC has no DDM support)
 *   - Detection via A0h page bytes 3 and 8 copper compliance bits
 *
 * Device tree binding example:
 *
 *   sfp0: sfp-0 {
 *       compatible = "sff,sfp";
 *       i2c-bus = <&sfp0_i2c>;
 *       leds = <&led_sfp0_link>, <&led_sfp0_activity>;
 *   };
 *
 *   sfp-led-controller {
 *       compatible = "mono,sfp-led";
 *       sfp-ports = <&sfp0>, <&sfp1>;
 *   };
 *
 *   // MAC node must reference SFP for netdev association
 *   &fman_mac {
 *       sfp = <&sfp0>;
 *   };
 *
 * Copyright 2026 Mono Technologies Inc.
 * Author: Tomaz Zaman <tomaz@mono.si>
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/errno.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <linux/leds.h>
#include <linux/workqueue.h>
#include <linux/netdevice.h>
#include <linux/rtnetlink.h>
#include <linux/i2c.h>
#include <linux/if.h>

#define DRIVER_NAME "sfp-led"
#define SFP_LED_NAME_SIZE 64

/* Polling interval in milliseconds */
#define SFP_LED_POLL_INTERVAL_MS	100
#define SFP_LED_NETDEV_RETRY_MS		1000
#define SFP_LED_MAX_NETDEV_RETRIES	30

/* SFP I2C addresses per SFP MSA */
#define SFP_EEPROM_ADDR		0x50	/* A0h page - module ID/capabilities */
#define SFP_DIAG_ADDR		0x51	/* A2h page - diagnostics/status */

/* SFP A2h page registers */
#define SFP_STATUS_CTRL_REG	110	/* Status/Control register */
#define SFP_STATUS_LOS		BIT(1)	/* RX Loss of Signal */
#define SFP_STATUS_TX_FAULT	BIT(2)	/* TX Fault */

/* SFP A0h page - cable type detection (per SFP MSA) */
#define SFP_PHYS_EXT_ID		1	/* Extended identifier */
#define SFP_COMPLIANCE_3	3	/* 10G/1G Ethernet compliance */
#define SFP_COMPLIANCE_8	8	/* SFP+ cable technology */
#define SFP_8472_COMPLIANCE	94	/* SFF-8472 compliance (DDM support) */

/* Byte 3 bits - 1G Ethernet copper compliance */
#define SFP_IF_1X_COPPER_PASSIVE	BIT(0)
#define SFP_IF_1X_COPPER_ACTIVE		BIT(1)

/* Byte 8 bits - SFP+ cable technology */
#define SFP_CT_PASSIVE		BIT(2)	/* Passive cable */
#define SFP_CT_ACTIVE		BIT(3)	/* Active cable */

struct sfp_led_port {
	struct sfp_led_priv *priv;
	struct device_node *sfp_np;
	struct i2c_adapter *i2c_adapter;	/* I2C bus for module detection */
	struct net_device *netdev;
	char netdev_name[IFNAMSIZ];

	struct led_classdev *link_led;
	struct led_classdev *activity_led;

	char link_led_name[SFP_LED_NAME_SIZE];
	char activity_led_name[SFP_LED_NAME_SIZE];

	struct delayed_work poll_work;
	int netdev_retries;

	/* Cached state for change detection */
	bool last_module_present;
	bool last_carrier;
	bool is_dac;			/* True if DAC cable (no DDM support) */
	u64 last_tx_packets;
	u64 last_rx_packets;
	bool activity_led_on;
};

struct sfp_led_priv {
	struct device *dev;
	int num_ports;
	struct sfp_led_port *ports;
};

/*
 * Find the netdev associated with an SFP by traversing device tree.
 *
 * DPAA device tree structure:
 *   fsldpaa/ethernet@8 (fsl,dpa-ethernet) -> fsl,fman-mac = <&enet6>
 *   fman0/ethernet@f0000 (enet6)          -> sfp = <&sfp_xfi0>
 */
static struct net_device *sfp_led_find_netdev(struct device_node *sfp_np)
{
	struct net_device *dev, *found = NULL;
	bool need_rtnl;

	if (!sfp_np)
		return NULL;

	need_rtnl = !rtnl_is_locked();
	if (need_rtnl)
		rtnl_lock();

	for_each_netdev(&init_net, dev) {
		struct device *parent = dev->dev.parent;
		struct device_node *dpaa_node, *mac_node, *sfp_ref;

		if (!parent || !parent->of_node)
			continue;

		dpaa_node = parent->of_node;

		mac_node = of_parse_phandle(dpaa_node, "fsl,fman-mac", 0);
		if (!mac_node)
			continue;

		sfp_ref = of_parse_phandle(mac_node, "sfp", 0);
		of_node_put(mac_node);

		if (sfp_ref == sfp_np) {
			of_node_put(sfp_ref);
			found = dev;
			dev_hold(found);
			break;
		}
		of_node_put(sfp_ref);
	}

	if (need_rtnl)
		rtnl_unlock();

	return found;
}

/*
 * Detect SFP module presence by probing I2C EEPROM at address 0x50.
 * All SFP/SFP+ modules have an EEPROM that responds to this address.
 * Returns true if module is present, false otherwise.
 */
static bool sfp_led_i2c_module_present(struct sfp_led_port *port)
{
	union i2c_smbus_data data;
	int ret;

	if (!port->i2c_adapter)
		return false;

	/*
	 * Try to read byte 0 from SFP EEPROM (identifier byte).
	 * If the read succeeds, a module is present.
	 */
	ret = i2c_smbus_xfer(port->i2c_adapter, SFP_EEPROM_ADDR,
			     0, I2C_SMBUS_READ, 0,
			     I2C_SMBUS_BYTE_DATA, &data);

	return ret >= 0;
}

static bool sfp_led_module_present(struct sfp_led_port *port)
{
	return sfp_led_i2c_module_present(port);
}

/*
 * Detect if the SFP module is a DAC (Direct Attach Copper) cable.
 * DAC cables don't have optical transceivers and don't support DDM.
 * Detection via A0h page compliance bytes per SFP MSA:
 *   - Byte 3 bits 0-1: 1G copper passive/active
 *   - Byte 8 bits 2-3: SFP+ cable technology passive/active
 * Returns true if DAC cable, false if fiber/optical module.
 */
static bool sfp_led_is_dac_cable(struct sfp_led_port *port)
{
	union i2c_smbus_data data;
	int ret;
	u8 byte3, byte8;
	bool is_dac;

	if (!port->i2c_adapter)
		return false;  /* Can't detect, assume fiber */

	/* Read byte 3 - 10G/1G Ethernet compliance */
	ret = i2c_smbus_xfer(port->i2c_adapter, SFP_EEPROM_ADDR,
			     0, I2C_SMBUS_READ, SFP_COMPLIANCE_3,
			     I2C_SMBUS_BYTE_DATA, &data);
	if (ret < 0) {
		dev_warn(port->priv->dev, "%s: failed to read A0h byte 3: %d\n",
			 port->link_led_name, ret);
		return false;
	}
	byte3 = data.byte;

	/* Read byte 8 - SFP+ cable technology */
	ret = i2c_smbus_xfer(port->i2c_adapter, SFP_EEPROM_ADDR,
			     0, I2C_SMBUS_READ, SFP_COMPLIANCE_8,
			     I2C_SMBUS_BYTE_DATA, &data);
	if (ret < 0) {
		dev_warn(port->priv->dev, "%s: failed to read A0h byte 8: %d\n",
			 port->link_led_name, ret);
		return false;
	}
	byte8 = data.byte;

	/* Check copper compliance bits */
	is_dac = (byte3 & (SFP_IF_1X_COPPER_PASSIVE | SFP_IF_1X_COPPER_ACTIVE)) ||
		 (byte8 & (SFP_CT_PASSIVE | SFP_CT_ACTIVE));

	dev_dbg(port->priv->dev, "%s: A0h byte3=0x%02x byte8=0x%02x -> %s\n",
		 port->link_led_name, byte3, byte8,
		 is_dac ? "DAC cable" : "fiber/optical");

	return is_dac;
}

/*
 * Read LOS (Loss of Signal) status from SFP module via I2C.
 * SFP MSA defines status register at A2h (0x51), byte 110.
 * Returns true if signal is lost, false if signal is present.
 */
static bool sfp_led_i2c_los(struct sfp_led_port *port)
{
	union i2c_smbus_data data;
	int ret;
	static int debug_count[2] = {0, 0};  /* Rate limit debug output */
	int port_idx = (port == &port->priv->ports[0]) ? 0 : 1;

	if (!port->i2c_adapter)
		return true;  /* Assume no signal if can't check */

	ret = i2c_smbus_xfer(port->i2c_adapter, SFP_DIAG_ADDR,
			     0, I2C_SMBUS_READ, SFP_STATUS_CTRL_REG,
			     I2C_SMBUS_BYTE_DATA, &data);

	/* Debug: log every 50th read or on error */
	if (ret < 0) {
		if (debug_count[port_idx]++ % 50 == 0)
			dev_dbg(port->priv->dev, "%s: A2h read failed: %d (no DDM?)\n",
				 port->link_led_name, ret);
		return true;  /* Error reading - assume no signal */
	}

	/* Debug: log status byte periodically */
	if (debug_count[port_idx]++ % 50 == 0)
		dev_dbg(port->priv->dev, "%s: A2h[110]=0x%02x LOS=%d\n",
			 port->link_led_name, data.byte,
			 (data.byte & SFP_STATUS_LOS) ? 1 : 0);

	return (data.byte & SFP_STATUS_LOS) != 0;
}

/*
 * Check if interface has operational link.
 * For DAC cables with DPAA fixed-link, get_link() is unreliable.
 * Use operstate which accurately reflects actual link status.
 */
static bool sfp_led_has_operational_link(struct net_device *netdev)
{
	/*
	 * operstate reflects actual link status:
	 * - IF_OPER_UP: interface is up and link is established
	 * - IF_OPER_DOWN: interface is down or no link
	 * This is what ethtool uses for "Link detected" field.
	 */
	return netdev->operstate == IF_OPER_UP;
}

/*
 * Check if we have signal/link.
 * For fiber modules: I2C DDM status register (A2h byte 110 LOS bit)
 * For DAC cables: operstate (DAC has no DDM support)
 * Returns true if link/signal is present.
 */
static bool sfp_led_has_signal(struct sfp_led_port *port)
{
	/*
	 * DAC cables don't have optical transceivers and don't support DDM.
	 * The A2h page reads return 0xff which looks like LOS=1.
	 * For DAC, check operstate which accurately reflects link status,
	 * unlike get_link()/carrier which may be stale with fixed-link config.
	 */
	if (port->is_dac) {
		if (port->netdev)
			return sfp_led_has_operational_link(port->netdev);
		return false;
	}

	/* Fiber: Use I2C DDM status register (most fiber SFPs support DDM) */
	if (port->i2c_adapter)
		return !sfp_led_i2c_los(port);

	/* Last resort: check operstate */
	if (port->netdev)
		return sfp_led_has_operational_link(port->netdev);

	return false;
}

static void sfp_led_set_link(struct sfp_led_port *port, bool on)
{
	if (!port->link_led)
		return;

	led_set_brightness(port->link_led,
			   on ? port->link_led->max_brightness : LED_OFF);
}

static void sfp_led_set_activity(struct sfp_led_port *port, bool on)
{
	if (!port->activity_led)
		return;

	/* Don't override if user has configured a trigger */
	if (port->activity_led->trigger)
		return;

	led_set_brightness(port->activity_led,
			   on ? port->activity_led->max_brightness : LED_OFF);
}

static void sfp_led_poll_work_handler(struct work_struct *work)
{
	struct sfp_led_port *port = container_of(work, struct sfp_led_port,
						 poll_work.work);
	struct net_device *netdev;
	bool module_present, carrier;
	struct rtnl_link_stats64 stats;
	bool had_activity;

	/* Check module presence via I2C */
	module_present = sfp_led_module_present(port);

	/* Handle module state changes */
	if (module_present != port->last_module_present) {
		port->last_module_present = module_present;

		if (!module_present) {
			/* Module removed - turn off both LEDs and reset state */
			sfp_led_set_link(port, false);
			sfp_led_set_activity(port, false);
			port->last_carrier = false;
			port->is_dac = false;
			dev_dbg(port->priv->dev, "%s: module removed\n",
				port->link_led_name);
		} else {
			/* Module inserted - detect cable type */
			port->is_dac = sfp_led_is_dac_cable(port);
			/* Set initial state: module present, no link yet */
			sfp_led_set_link(port, false);
			sfp_led_set_activity(port, true);
			dev_dbg(port->priv->dev, "%s: module inserted (%s)\n",
				port->link_led_name,
				port->is_dac ? "DAC" : "fiber");
		}
	}

	if (!module_present)
		goto reschedule;

	/* Try to find netdev if we don't have one yet */
	netdev = READ_ONCE(port->netdev);
	if (!netdev) {
		netdev = sfp_led_find_netdev(port->sfp_np);
		if (netdev) {
			if (cmpxchg(&port->netdev, NULL, netdev) != NULL) {
				dev_put(netdev);
			} else {
				strscpy(port->netdev_name, netdev->name,
					sizeof(port->netdev_name));
				dev_dbg(port->priv->dev, "%s: found netdev %s\n",
					port->link_led_name, netdev->name);
			}
		} else {
			port->netdev_retries++;
			if (port->netdev_retries < SFP_LED_MAX_NETDEV_RETRIES) {
				/* Keep activity LED on to show module present */
				sfp_led_set_activity(port, true);
			}
		}
		netdev = READ_ONCE(port->netdev);
	}

	if (!netdev) {
		/* No netdev yet - show module present only */
		sfp_led_set_link(port, false);
		sfp_led_set_activity(port, true);
		goto reschedule;
	}

	/* Check signal/carrier state */
	carrier = sfp_led_has_signal(port);

	if (carrier != port->last_carrier) {
		port->last_carrier = carrier;
		sfp_led_set_link(port, carrier);

		if (carrier) {
			dev_dbg(port->priv->dev, "%s: link up\n",
				port->link_led_name);
			/* Turn off activity LED and reset counters on link up */
			sfp_led_set_activity(port, false);
			port->last_tx_packets = 0;
			port->last_rx_packets = 0;
			port->activity_led_on = false;
		} else {
			dev_dbg(port->priv->dev, "%s: link down\n",
				port->link_led_name);
			/* Module present but no link - solid activity LED */
			sfp_led_set_activity(port, true);
		}
	}

	if (!carrier)
		goto reschedule;

	/* Monitor activity when link is up */
	if (!netif_running(netdev))
		goto reschedule;

	dev_get_stats(netdev, &stats);

	had_activity = (stats.tx_packets != port->last_tx_packets ||
			stats.rx_packets != port->last_rx_packets);

	if (had_activity) {
		/* Toggle LED for visible blink */
		port->activity_led_on = !port->activity_led_on;
		sfp_led_set_activity(port, port->activity_led_on);
		port->last_tx_packets = stats.tx_packets;
		port->last_rx_packets = stats.rx_packets;
	} else if (port->activity_led_on) {
		/* No activity - turn off */
		port->activity_led_on = false;
		sfp_led_set_activity(port, false);
	}

reschedule:
	schedule_delayed_work(&port->poll_work,
			      msecs_to_jiffies(SFP_LED_POLL_INTERVAL_MS));
}

static int sfp_led_register_port(struct sfp_led_priv *priv,
				 struct device_node *sfp_np, int index)
{
	struct sfp_led_port *port = &priv->ports[index];
	struct device_node *i2c_np;

	port->priv = priv;
	port->sfp_np = sfp_np;
	of_node_get(sfp_np);

	/* Get I2C adapter for module detection */
	i2c_np = of_parse_phandle(sfp_np, "i2c-bus", 0);
	if (i2c_np) {
		port->i2c_adapter = of_get_i2c_adapter_by_node(i2c_np);
		of_node_put(i2c_np);
	}

	if (IS_ERR_OR_NULL(port->i2c_adapter)) {
		int ret = PTR_ERR_OR_ZERO(port->i2c_adapter);

		port->i2c_adapter = NULL;
		if (ret != -EPROBE_DEFER)
			dev_err(priv->dev, "port %d: i2c-bus not available\n", index);
		of_node_put(sfp_np);
		port->sfp_np = NULL;
		return ret ? ret : -ENODEV;
	}

	/* Get LEDs */
	port->link_led = of_led_get(sfp_np, 0);
	if (IS_ERR(port->link_led)) {
		dev_dbg(priv->dev, "port %d: link LED not in DT: %ld\n",
			index, PTR_ERR(port->link_led));
		port->link_led = NULL;
	}

	port->activity_led = of_led_get(sfp_np, 1);
	if (IS_ERR(port->activity_led)) {
		dev_dbg(priv->dev, "port %d: activity LED not in DT: %ld\n",
			index, PTR_ERR(port->activity_led));
		port->activity_led = NULL;
	}

	/* Set LED names for logging */
	if (port->link_led && port->link_led->name)
		strscpy(port->link_led_name, port->link_led->name,
			sizeof(port->link_led_name));
	else
		snprintf(port->link_led_name, sizeof(port->link_led_name),
			 "sfp%d:link", index);

	if (port->activity_led && port->activity_led->name)
		strscpy(port->activity_led_name, port->activity_led->name,
			sizeof(port->activity_led_name));
	else
		snprintf(port->activity_led_name, sizeof(port->activity_led_name),
			 "sfp%d:activity", index);

	/* Initialize work */
	INIT_DELAYED_WORK(&port->poll_work, sfp_led_poll_work_handler);

	/* Start polling */
	schedule_delayed_work(&port->poll_work, 0);

	dev_dbg(priv->dev, "registered port %d: %pOFn (link=%s, activity=%s)\n",
		index, sfp_np, port->link_led_name, port->activity_led_name);

	return 0;
}

static void sfp_led_cleanup_port(struct sfp_led_port *port)
{
	if (!port->sfp_np)
		return;

	cancel_delayed_work_sync(&port->poll_work);

	sfp_led_set_link(port, false);
	sfp_led_set_activity(port, false);

	if (port->activity_led) {
		led_put(port->activity_led);
		port->activity_led = NULL;
	}

	if (port->link_led) {
		led_put(port->link_led);
		port->link_led = NULL;
	}

	if (port->netdev) {
		dev_put(port->netdev);
		port->netdev = NULL;
	}

	if (port->i2c_adapter) {
		i2c_put_adapter(port->i2c_adapter);
		port->i2c_adapter = NULL;
	}

	of_node_put(port->sfp_np);
	port->sfp_np = NULL;
}

static int sfp_led_probe(struct platform_device *pdev)
{
	struct sfp_led_priv *priv;
	struct device_node *np;
	int count, i, registered = 0;

	priv = devm_kzalloc(&pdev->dev, sizeof(*priv), GFP_KERNEL);
	if (!priv)
		return -ENOMEM;

	priv->dev = &pdev->dev;
	platform_set_drvdata(pdev, priv);

	count = of_count_phandle_with_args(pdev->dev.of_node, "sfp-ports", NULL);
	if (count <= 0) {
		dev_err(&pdev->dev, "no sfp-ports specified\n");
		return -ENODEV;
	}

	priv->ports = devm_kcalloc(&pdev->dev, count,
				   sizeof(*priv->ports), GFP_KERNEL);
	if (!priv->ports)
		return -ENOMEM;

	priv->num_ports = count;

	for (i = 0; i < count; i++) {
		np = of_parse_phandle(pdev->dev.of_node, "sfp-ports", i);
		if (!np) {
			dev_warn(&pdev->dev, "failed to parse sfp-ports[%d]\n", i);
			continue;
		}

		if (sfp_led_register_port(priv, np, i) == 0)
			registered++;

		of_node_put(np);
	}

	if (registered == 0) {
		dev_err(&pdev->dev, "no SFP ports registered\n");
		return -ENODEV;
	}

	dev_dbg(&pdev->dev, "loaded (passive monitor, %d ports)\n", registered);
	return 0;
}

static void sfp_led_remove(struct platform_device *pdev)
{
	struct sfp_led_priv *priv = platform_get_drvdata(pdev);
	int i;

	for (i = 0; i < priv->num_ports; i++)
		sfp_led_cleanup_port(&priv->ports[i]);

	dev_dbg(&pdev->dev, "unloaded\n");
}

static const struct of_device_id sfp_led_of_match[] = {
	{ .compatible = "mono,sfp-led" },
	{ }
};
MODULE_DEVICE_TABLE(of, sfp_led_of_match);

static struct platform_driver sfp_led_driver = {
	.probe = sfp_led_probe,
	.remove = sfp_led_remove,
	.driver = {
		.name = DRIVER_NAME,
		.of_match_table = sfp_led_of_match,
	},
};
module_platform_driver(sfp_led_driver);

MODULE_AUTHOR("Tomaz Zaman <tomaz@mono.si>");
MODULE_DESCRIPTION("SFP LED Control Platform Driver (Passive Monitor)");
MODULE_LICENSE("GPL");
