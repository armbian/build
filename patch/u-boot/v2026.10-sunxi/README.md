# `v2026.10-sunxi` — 32-bit sunxi u-boot patch dir (v2026.10)

Shared patches 0001-0009 add Crust (SCP firmware) support for H3.
They come from Samuel Holland's `patch/h3-scp` branch
(https://github.com/smaeul/u-boot), rebased to v2026.10.

The code is off by default. A board enables it with
`CONFIG_SUNXI_SCPI_PSCI=y` in its defconfig and sets `CRUSTCONFIG`.
Then U-Boot starts Crust on the AR100, and PSCI calls go to Crust over SCPI.
Other boards keep the native PSCI code.

The kernel must keep the msgbox clock on: enable `CONFIG_SUN6I_MSGBOX`.
