# Add compiler (gcc/clang) identifier to kernel artifact version string.
# This ensures cache invalidation when the toolchain changes.
# Enable with: ENABLE_EXTENSIONS="kernel-version-toolchain"

function artifact_kernel_version_parts__add_toolchain() {
	# Determine compiler binary
	declare kernel_compiler_bin="${KERNEL_COMPILER}gcc"
	if [[ "${KERNEL_COMPILER}" == "clang" ]]; then
		kernel_compiler_bin="clang"
	fi

	# Get compiler version (major.minor only)
	declare toolchain_id="unknown"
	if command -v "${kernel_compiler_bin}" &> /dev/null; then
		declare full_version
		full_version="$(${kernel_compiler_bin} -dumpfullversion -dumpversion 2>/dev/null || echo "")"
		if [[ -n "${full_version}" ]]; then
			# Extract major.minor, drop patch version
			declare short_version
			short_version="$(echo "${full_version}" | cut -d'.' -f1-2)"
			# Build identifier: gcc13.3 or clang18.1
			if [[ "${KERNEL_COMPILER}" == "clang" ]]; then
				toolchain_id="clang${short_version}"
			else
				toolchain_id="gcc${short_version}"
			fi
		fi
	fi

	display_alert "Extension: ${EXTENSION}: Adding toolchain to kernel version" "${toolchain_id}" "debug"

	# Add to version parts
	artifact_version_parts["_T"]="${toolchain_id}"
	artifact_version_part_order+=("0085-_T")
}
