#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2026 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function github_actions_add_output() {
	# if CI is not GitHub Actions, do nothing
	if [[ "${GITHUB_ACTIONS}" != "true" ]]; then
		display_alert "Not running in GitHub Actions, not adding output" "'${*}'" "debug"
		return 0
	fi

	if [[ ! -f "${GITHUB_OUTPUT}" ]]; then
		exit_with_error "GITHUB_OUTPUT file not found '${GITHUB_OUTPUT}'"
	fi

	local output_name="$1"
	shift
	local output_value="$*"

	echo "${output_name}=${output_value}" >> "${GITHUB_OUTPUT}"
	display_alert "Added GHA output" "'${output_name}'='${output_value}'" "ext"
}

# Resolve the tag name of a repository's latest GitHub release; prints it on stdout.
#
#   latest_version="$(github_latest_release_tag "radxa-pkg/aic8800")" || return 1
#
# Sends GITHUB_TOKEN when the environment has one. Unauthenticated calls are
# capped at 60 per hour *per IP*, and a CI host running many builds back to back
# burns through that; an authenticated call gets 1000/hour per repository.
#
# Both failure modes are checked. A rate-limited reply is still valid JSON with
# no .tag_name in it, so an unchecked lookup yields the string "null", which
# then travels into a download filename and fails as a 404 much later on.
function github_latest_release_tag() {
	declare repo="${1}"
	declare api_url="https://api.github.com/repos/${repo}/releases/latest"

	# The token must not reach curl's argument vector: on a shared build host
	# anything able to read /proc/<pid>/cmdline could lift it out. curl takes
	# headers from stdin with "@-", so it travels over a pipe instead. With no
	# token the pipe carries nothing and curl is never told to read it.
	declare -a auth_args=()
	if [[ -n "${GITHUB_TOKEN:-}" ]]; then
		auth_args=("--header" "@-")
	fi

	# Said in both failure messages below. An exhausted quota answers 403, which reads exactly
	# like a dead URL or a private repo unless the message says which pool was being spent:
	# anonymous is 60/hour *per IP*, shared by every lookup from that host.
	declare auth_state="unauthenticated - 60 requests/hour per IP"
	if [[ -n "${GITHUB_TOKEN:-}" ]]; then
		auth_state="authenticated"
	fi

	declare api_output
	if ! api_output="$(printf '%s' "${GITHUB_TOKEN:+Authorization: Bearer ${GITHUB_TOKEN}}" \
		| curl -f --silent --show-error --location "${auth_args[@]}" "${api_url}" 2>&1)"; then
		display_alert "Failed to fetch the latest release of ${repo}" "${api_output} (${auth_state})" "error"
		return 1
	fi

	declare tag
	tag="$(printf '%s' "${api_output}" | jq -r '.tag_name' 2> /dev/null || true)"
	if [[ -z "${tag}" || "${tag}" == "null" ]]; then
		display_alert "GitHub API returned no release tag for ${repo}" \
			"${auth_state}; rate limited, or no releases published" "error"
		return 1
	fi

	# Callers interpolate the tag into URLs, filenames, and command strings that
	# chroot_sdcard runs through `bash -c`, so a tag is only ever allowed to look
	# like a version. Requiring the first character to be alphanumeric also keeps
	# a leading "-" from being read as an option by wget and friends.
	#
	# "/" is excluded even though git allows it in a tag: bcmdhd, radxa-aic8800
	# and yt6801 build a local filename out of the tag, so "release/v1.2" turns
	# /tmp/<pkg>_<tag>_all.deb into a nested path that the flat `wget -P /tmp`
	# never creates, and apt-get then fails on a file that isn't there. Refusing
	# the tag up front says why; allowing it fails later and obscurely.
	if [[ ! "${tag}" =~ ^[A-Za-z0-9][A-Za-z0-9._+~-]*$ ]]; then
		display_alert "Refusing release tag with unexpected characters for ${repo}" "'${tag}'" "error"
		return 1
	fi

	echo "${tag}"
}
