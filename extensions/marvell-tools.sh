#!/usr/bin/env bash
function fetch_sources_tools__marvell_tools() {
	# EspressoBin/A3720 WTMI (sys_init): upstream Marvell A3700-utils is abandoned
	# and no longer compiles/links on a modern gcc/ld toolchain ('bool' is a C23
	# keyword; sys_init main() hits a "dangerous relocation"). Use bschnei's fork,
	# pinned to the commit the working espressobin-bootloader uses, which fixes both.
	fetch_from_repo "https://github.com/bschnei/A3700-utils-marvell" "marvell-tools" "commit:f423ac60285fe1ee8c13734f9aaba47dbccb28a9"
	fetch_from_repo "https://github.com/MarvellEmbeddedProcessors/mv-ddr-marvell.git" "marvell-ddr" "branch:master"
	fetch_from_repo "https://github.com/MarvellEmbeddedProcessors/binaries-marvell" "marvell-binaries" "branch:binaries-marvell-armada-SDK10.0.1.0"
	fetch_from_repo "https://github.com/weidai11/cryptopp.git" "cryptopp" "branch:master"
	fetch_from_repo "https://gitlab.nic.cz/turris/mox-boot-builder.git" "mox-boot" "branch:master"
}
