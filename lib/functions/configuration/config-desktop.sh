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

	# Refresh the armbian-configng clone on EVERY desktop build,
	# regardless of whether DESKTOP_ENVIRONMENT was pre-set. The
	# clone feeds two downstream consumers:
	#
	#   1. The interactive DE-selection dialog below — only fires
	#      when DESKTOP_ENVIRONMENT is empty.
	#   2. artifact_rootfs_config_dump, which reads the clone's
	#      `git log -1 -- tools/modules/desktops/` as the
	#      CONFIGNG_DESKTOPS_HASH input that (via create-cache.sh's
	#      cache_type) fingerprints the rootfs tarball filename.
	#
	# Keeping the fetch inside the `-z DESKTOP_ENVIRONMENT` branch
	# meant every non-interactive build (CI, items-from-inventory,
	# scripted local) skipped it — so the hash was computed against
	# whatever stale clone happened to be on disk and the build
	# happily cache-hit a pre-configng-change rootfs. Hoisting the
	# fetch up here makes the clone authoritative for every
	# BUILD_DESKTOP=yes invocation.
	fetch_from_repo "https://github.com/armbian/configng" "armbian-configng" "branch:main"

	local configng_dir="${SRC}/cache/sources/armbian-configng"
	local yaml_dir="${configng_dir}/tools/modules/desktops/yaml"
	local parser="${configng_dir}/tools/modules/desktops/scripts/parse_desktop_yaml.py"

	if [[ ! -f "${parser}" ]]; then
		exit_with_error "Desktop parser not found at ${parser}" \
			"armbian-config clone may be incomplete"
	fi

	# --- DE selection ---
	if [[ -z $DESKTOP_ENVIRONMENT ]]; then

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

		# Capture stdout and stderr separately and check the exit code
		# explicitly. Previously stderr was redirected to /dev/null and
		# only stdout was captured, so a non-zero exit (missing python3
		# yaml module, malformed YAML, parser-side argparse change, …)
		# left the SUBSHELL ERR trap firing at this line with no
		# diagnostic — see the build hang at config-desktop.sh:78
		# referenced from production logs.
		local de_json de_stderr de_rc=0
		de_stderr=$(mktemp)
		de_json=$(python3 "${parser}" "${yaml_dir}" --list-json \
			"${RELEASE}" "${ARCH}" --status "${status_filter}" 2>"${de_stderr}") || de_rc=$?
		if [[ "${de_rc}" -ne 0 ]]; then
			local err_text
			err_text=$(cat "${de_stderr}" 2> /dev/null || true)
			rm -f "${de_stderr}"
			exit_with_error "Desktop parser failed (exit ${de_rc}) for ${RELEASE}/${ARCH}" \
				"stderr: ${err_text:-<empty>}"
		fi
		rm -f "${de_stderr}"
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

	# Backwards-compat: the legacy DESKTOP_APPGROUPS_SELECTED variable
	# used to pick extra package groups (office, multimedia, programming,
	# …) on top of a base desktop. The tier model subsumes those groups —
	# `full` includes everything the old appgroups provided. If a
	# userpatch or board config still sets DESKTOP_APPGROUPS_SELECTED and
	# hasn't opted into a tier explicitly, assume `full` to preserve the
	# old behaviour. Treat "none" (the old sentinel meaning no appgroups
	# at all) as empty — the operator didn't actually pick any extras.
	if [[ -z $DESKTOP_TIER && -n $DESKTOP_APPGROUPS_SELECTED && "$DESKTOP_APPGROUPS_SELECTED" != "none" ]]; then
		display_alert "desktop-config" "legacy DESKTOP_APPGROUPS_SELECTED='${DESKTOP_APPGROUPS_SELECTED}' → selecting tier=full" "wrn"
		DESKTOP_TIER="full"
	fi

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
