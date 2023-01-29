function armbian_register_artifacts() {

	declare -g -A ARMBIAN_ARTIFACTS_TO_HANDLERS_DICT=(
		#["firmware"]="firmware"
		["kernel"]="kernel"
		#["u-boot"]="u-boot"
	)

}
