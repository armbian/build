#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

# This works under memoize-cached.sh::run_memoized() -- which is full of tricks.
# Nested functions are used because the source of the momoized function is used as part of the cache hash.
function memoized_git_ref_to_info() {
	declare -n MEMO_DICT="${1}" # nameref
	declare ref_type ref_name
	git_parse_ref "${MEMO_DICT[GIT_REF]}"
	MEMO_DICT+=(["REF_TYPE"]="${ref_type}")
	MEMO_DICT+=(["REF_NAME"]="${ref_name}")

	# Small detour here; if it's a tag, ask for the dereferenced commit, to avoid the annotated tag's sha1, instead get the commit tag points to.
	if [[ "${ref_type}" == "tag" ]]; then
		ref_name="${ref_name}^{}" # dereference tag
	fi

	# Get the SHA1 of the commit
	declare sha1
	display_alert "Fetching SHA1 of ${ref_type} ${ref_name}" "${MEMO_DICT[GIT_SOURCE]}" "info"
	case "${ref_type}" in
		commit)
			sha1="${ref_name}"
			;;
		*)
			sha1="$(git ls-remote --exit-code "${MEMO_DICT[GIT_SOURCE]}" "${ref_name}" | cut -f1)"
			;;
	esac

	display_alert "SHA1 of ${ref_type} ${ref_name}" "'${sha1}'" "info"

	if [[ -z "${sha1}" ]]; then
		exit_with_error "Failed to fetch SHA1 of '${MEMO_DICT[GIT_SOURCE]}' '${ref_type}' '${ref_name}' - make sure it's correct"
	fi

	MEMO_DICT+=(["SHA1"]="${sha1}")

	if [[ "${2}" == "include_makefile_body" ]]; then

		function obtain_makefile_body_from_git() {
			declare git_source="${1}"
			declare sha1="${2}"
			makefile_body="undetermined"     # outer scope
			makefile_url="undetermined"      # outer scope
			makefile_version="undetermined"  # outer scope
			makefile_codename="undetermined" # outer scope

			declare url="undetermined"
			case "${git_source}" in

				"git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git")
					url="https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain/Makefile?h=${sha1}"
					;;

					# @TODO: urgently add support for Google Mirror
					# @TODO: china mirror etc.
					# @TODO: mirrors might need to be resolved before/during/after this, refactor

				"https://github.com/"*)
					# parse org/repo from https://github.com/org/repo
					declare org_and_repo=""
					org_and_repo="$(echo "${git_source}" | cut -d/ -f4-5)"
					org_and_repo="${org_and_repo%.git}" # remove .git if present
					url="https://raw.githubusercontent.com/${org_and_repo}/${sha1}/Makefile"
					;;

				"https://gitlab.com/"*)
					# GitLab is more complex than GitHub, there can be more levels.
					# This code is incomplete... but it works for now.
					# Example: input:  https://gitlab.com/rk3588_linux/rk/kernel.git
					#          output: https://gitlab.com/rk3588_linux/rk/kernel/-/raw/linux-5.10/Makefile
					declare gitlab_path="${git_source%.git}" # remove .git
					url="${gitlab_path}/-/raw/${sha1}/Makefile"
					;;

				"https://source.codeaurora.org/external/imx/linux-imx")
					# Random, bizarre stuff here, to keep compatibility with some old stuff
					url="https://source.codeaurora.org/external/imx/linux-imx/plain/Makefile?h=${sha1}"
					;;

				*)
					exit_with_error "Unknown git source '${git_source}'"
					;;
			esac

			display_alert "Fetching Makefile via HTTP" "${url}" "debug"
			makefile_url="${url}"
			makefile_body="$(curl -sL --fail "${url}")" || exit_with_error "Failed to fetch Makefile from '${url}'"

			parse_makefile_version "${makefile_body}"

			return 0
		}

		function parse_makefile_version() {
			declare makefile_body="${1}"
			makefile_version="undetermined"      # outer scope
			makefile_codename="undetermined"     # outer scope
			makefile_full_version="undetermined" # outer scope

			local ver=()
			ver[0]=$(grep "^VERSION" <(echo "${makefile_body}") | head -1 | awk '{print $(NF)}' | grep -oE '^[[:digit:]]+' || true)
			ver[1]=$(grep "^PATCHLEVEL" <(echo "${makefile_body}") | head -1 | awk '{print $(NF)}' | grep -oE '^[[:digit:]]+' || true)
			ver[2]=$(grep "^SUBLEVEL" <(echo "${makefile_body}") | head -1 | awk '{print $(NF)}' | grep -oE '^[[:digit:]]+' || true)
			ver[3]=$(grep "^EXTRAVERSION" <(echo "${makefile_body}") | head -1 | awk '{print $(NF)}' | grep -oE '^-rc[[:digit:]]+' || true)
			makefile_version="${ver[0]:-0}${ver[1]:+.${ver[1]}}${ver[2]:+.${ver[2]}}${ver[3]}"

			# validate sanity
			if [[ "${makefile_version}" == "0" ]]; then
				exit_with_error "Unable to parse Makefile version '${makefile_version}' from body '${makefile_body}'"
			fi

			makefile_full_version="${makefile_version}"
			if [[ "${ver[3]}" == "-rc"* ]]; then # contentious:, if an "-rc" EXTRAVERSION, don't include the SUBLEVEL
				makefile_version="${ver[0]:-0}${ver[1]:+.${ver[1]}}${ver[3]}"
			fi

			# grab the codename while we're at it
			makefile_codename="$(grep "^NAME\ =\ " <(echo "${makefile_body}") | head -1 | cut -d '=' -f 2 | sed -e "s|'||g" | xargs echo -n || true)"
			# remove any starting whitespace left
			makefile_codename="${makefile_codename#"${makefile_codename%%[![:space:]]*}"}"
			# remove any trailing whitespace left
			makefile_codename="${makefile_codename%"${makefile_codename##*[![:space:]]}"}"

			return 0
		}

		display_alert "Fetching Makefile body" "${ref_name}" "debug"
		declare makefile_body makefile_url
		declare makefile_version makefile_codename makefile_full_version
		obtain_makefile_body_from_git "${MEMO_DICT[GIT_SOURCE]}" "${sha1}"
		MEMO_DICT+=(["MAKEFILE_URL"]="${makefile_url}")
		#MEMO_DICT+=(["MAKEFILE_BODY"]="${makefile_body}") # large, don't store
		MEMO_DICT+=(["MAKEFILE_VERSION"]="${makefile_version}")
		MEMO_DICT+=(["MAKEFILE_FULL_VERSION"]="${makefile_full_version}")
		MEMO_DICT+=(["MAKEFILE_CODENAME"]="${makefile_codename}")
	fi

}
