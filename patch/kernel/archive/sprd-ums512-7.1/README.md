# sprd-ums512 kernel patches

The kernel for this family is a fork
(`beebono/linux-mainline-sprd`, branch `rg-rotate`) that already carries the
bulk of the UMS512/T618 support - DRM/DSI panel, SC2355 Wi-Fi and Bluetooth,
the DSP-mediated audio stack, the panfrost match for Mali-G52, the sharkl5pro
cpufreq driver and the AP-APB address fixes.

What is here on top of it falls into three groups:

- `board-anbernic-rg-rotate-*` - DT fixes for this board on top of the fork's
  `ums512-rg-rotate.dts`: stop claiming the last DRAM page (stock stops one
  page short and that page is not spare - handing it to the page allocator
  produces intermittent page-sized data corruption), and give the Goodix
  touchscreen its interrupt so the driver stops falling back to I2C polling.
- `general-sprd-*` - fixes to the vendor ASoC and DMA code that the fork
  inherited unchanged from the Android BSP.
- `general-sprdwcn-*`, `general-sc23xx-*` - Wi-Fi/BT firmware-load,
  scan-teardown and firmware-notification fixes (the firmware is told the
  station's IPv4 address, as the vendor driver does; without it no broadcast
  reaches the host and the board is unreachable from the LAN once peers' ARP
  entries expire).

`.disabled` files are hypotheses the evidence did not support. They are kept
for the reasoning in their commit message, not to be applied.
