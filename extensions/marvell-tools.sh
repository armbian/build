function fetch_sources_tools__marvell_tools() {
	fetch_from_repo "https://github.com/MarvellEmbeddedProcessors/A3700-utils-marvell" "marvell-tools" "branch:master"
	fetch_from_repo "https://github.com/MarvellEmbeddedProcessors/mv-ddr-marvell.git" "marvell-ddr" "branch:master"
	fetch_from_repo "https://github.com/MarvellEmbeddedProcessors/binaries-marvell" "marvell-binaries" "branch:binaries-marvell-armada-SDK10.0.1.0"
	fetch_from_repo "https://github.com/weidai11/cryptopp.git" "cryptopp" "branch:master"
    fetch_from_repo "https://gitlab.nic.cz/turris/mox-boot-builder.git" "mox-boot" "branch:master"
}
