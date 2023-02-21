function extension_prepare_config__prepare_localmodconfig() {
	display_alert "${EXTENSION}: nomod enabled" "${LSMOD} -- kernels won't work" "warn"
}

# This produces non-working kernels. It's meant for testing kernel image build and packaging.
function custom_kernel_config__apply_mod2noconfig() {
	kernel_config_modifying_hashes+=("mod2noconfig")
	[[ -f .config ]] && run_kernel_make mod2noconfig
	return 0 # short-circuit above
}
