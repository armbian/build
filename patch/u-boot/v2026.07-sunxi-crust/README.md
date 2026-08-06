# `v2026.07-sunxi-crust` — crust/SCP u-boot patch dir (v2026.07+)

Intentionally empty. Mainline u-boot (v2026.07-rc4) has **native SCP support**:
`arch/arm/dts/sunxi-u-boot.dtsi` already carries the `scp { filename = "scp.bin" }`
binman node and FIT `loadables`, gated by `CONFIG_SUNXI_SCP_BASE` — which is
auto-set per SoC (`0x00050000` for SUN50I/H5, `0x00114000` for H6). The crust
`scp.bin` is still built (`CRUST_TARGET_MAP`) and assembled by binman
(`BINMAN_ALLOW_MISSING=1`).

So the legacy `u-boot-sunxi-crust` patchset (`h3-scp.patch` etc., which manually
wired SCPI/PSCI into u-boot v2024.01) is obsolete here — 5/9 of its hunks no longer
apply, and they're not needed. crust boots via the upstream path now. Add
crust-specific u-boot tweaks here only if a real need surfaces.
