#
# Linux splash file
#
function apply_kernel_patches_for_bootsplash() {
	# previously: if linux-version compare "${version}" ge 5.10 && [ $SKIP_BOOTSPLASH != yes ]; then
	[[ "${SKIP_BOOTSPLASH}" == "yes" ]] && return 0
	linux-version compare "${version}" le 5.10 && return 0

	display_alert "Adding" "Kernel bootsplash patch" "info"

	if linux-version compare "${version}" ge 5.11; then
		process_patch_file "${SRC}/patch/misc/bootsplash-5.16.y-0000-Revert-fbcon-Avoid-cap-set-but-not-used-warning.patch" "applying"
	fi

	process_patch_file "${SRC}/patch/misc/bootsplash-5.16.y-0001-Revert-fbcon-Add-option-to-enable-legacy-hardware-ac.patch" "applying"

	if linux-version compare "${version}" ge 5.15; then
		process_patch_file "${SRC}/patch/misc/bootsplash-5.16.y-0002-Revert-vgacon-drop-unused-vga_init_done.patch" "applying"
	fi

	process_patch_file "${SRC}/patch/misc/bootsplash-5.16.y-0003-Revert-vgacon-remove-software-scrollback-support.patch" "applying"
	process_patch_file "${SRC}/patch/misc/bootsplash-5.16.y-0004-Revert-drivers-video-fbcon-fix-NULL-dereference-in-f.patch" "applying"
	process_patch_file "${SRC}/patch/misc/bootsplash-5.16.y-0005-Revert-fbcon-remove-no-op-fbcon_set_origin.patch" "applying"
	process_patch_file "${SRC}/patch/misc/bootsplash-5.16.y-0006-Revert-fbcon-remove-now-unusued-softback_lines-curso.patch" "applying"
	process_patch_file "${SRC}/patch/misc/bootsplash-5.16.y-0007-Revert-fbcon-remove-soft-scrollback-code.patch" "applying"

	process_patch_file "${SRC}/patch/misc/0001-bootsplash.patch" "applying"
	process_patch_file "${SRC}/patch/misc/0002-bootsplash.patch" "applying"
	process_patch_file "${SRC}/patch/misc/0003-bootsplash.patch" "applying"
	process_patch_file "${SRC}/patch/misc/0004-bootsplash.patch" "applying"
	process_patch_file "${SRC}/patch/misc/0005-bootsplash.patch" "applying"
	process_patch_file "${SRC}/patch/misc/0006-bootsplash.patch" "applying"
	process_patch_file "${SRC}/patch/misc/0007-bootsplash.patch" "applying"
	process_patch_file "${SRC}/patch/misc/0008-bootsplash.patch" "applying"
	process_patch_file "${SRC}/patch/misc/0009-bootsplash.patch" "applying"
	process_patch_file "${SRC}/patch/misc/0010-bootsplash.patch" "applying"
	process_patch_file "${SRC}/patch/misc/0011-bootsplash.patch" "applying"
	process_patch_file "${SRC}/patch/misc/0012-bootsplash.patch" "applying"
}
