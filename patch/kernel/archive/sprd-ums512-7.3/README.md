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
The fork then moved to **v7.3** on branch `armbian-73`. The fixes below
come along unchanged.
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
here would buy nothing, so it sits in the fork on branch `armbian-73`, one
commit per fix, with the reasoning in each commit message:

- `936280b5a267` arm64: dts: sprd: rg-rotate: do not claim the last DRAM page
- `bd022b10f119` arm64: dts: sprd: rg-rotate: wire the goodix touchscreen IRQ
- `a09abeaaf916` wifi: sc23xx: finish the scan when the interface goes down
- `afac2fc5bf07` wifi: sc23xx: notify the firmware of the interface's IPv4 address
- `7bdadc4b271e` wifi: sc23xx: report the fallback MAC address as random
- `48fb2d5ced7a` ASoC: sprd: stop rejecting the 96 kHz DAC mode
- `5692f7396a68` ASoC: sprd: wait for audcp rather than dropping the write
- `351b152cfecd` ASoC: sprd: step the non-interleaved DMA by the sample width
- `62a5a32a676b` ASoC: sprd: resume the DMA channel instead of re-submitting
- `b58bba695549` ASoC: sprd: pcm-routing: mark the AIF widgets SND_SOC_NOPM
- `282d16f13d52` ASoC: sprd: give the VBC path a buffer a desktop can feed
- `bf9fc5835bf8` ASoC: sprd: stop the DSP when the fast scene stops
- `db21cdd983fb` sprdwcn: only toggle pub_int on an actual power transition
- `361441b30449` sprdwcn: do not latch the firmware-partition fallback on a missing blob
- `a069e1775e0f` sprdwcn: fail fast when the BTWF firmware is missing

Six more are what moving to 7.2 cost. The first two are the build - 7.2 removed
both of the things they used - and the rest are noise this port had been
printing at error level for events that are not errors:

- `c3de4eeebf74` drm/panel: generic-dsi: use the refcounted panel allocation
- `6f8fc1e3bd4c` sprdwcn: stop using strncpy()
- `303f05d242fa` sprdwcn: do not report the planned first firmware miss as an error
- `83ed4d179195` ASoC: sprd: do not report a deferred audio-regulator probe as a failure
- `5745cdfa55b5` ASoC: sprd: stop shouting when a board does not wire an IIS pin group
- `d858a18944d8` ASoC: sprd: send the hw params to the dsp for the normal AP scene too

Between them they take twenty-two error lines per boot down to none: eleven
regulators were deferring once each and shouting about it, and six IIS pin
groups this board does not wire were failing to restore a value they had
reported themselves.

The move to 7.3 added ten more. Five follow mainline API changes. The others
fix USB, charger boost and audio codec probe order:

- `e5b6608fd8ba` usb: typec: tcpm: sc27xx: do not latch vbus_on when the boost fails
- `7fb7ca4ed292` power: supply: bq2415x: tell the regulator core how slow the boost is
- `e10af23d78d8` usb: musb: sprd: ask the engine to clear an aborted channel
- `ab21269968d6` drm/panel: chipone-icnl9916: allocate the panel with devm_drm_panel_alloc()
- `4fcf5642ccf5` drm/panel: generic-dsi: follow the of_drm_get_panel_orientation() rename
- `fb0a0698ab09` wifi: sc23xx: take the mgmt_tx cookie by value
- `868cb6a4487d` media: sprd: follow the v4l2_isp_params_buffer_size() rename
- `b202b61bc2c1` drm/sprd: dsi: move the bridge to the atomic enable hooks
- `e614aed9a9ea` drm/sprd: dsi: give the bridge its atomic state hooks
- `736addef6211` ASoC: sprd: codec: wait for the audcp power domain before probing

One more commit on that branch is not a fix of this port's but a mainline commit
put back: `ASoC: sprd: sprd-mcdt: Use guard() for mutex & spin locks`. The fork
carries an audio port attempt and a later wholesale revert of it, and on the new
base that revert restores the file from before the port, which silently undid the
cleanup and left the driver on the old manual locking.

Three more changes were hypotheses the evidence did not support. They are kept for
the reasoning in their commit messages, on branch `rg-rotate-experiments` of the
same fork, and are not applied.
