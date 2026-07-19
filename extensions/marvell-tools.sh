#!/usr/bin/env bash
function fetch_sources_tools__marvell_tools() {
	# EspressoBin/A3720 WTMI (sys_init): upstream Marvell A3700-utils is abandoned
	# and no longer compiles/links on a modern gcc/ld toolchain ('bool' is a C23
	# keyword; sys_init main() hits a "dangerous relocation"). Use bschnei's fork,
	# pinned to the commit the working espressobin-bootloader uses, which fixes both.
	fetch_from_repo "https://github.com/bschnei/A3700-utils-marvell" "marvell-tools" "commit:f423ac60285fe1ee8c13734f9aaba47dbccb28a9"
	# Pinned to the commit the working espressobin-bootloader uses (includes a gcc
	# build fix); reproducible firmware. Shared with MacchiatoBin (a8040), which is
	# best-effort here anyway.
	fetch_from_repo "https://github.com/MarvellEmbeddedProcessors/mv-ddr-marvell.git" "marvell-ddr" "commit:7bcb9dc7ea7fa233bf96bd0350a4ec7c205e342e"
	fetch_from_repo "https://github.com/MarvellEmbeddedProcessors/binaries-marvell" "marvell-binaries" "branch:binaries-marvell-armada-SDK10.0.1.0"
	fetch_from_repo "https://github.com/weidai11/cryptopp.git" "cryptopp" "branch:master"
	# CZ.NIC secure firmware (WTMI). Pinned to the commit the working
	# espressobin-bootloader uses; reproducible. EspressoBin-only.
	fetch_from_repo "https://gitlab.nic.cz/turris/mox-boot-builder.git" "mox-boot" "commit:14f39dd4156f1a8c9aa13f27a5a51e66f4b88d90"
}
