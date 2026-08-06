# `v2026.07-sunxi64` — 64-bit sunxi u-boot patch dir (migration target)

The 64-bit sunxi family (`sunxi64_common.inc`, sun50i: A64/H5/H6/H616/…) moved from
u-boot **v2024.01** to **v2026.07-rc4** so it builds on Debian trixie hosts (old
u-boot's pre-generated `scripts/dtc/pylibfdt/libfdt_wrap.c` doesn't compile against
trixie's SWIG 4.3) — the same break the 32-bit family hit.

Like the 32-bit `v2026.07-sunxi` dir, this starts from a **clean upstream baseline**
and re-adds only the patches still needed, board by board, as CI / on-target boot
tests confirm them. The v2024.01-era `u-boot-sunxi` set won't forward-apply and much
is upstreamed; the legacy dir is kept for reference.

Boards that already self-pin a newer `BOOTBRANCH_BOARD`/`BOOTPATCHDIR` (e.g.
`v2025-sunxi`, `v2025.04`, `v2026.01`) are unaffected by the family default and keep
their pins.
