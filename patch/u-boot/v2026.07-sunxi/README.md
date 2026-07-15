# `v2026.07-sunxi` — 32-bit sunxi u-boot patch dir (migration target)

The sunxi family (`sunxi_common.inc`) moved from u-boot **v2024.01** to
**v2026.07-rc4** so it builds on Debian trixie hosts (old u-boot's pre-generated
`scripts/dtc/pylibfdt/libfdt_wrap.c` doesn't compile against trixie's SWIG 4.3).

This dir intentionally starts **empty** (clean upstream baseline). The old
`patch/u-boot/v2024.01`-era `u-boot-sunxi` set (16 general + ~30 `board_*` patches)
does **not** forward-apply across two years of u-boot, and much of it has been
upstreamed. Rather than carry broken patches, we rebase from a clean base and
**re-add only what's still needed**, board by board, as CI / on-target boot tests
surface real failures:

- a board that fails to **build** (missing defconfig) needs its `board_<board>/`
  defconfig/DT patch ported here;
- a board that builds but won't **boot** needs its functional fix ported here.

The legacy `patch/u-boot/u-boot-sunxi/` is kept in-tree for reference and for any
board that pins an older `BOOTBRANCH_BOARD`.
