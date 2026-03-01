#!/bin/bash
# Armbian Generic Calamares Installer Extension

function post_repo_customize_image__install_calamares() {
	display_alert "Adding calamares package to the image."
	do_with_retries 3 chroot_sdcard_apt_get_update
	do_with_retries 3 chroot_sdcard_apt_get_install "calamares qtwayland5"
	display_alert "Configuring Calamares for any Desktop Environment..."
	run_host_command_logged "cp -vr \"${SRC}/extensions/calamares-installer/config/\"* \"$SDCARD/\""

	# --- Create the Armbian Branding Directory ---
	# Calamares needs a branding directory with a 'branding.desc' file.
	# We copy the default theme as a base.
	echo "Setting up Calamares branding..."
	mkdir -p "${SDCARD}/etc/calamares/branding"
	run_host_command_logged "cp -r \"${SDCARD}/usr/share/calamares/branding/default\" \"${SDCARD}/etc/calamares/branding/armbian\""

	# --- Fix the Branding Component Name ---
	# The copied branding.desc file still contains 'componentName: default'.
	# We must change it to 'armbian' to match our directory name and settings.conf.
	echo "Updating branding component name to 'armbian'..."
	sed -i 's/componentName: default/componentName: armbian/g' "${DEST}/etc/calamares/branding/armbian/branding.desc"

	# --- Copy the QML Files ---
	# The default branding theme is often incomplete and missing the 'qml' folder.
	# We must get the QML files from the global Calamares installation directory.
	QML_SOURCE_DIR="${SDCARD}/usr/share/calamares/qml"
	QML_BRANDING_DIR="${SDCARD}/etc/calamares/branding/armbian/qml"

	if [ -d "$QML_SOURCE_DIR" ]; then
		echo "Copying QML files from global directory to branding directory..."
		mkdir -p "$QML_BRANDING_DIR"
		run_host_command_logged "cp -r \"$QML_SOURCE_DIR\"/* \"$QML_BRANDING_DIR/\""
	else
		echo "ERROR: Global QML directory not found at $QML_SOURCE_DIR"
		echo "The 'calamares' package may be incomplete or broken."
		exit 1
	fi
	chroot_sdcard "chmod +x /usr/libexec/armbian-finalize.sh"
	display_alert "Calamares configuration complete."
}
