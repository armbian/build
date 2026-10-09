# sprd-ums512 kernel patches

The kernel for this family is a fork of `beebono/linux-mainline-sprd` (branch
`rg-rotate`), which already carries the bulk of the UMS512/T618 support - DRM/DSI
panel, SC2355 Wi-Fi and Bluetooth, the DSP-mediated audio stack, the panfrost
match for Mali-G52, the sharkl5pro cpufreq driver and the AP-APB address fixes.
That branch sits on 7.1-rc1 and its author stopped updating it in August 2026, so
it has been forward ported here onto **v7.2.9**: 226 of its 227 commits replayed
untouched, and the one that did not was dropped because mainline had merged it
(`mfd: sprd-sc27xx: Switch to devm_mfd_add_devices()`, in a better form - it
starts the PMIC type enum at 1 so a missing match can still be told apart).
`KERNELBRANCH` pins an exact commit, so the tree is reproducible.

Six commits needed a hand. All six were the same shape: mainline had changed the
surrounding style, not the behaviour - scope-based `guard()` locking, named
initializers for `i2c_device_id` tables, `mod_devicetable.h` split into
`device-id/*.h`. One deserves naming, because taking either side alone would have
been wrong: mainline added a `bus_ace` optional clock to panfrost for Renesas
RZ/G2L in the same place this fork adds Unisoc's `GPU_MEM_CLK`. The binding
restricts `bus_ace` to the RZ/G2L compatible, so they are different clocks and
both are kept.

Only two patches live here, both because they touch mainline files and so have
somewhere upstream to go:

- `general-musb-gadget-*` - `drivers/usb/musb/musb_gadget.c`.
- `general-sprd-ums512-thermal-*` - the passive trip in
  `arch/arm64/boot/dts/sprd/ums512.dtsi`.

Everything else edits code that exists only in that fork - the board's own DTS,
and the Android-BSP vendor code under `sound/soc/sprd/vendor/`,
`drivers/net/wireless/unisoc/` and `drivers/net/wireless/sprdwcn/`. Carrying it
here would buy nothing, so it sits in the fork on branch `armbian-729`, one
commit per fix, with the reasoning in each commit message:

- `a44c9e3b140c` arm64: dts: sprd: rg-rotate: do not claim the last DRAM page
- `eeb83f0d0387` arm64: dts: sprd: rg-rotate: wire the goodix touchscreen IRQ
- `67de9831b8b1` wifi: sc23xx: finish the scan when the interface goes down
- `bd9e99bb50a0` wifi: sc23xx: notify the firmware of the interface's IPv4 address
- `3a798fa54fcd` wifi: sc23xx: report the fallback MAC address as random
- `24fc73ed714d` ASoC: sprd: stop rejecting the 96 kHz DAC mode
- `9e49da7e8c1d` ASoC: sprd: wait for audcp rather than dropping the write
- `936277492ed9` ASoC: sprd: step the non-interleaved DMA by the sample width
- `ee4431f6f3fd` ASoC: sprd: resume the DMA channel instead of re-submitting
- `7dcaa56d0678` ASoC: sprd: pcm-routing: mark the AIF widgets SND_SOC_NOPM
- `e577585ca7e0` ASoC: sprd: give the VBC path a buffer a desktop can feed
- `991b52f1cfc8` ASoC: sprd: stop the DSP when the fast scene stops
- `cfc596a2a2a4` sprdwcn: only toggle pub_int on an actual power transition
- `e9e34257b200` sprdwcn: do not latch the firmware-partition fallback on a missing blob
- `c18a3b5580ed` sprdwcn: fail fast when the BTWF firmware is missing

Six more are what moving to 7.2 cost. The first two are the build - 7.2 removed
both of the things they used - and the rest are noise this port had been
printing at error level for events that are not errors:

- `226ba1247b1a` drm/panel: generic-dsi: use the refcounted panel allocation
- `31f5629e0e40` sprdwcn: stop using strncpy()
- `ba9933bf25db` sprdwcn: do not report the planned first firmware miss as an error
- `706825e42f39` ASoC: sprd: do not report a deferred audio-regulator probe as a failure
- `433481a1deb4` ASoC: sprd: stop shouting when a board does not wire an IIS pin group
- `d0aba8189b5a` ASoC: sprd: send the hw params to the dsp for the normal AP scene too

Between them they take twenty-two error lines per boot down to none: eleven
regulators were deferring once each and shouting about it, and six IIS pin
groups this board does not wire were failing to restore a value they had
reported themselves.

One more commit on that branch is not a fix of this port's but a mainline commit
put back: `ASoC: sprd: sprd-mcdt: Use guard() for mutex & spin locks`. The fork
carries an audio port attempt and a later wholesale revert of it, and on the new
base that revert restores the file from before the port, which silently undid the
cleanup and left the driver on the old manual locking.

Three more changes were hypotheses the evidence did not support. They are kept for
the reasoning in their commit messages, on branch `rg-rotate-experiments` of the
same fork, and are not applied.
