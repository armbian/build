#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# Mask Wayland desktop sessions
#
# Some boards have limited or unstable Wayland support due to GPU or driver
# constraints. This extension allows board maintainers to disable Wayland
# sessions in a desktop-agnostic and upgrade-safe manner by masking session
# definitions.
#
# Wayland sessions are masked by placing empty marker files with matching names
# in /usr/local/share/wayland-sessions/, which takes precedence over
# /usr/share/wayland-sessions/.
#
# Usage (board config):
#   enable_extension "wayland-sessions-mask"
#
# Default behavior when unset: Wayland sessions remain enabled.
# post_post_debootstrap_tweaks__wayland_sessions_mask masks existing Wayland desktop session definitions by creating empty marker files in ${SDCARD}/usr/local/share/wayland-sessions that correspond to each .desktop file in ${SDCARD}/usr/share/wayland-sessions. It displays an informational alert and returns without action if the source directory is absent.

post_post_debootstrap_tweaks__wayland_sessions_mask() {

	# Only apply to desktop images with Wayland sessions present
	[[ -d "${SDCARD}/usr/share/wayland-sessions" ]] || return 0

	local src_dir dst_dir sess_file
	src_dir="${SDCARD}/usr/share/wayland-sessions"
	dst_dir="${SDCARD}/usr/local/share/wayland-sessions"

	display_alert \
		"Masking Wayland desktop sessions" \
		"Board policy: wayland-sessions-mask" \
		"info"

	mkdir -p "${dst_dir}"

	# Mask all existing Wayland session definitions
	for sess_file in "${src_dir}"/*.desktop; do
		[[ -f "${sess_file}" ]] || continue
		: > "${dst_dir}/$(basename "${sess_file}")"
	done
}