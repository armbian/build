function armbian_register_artifacts() {

	declare -g -A ARMBIAN_ARTIFACTS_TO_HANDLERS_DICT=(
		# deb-tar
		["kernel"]="kernel"

		# deb
		["u-boot"]="uboot"
		["uboot"]="uboot"
		["firmware"]="firmware"
		["full_firmware"]="full_firmware"

		# tar.zst
		["rootfs"]="rootfs"
	)

}
