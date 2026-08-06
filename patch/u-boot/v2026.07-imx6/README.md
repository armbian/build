# `v2026.07-imx6` — modern u-boot patch dir for bumped i.MX6 boards

Intentionally (almost) empty. Used by boards moved off the legacy imx6 u-boot
(`legacy/u-boot-imx6`, pinned to **v2017.11**) onto a modern u-boot
(**v2026.07-rc4**) that builds on Debian trixie — the old pylibfdt setup.py
fails on Python 3.13 (`distutils` removed) and against SWIG 4.3.

Currently used by **udoo** only (pilot bump; see `config/boards/udoo.csc`). The
upstream `udoo_defconfig` + `imx6q-udoo` DT are used as-is; Armbian-specific
tweaks (SPL raw-sector load to match the raw-dd `write_uboot_platform` layout)
are applied via `post_config_uboot_target` in the board file, not as patches.

Add real patches here only if a board needs a source change that can't be done
through defconfig.
