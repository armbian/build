# sprd-ums512 kernel patches

The kernel for this family is a fork of `beebono/linux-mainline-sprd` (branch
`rg-rotate`), which already carries the bulk of the UMS512/T618 support - DRM/DSI
panel, SC2355 Wi-Fi and Bluetooth, the DSP-mediated audio stack, the panfrost
match for Mali-G52, the sharkl5pro cpufreq driver and the AP-APB address fixes.
`KERNELBRANCH` pins an exact commit, so the tree is reproducible.

Only two patches live here, both because they touch mainline files and so have
somewhere upstream to go:

- `general-musb-gadget-*` - `drivers/usb/musb/musb_gadget.c`.
- `general-sprd-ums512-thermal-*` - the passive trip in
  `arch/arm64/boot/dts/sprd/ums512.dtsi`.

Everything else edits code that exists only in that fork - the board's own DTS,
and the Android-BSP vendor code under `sound/soc/sprd/vendor/`,
`drivers/net/wireless/unisoc/` and `drivers/net/wireless/sprdwcn/`. Carrying it
here would buy nothing, so it sits in the fork on branch `armbian-rg-rotate`, one
commit per fix, with the reasoning in each commit message:

- `79257d989c55` arm64: dts: sprd: rg-rotate: do not claim the last DRAM page
- `4eb5367c189a` arm64: dts: sprd: rg-rotate: wire the goodix touchscreen IRQ
- `4afcad751e7e` wifi: sc23xx: finish the scan when the interface goes down
- `9f34fa7129f1` wifi: sc23xx: notify the firmware of the interface's IPv4 address
- `c071df7e4f68` wifi: sc23xx: report the fallback MAC address as random
- `f81b338fc05d` ASoC: sprd: stop rejecting the 96 kHz DAC mode
- `37c1068a2f68` ASoC: sprd: wait for audcp rather than dropping the write
- `a9509b732cb0` ASoC: sprd: step the non-interleaved DMA by the sample width
- `232246eddafb` ASoC: sprd: resume the DMA channel instead of re-submitting
- `c18802181936` ASoC: sprd: pcm-routing: mark the AIF widgets SND_SOC_NOPM
- `c30bb42b004c` ASoC: sprd: give the VBC path a buffer a desktop can feed
- `4d0432acfa89` ASoC: sprd: stop the DSP when the fast scene stops
- `d8046504dca0` sprdwcn: only toggle pub_int on an actual power transition
- `a9328790d7af` sprdwcn: do not latch the firmware-partition fallback on a missing blob
- `9c607a698f9f` sprdwcn: fail fast when the BTWF firmware is missing

Three more changes were hypotheses the evidence did not support. They are kept for
the reasoning in their commit messages, on branch `rg-rotate-experiments` of the
same fork, and are not applied.
