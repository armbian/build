# This has... everything: https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/commit/?h=linux-6.1.y
# This has... everything: https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/commit/?h=v6.2-rc5

# get the sha1 of the commit on tag or branch
# git ls-remote --exit-code --symref git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git v6.2-rc5
# git ls-remote --exit-code --symref git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git v6.2-rc5

# 93f875a8526a291005e7f38478079526c843cbec	refs/heads/linux-6.1.y
# 4cc398054ac8efe0ff832c82c7caacbdd992312a	refs/tags/v6.2-rc5

# https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/tree/Makefile?h=linux-6.1.y
# plaintext: https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain/Makefile?h=4cc398054ac8efe0ff832c82c7caacbdd992312a

function memoized_git_ref_to_info() {
	declare -n MEMO_DICT="${1}" # nameref
	declare ref_type ref_name
	git_parse_ref "${MEMO_DICT[GIT_REF]}"
	MEMO_DICT+=(["REF_TYPE"]="${ref_type}")
	MEMO_DICT+=(["REF_NAME"]="${ref_name}")

	# Get the SHA1 of the commit
	declare sha1
	sha1="$(git ls-remote --exit-code "${MEMO_DICT[GIT_SOURCE]}" "${ref_name}" | cut -f1)"
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
					url="https://raw.githubusercontent.com/${org_and_repo}/${sha1}/Makefile"
					;;

				"https://source.codeaurora.org/external/imx/linux-imx")
					# Random, bizarre stuff here, to keep compatibility with some old stuff
					url="https://source.codeaurora.org/external/imx/linux-imx/plain/Makefile?h=${sha1}"
					;;

				*)
					exit_with_error "Unknown git source '${git_source}'"
					;;
			esac

			display_alert "Fetching Makefile via HTTP" "${url}" "warn"
			makefile_url="${url}"
			makefile_body="$(curl -sL "${url}")"

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

		display_alert "Fetching Makefile body" "${ref_name}" "warn"
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
