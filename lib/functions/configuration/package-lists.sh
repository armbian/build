function get_caller_reference() {
	# grab the caller function name, its source file and line number
	local caller_ref="${FUNCNAME[2]}"
	local caller_file="${BASH_SOURCE[2]}"
	local caller_line="${BASH_LINENO[1]}"
	# the format below must match the parser in parseEnvForList in aggregation.py
	declare -g caller_reference="${caller_ref}:${caller_file}:${caller_line}"
}

# Adds to the main package list.
function add_packages_to_rootfs() {
	get_caller_reference
	declare -g -a EXTRA_PACKAGES_ROOTFS=("${EXTRA_PACKAGES_ROOTFS[@]}")
	declare -g -a EXTRA_PACKAGES_ROOTFS_REFS=("${EXTRA_PACKAGES_ROOTFS_REFS[@]}")
	for package in "${@}"; do
		# add package to the list
		EXTRA_PACKAGES_ROOTFS+=("${package}")
		EXTRA_PACKAGES_ROOTFS_REFS+=("${caller_reference}")
	done
}

# Adds to the image package list; they're not cached in the rootfs.
function add_packages_to_image() {
	get_caller_reference
	declare -g -a EXTRA_PACKAGES_IMAGE=("${EXTRA_PACKAGES_IMAGE[@]}")
	declare -g -a EXTRA_PACKAGES_IMAGE_REFS=("${EXTRA_PACKAGES_IMAGE_REFS[@]}")
	for package in "${@}"; do
		# add package to the list
		EXTRA_PACKAGES_IMAGE+=("${package}")
		EXTRA_PACKAGES_IMAGE_REFS+=("${caller_reference}")
	done
}

# Removes a package from all lists: debootstrap, rootfs, desktop and image.
function remove_packages() {
	get_caller_reference
	declare -g -a REMOVE_PACKAGES=("${REMOVE_PACKAGES[@]}")
	declare -g -a REMOVE_PACKAGES_REFS=("${REMOVE_PACKAGES_REFS[@]}")
	for package in "${@}"; do
		# add package to the list
		REMOVE_PACKAGES+=("${package}")
		REMOVE_PACKAGES_REFS+=("${caller_reference}")
	done
}
