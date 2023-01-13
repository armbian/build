# `cryptroot` / LUKS support is no longer included by default in prepare-host.sh.
# Enable this extension to include the required dependencies for building.
# This is automatically enabled if CRYPTROOT_ENABLE is set to yes in main-config.sh.

function add_host_dependencies__add_cryptroot_tooling() {
	display_alert "Adding cryptroot to host dependencies" "cryptsetup LUKS" "debug"
	EXTRA_BUILD_DEPS="${EXTRA_BUILD_DEPS} cryptsetup" # @TODO: convert to array later
}
