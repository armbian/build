# S5P6818 mainline u-boot v2026.07 port — INCOMPLETE / WORK IN PROGRESS

This directory contains an arm64 S5P6818 target for mainline u-boot v2026.07
(NanoPi-M3 / NanoPC-T3+). It is **not yet usable as the board's bootloader.**

## Status
- **Warm reboot:** boots fine.
- **Cold boot (power-on):** reset-loops. The crash is in early C
  (`board_init_f` / `arch_cpu_init`), before the console, and cascades through
  the nexell `clk_init` / `cpu_soc_init`. The nexell code (`mach-nexell`) is
  equivalent to the 2016.01 fork's, which boots cold — so the fault is a
  subtle **2026-u-boot framework + GCC-15 early-environment** difference
  (uninitialised cold-boot memory / relocation / early-heap ordering), not the
  SoC support. Blind serial-poke bisection was exhausted; cracking it needs
  JTAG (read the fault PC/EC), a from-SPL build, or framework work.

## What actually boots the board
The **2016.01 rafaello7 fork u-boot** (boots cold + warm at EL2) is the
known-good bootloader and is what the NanoPC-T3+ boots with today. A shippable
Armbian image for this board should use the fork until this port's cold-boot
crash is resolved.

## If you pick this up
- SP=CONFIG_TEXT_BASE=0x43c00000 (same as the fork); non-SPL; caches on;
  cacheline 64 — all equivalent to the fork.
- Try: move `CUSTOM_SYS_INIT_SP_ADDR` well above the image; diff
  `crt0_64`/`board_init_f_alloc_reserve` fork-vs-mainline; or build from SPL.
- The NSIH header + BL1 are prepended by the family hook
  (`uboot_custom_postprocess` in `config/sources/families/s5p6818.conf`);
  that path is correct and not the cause.
