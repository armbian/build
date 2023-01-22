function extension_prepare_config__prepare_localmodconfig() {
	display_alert "${EXTENSION}: nomod enabled" "${LSMOD} -- kernels won't work" "warn"
}

# This produces non-working kernels. It's meant for testing kernel image build and packaging.
function custom_kernel_config_post_defconfig__apply_mod2noconfig() {
	run_kernel_make mod2noconfig
}
