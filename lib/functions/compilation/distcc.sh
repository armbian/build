# Config:
# declare -A -g DISTCC_TARGETS_HOST_PORT=()
# declare -A -g DISTCC_TARGETS_CORES=()
# declare -a -g DISTCC_TARGETS_SPEED_ORDER=()
# Vars:
# declare -a -g DISTCC_CROSS_COMPILE_PREFIX=()
# declare -a -g DISTCC_MAKE_J_PARALLEL=()
function prepare_distcc_compilation_config() {
	declare -a DISTCC_TARGETS_SEGMENTS=()

	declare -i total_distcc_cores=0
	# Loop over DISTCC_TARGETS_SPEED_ORDER, get the details from DISTCC_TARGETS_HOST_PORT, and add the targets to the DISTCC_TARGETS_SEGMENTS array.
	for target in "${DISTCC_TARGETS_SPEED_ORDER[@]}"; do
		local host_port="${DISTCC_TARGETS_HOST_PORT[$target]}"
		declare -i cores="${DISTCC_TARGETS_CORES[$target]}"

		# Check if host_port is not empty, otherwise continue.
		if [[ -z "$host_port" ]]; then
			display_alert "Skipping distcc target" "$target has no host_port defined in config" "wrn"
			continue
		fi
		# Check if $cores is bigger than zero (0), otherwise continue.
		if [[ $cores -lt 1 ]]; then
			display_alert "Skipping distcc target" "$target has no cores defined in config" "wrn"
			continue
		fi
		total_distcc_cores=$((total_distcc_cores + cores))
		DISTCC_TARGETS_SEGMENTS+=("${host_port}/${cores},lzo")
	done

	# If DISTCC_TARGETS_SEGMENTS is not empty, add the localslots to it.
	if [[ ${#DISTCC_TARGETS_SEGMENTS[@]} -gt 0 ]]; then
		# Use the total number of distcc cores plus 2
		DISTCC_TARGETS_SEGMENTS+=(--localslots=2 --localslots_cpp=$((total_distcc_cores + 2)))

		DISTCC_EXTRA_ENVS=(
			"HOME=\"${HOME}\""                               # Set the HOME, for distcc
			"DISTCC_HOSTS=\"${DISTCC_TARGETS_SEGMENTS[*]}\"" # DistCC!
		)

		DISTCC_CROSS_COMPILE_PREFIX=("distcc")

		DISTCC_MAKE_J_PARALLEL=("-j$((total_distcc_cores * 2))") # Use double the total distcc cores

		display_alert "DISTCC_TARGETS_SEGMENTS" "${DISTCC_TARGETS_SEGMENTS[*]}" "warn"
	else
		# If not using distcc, just add "$CTHREADS" to the DISTCC_MAKE_J_PARALLEL array.
		DISTCC_MAKE_J_PARALLEL=("${CTHREADS}")
	fi

	return 0
}
