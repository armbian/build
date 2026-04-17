#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2026 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

# Interactive desktop configuration: DE selection + tier selection.
# Desktop packages are installed by armbian-config's module_desktops
# at image-build time (see distro-agnostic.sh). This file collects
# the two user-facing choices: which DE and which tier.
#
# The available DEs are queried from armbian-config's YAML-driven
# desktop definitions. The configng repo is cloned into cache/sources/
# via the build framework's standard fetch_from_repo, then the
# standalone Python parser runs on the host (no chroot, no root).
#
# Variables set:
#   DESKTOP_ENVIRONMENT   — xfce, gnome, kde-plasma, mate, cinnamon, ...
#   DESKTOP_TIER          — minimal, mid, full
#
# Legacy variables (removed — armbian-config YAML tiers subsume them):
#   DESKTOP_ENVIRONMENT_CONFIG_NAME
#   DESKTOP_APPGROUPS_SELECTED

function interactive_desktop_main_configuration() {
	[[ $BUILD_DESKTOP != "yes" ]] && return 0

	display_alert "desktop-config" "DESKTOP_ENVIRONMENT entry: ${DESKTOP_ENVIRONMENT}" "debug"

	# --- DE selection ---
	if [[ -z $DESKTOP_ENVIRONMENT ]]; then

		# Fetch armbian-config (configng) to get the YAML desktop
		# definitions and the standalone Python parser.
		fetch_from_repo "https://github.com/armbian/configng" "armbian-configng" "branch:main"

		local configng_dir="${SRC}/cache/sources/armbian-configng"
		local yaml_dir="${configng_dir}/tools/modules/desktops/yaml"
		local parser="${configng_dir}/tools/modules/desktops/scripts/parse_desktop_yaml.py"

		if [[ ! -f "${parser}" ]]; then
			exit_with_error "Desktop parser not found at ${parser}" \
				"armbian-config clone may be incomplete"
		fi

		# EXPERT mode controls which editorial `status:` values are
		# surfaced in the dialog:
		#   default: `status: supported` only
		#   EXPERT:  `status: supported` + `status: community` (CSC)
		# `status: unsupported` DEs are never offered from the build
		# dialog — they're vendor-specific (e.g. bianbu on riscv64)
		# and only reachable via `armbian-config --api` on a running
		# system, not baked into an image.
		local status_filter="supported"
		[[ "${EXPERT}" == "yes" ]] && status_filter="supported,community"

		local de_json
		de_json=$(python3 "${parser}" "${yaml_dir}" --list-json \
			"${RELEASE}" "${ARCH}" --status "${status_filter}" 2>/dev/null)
		if [[ -z "${de_json}" || "${de_json}" == "[]" ]]; then
			exit_with_error "No desktop environments available for ${RELEASE}/${ARCH}" \
				"Parser returned an empty list"
		fi

		# Build dialog options from the JSON output. Server-side
		# `--filter available` (the parser default) guarantees only
		# DEs whose YAML declares this (release, arch) reach us, and
		# `--status` above handles the editorial filter. Append a
		# " [CSC]" marker to community DEs so the user can tell them
		# apart from first-class supported ones at a glance.
		local -a options=()
		while IFS=$'\t' read -r de_name de_desc de_status; do
			[[ -z "${de_name}" ]] && continue
			local label="${de_desc}"
			[[ "${de_status}" == "community" ]] && label="${de_desc} [CSC]"
			options+=("${de_name}" "${label}")
		done < <(echo "${de_json}" | python3 -c "
import sys, json
for de in json.load(sys.stdin):
    print(de.get('name','') + '\t' + de.get('description','') + '\t' + de.get('status',''))
" 2>/dev/null)

		if [[ "${#options[@]}" -eq 0 ]]; then
			exit_with_error "No desktop environments available for ${RELEASE}/${ARCH}"
		fi

		dialog_menu "Choose a desktop environment" "$backtitle" \
			"Select the default desktop environment to bundle with this image" \
			"${options[@]}"
		set_interactive_config_value DESKTOP_ENVIRONMENT "${DIALOG_MENU_RESULT}"

		if [[ -z "${DESKTOP_ENVIRONMENT}" ]]; then
			exit_with_error "No desktop environment selected"
		fi
	fi

	display_alert "desktop-config" "DESKTOP_ENVIRONMENT selected: ${DESKTOP_ENVIRONMENT}" "debug"

	# --- Tier selection ---
	if [[ -z $DESKTOP_TIER ]]; then
		local -a options=(
			"minimal" "DE + display manager (~500 MB)"
			"mid" "Browser, file manager, media apps (~1 GB)"
			"full" "Office, creative, dev tools (~2.5 GB)"
		)
		dialog_menu "Choose desktop tier" "$backtitle" \
			"Select which package set to install with this desktop.\nTiers can be upgraded or downgraded at any time\nusing armbian-config on the running system." \
			"${options[@]}"
		set_interactive_config_value DESKTOP_TIER "${DIALOG_MENU_RESULT}"

		if [[ -z "${DESKTOP_TIER}" ]]; then
			DESKTOP_TIER="mid"
		fi
	fi

	display_alert "desktop-config" "DESKTOP_TIER selected: ${DESKTOP_TIER}" "debug"
}
