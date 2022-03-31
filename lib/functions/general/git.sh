#
# This function retries Git operations to avoid failure in case remote is borked
#
improved_git() {
	local real_git
	real_git="$(command -v git)"
	local retries=3
	local delay=10
	local count=0
	while [ $count -lt $retries ]; do
		run_host_command_logged_raw "$real_git" --no-pager "$@" && return 0 # this gobbles up errors, but returns if OK, so everything after is error
		count=$((count + 1))
		display_alert "improved_git try $count failed, retrying in ${delay} seconds" "git $*" "warn"
		sleep $delay
	done
	display_alert "improved_git, too many retries" "git $*" "err"
	return 17 # explode with error if this is reached, "too many retries"
}

# Not improved, just regular, but logged "correctly".
regular_git() {
	run_host_command_logged_raw git --no-pager "$@"
}

# avoid repeating myself too much
function improved_git_fetch() {
	improved_git fetch --progress --verbose --no-auto-maintenance "$@"
}

# fetch_from_repo <url> <directory> <ref> <ref_subdir>
# <url>: remote repository URL
# <directory>: local directory; subdir for branch/tag will be created
# <ref>:
#	branch:name
#	tag:name
#	head(*)
#	commit:hash
#
# *: Implies ref_subdir=no
#
# <ref_subdir>: "yes" to create subdirectory for tag or branch name
#
fetch_from_repo() {
	display_alert "fetch_from_repo" "$*" "git"
	local url=$1
	local dir=$2
	local ref=$3
	local ref_subdir=$4
	local git_work_dir

	# Set GitHub mirror before anything else touches $url
	url=${url//'https://github.com/'/$GITHUB_SOURCE'/'}

	# The 'offline' variable must always be set to 'true' or 'false'
	local offline=false
	if [[ "${OFFLINE_WORK}" == "yes" ]]; then
		offline=true
	fi

	[[ -z $ref || ($ref != tag:* && $ref != branch:* && $ref != head && $ref != commit:*) ]] && exit_with_error "Error in configuration"
	local ref_type=${ref%%:*} ref_name=${ref##*:}
	if [[ $ref_type == head ]]; then
		ref_name=HEAD
	fi

	display_alert "Getting sources from Git" "$dir $ref_name" "info"

	local workdir=$dir
	if [[ $ref_subdir == yes ]]; then
		workdir=$dir/$ref_name
	fi

	git_work_dir="${SRC}/cache/sources/${workdir}"

	# if GIT_FIXED_WORKDIR has something, ignore above logic and use that directly.
	if [[ "${GIT_FIXED_WORKDIR}" != "" ]]; then
		display_alert "GIT_FIXED_WORKDIR is set to" "${GIT_FIXED_WORKDIR}" "git"
		git_work_dir="${SRC}/cache/sources/${GIT_FIXED_WORKDIR}"
	fi

	mkdir -p "${git_work_dir}" || exit_with_error "No path or no write permission" "${git_work_dir}"

	cd "${git_work_dir}" || exit

	display_alert "Git working dir" "${git_work_dir}" "git"

	local expected_origin_url actual_origin_url
	expected_origin_url="$(echo -n "${url}" | sed 's/^.*@//' | sed 's/^.*\/\///')"

	# Make sure the origin matches what is expected. If it doesn't, clean up and start again.
	if [[ "$(git rev-parse --git-dir)" == ".git" ]]; then
		actual_origin_url="$(git config remote.origin.url | sed 's/^.*@//' | sed 's/^.*\/\///')"
		if [[ "${expected_origin_url}" != "${actual_origin_url}" ]]; then
			display_alert "Remote git URL does not match, deleting working copy" "${git_work_dir} expected: '${expected_origin_url}' actual: '${actual_origin_url}'" "warn"
			cd "${SRC}" || exit 3                                                                            # free up cwd
			run_host_command_logged rm -rf "${git_work_dir}"                                                 # delete the dir
			mkdir -p "${git_work_dir}" || exit_with_error "No path or no write permission" "${git_work_dir}" # recreate
			cd "${git_work_dir}" || exit                                                                     #reset cwd
		fi
	fi

	local do_warmup_remote="no" do_cold_bundle="no" do_add_origin="no"

	if [[ "$(git rev-parse --git-dir)" != ".git" ]]; then
		# Dir is not a git working copy. Make it so.
		display_alert "Creating local copy" "$dir $ref_name"
		regular_git init -q --initial-branch="armbian_unused_initial_branch" .
		offline=false          # Force online, we'll need to fetch.
		do_add_origin="yes"    # Just created the repo, it needs an origin later.
		do_warmup_remote="yes" # Just created the repo, mark it as ready to receive the warm remote if exists.
		do_cold_bundle="yes"   # Just created the repo, mark it as ready to receive a cold bundle if that is available.
		# @TODO: possibly hang a cleanup handler here: if this fails, ${git_work_dir} should be removed.
	fi

	local changed=false

	# get local hash; might fail
	local local_hash
	local_hash=$(git rev-parse @ 2> /dev/null || true) # Don't fail nor output anything if failure

	# when we work offline we simply return the sources to their original state
	if ! $offline; then

		case $ref_type in
			branch)
				# TODO: grep refs/heads/$name
				local remote_hash
				remote_hash=$(git ls-remote -h "${url}" "$ref_name" | head -1 | cut -f1)
				[[ -z $local_hash || "${local_hash}" != "a${remote_hash}" ]] && changed=true
				;;
			tag)
				local remote_hash
				remote_hash=$(git ls-remote -t "${url}" "$ref_name" | cut -f1)
				if [[ -z $local_hash || "${local_hash}" != "${remote_hash}" ]]; then
					remote_hash=$(git ls-remote -t "${url}" "$ref_name^{}" | cut -f1)
					[[ -z $remote_hash || "${local_hash}" != "${remote_hash}" ]] && changed=true
				fi
				;;
			head)
				local remote_hash
				remote_hash=$(git ls-remote "${url}" HEAD | cut -f1)
				[[ -z $local_hash || "${local_hash}" != "${remote_hash}" ]] && changed=true
				;;
			commit)
				[[ -z $local_hash || $local_hash == "@" ]] && changed=true
				;;
		esac

		display_alert "Git local_hash vs remote_hash" "${local_hash} vs ${remote_hash}" "git"

	fi # offline

	local checkout_from="HEAD" # Probably best to use the local revision?

	if [[ "${changed}" == "true" ]]; then
		git_handle_cold_and_warm_bundle_remotes # Delegate to function to find or create cache if appropriate.

		if [[ "${do_add_origin}" == "yes" ]]; then
			regular_git remote add origin "${url}"
		fi

		# remote was updated, fetch and check out updates, but not tags; tags pull their respective commits too, making it a huge fetch.
		display_alert "Fetching updates from origin" "$dir $ref_name"
		case $ref_type in
			branch | commit) improved_git_fetch --no-tags origin "${ref_name}" ;;
			tag) improved_git_fetch --no-tags origin tags/"${ref_name}" ;;
			head) improved_git_fetch --no-tags origin HEAD ;;
		esac
		display_alert "Origin fetch completed, working copy size" "$(du -h -s | awk '{print $1}')" "git"
		checkout_from="FETCH_HEAD"
	fi

	# should be declared in outside scope, so can be read.
	checked_out_revision_mtime="$(git log --date='format:%Y%m%d%H%M%S' --format='format:%ad' -1 "${checkout_from}")"
	checked_out_revision_ts="$(git log -1 --pretty=%ct "${checkout_from}")"
	display_alert "checked_out_revision_mtime set!" "${checked_out_revision_mtime} - ${checked_out_revision_ts}" "git"

	display_alert "Cleaning git dir" "$(git status -s 2> /dev/null | wc -l) files" # working directory is not clean, show it

	#fasthash_debug "before git checkout of $dir $ref_name" # fasthash interested in this
	regular_git checkout -f -q "${checkout_from}" # Return the files that are tracked by git to the initial state.

	#fasthash_debug "before git clean of $dir $ref_name"
	regular_git clean -q -d -f # Files that are not tracked by git and were added when the patch was applied must be removed.

	# set the checkout date on all the versioned files.
	# @TODO: this is contentious. disable for now. patches will still use the mininum date set by checked_out_revision_mtime above
	#git ls-tree -r -z --name-only "${checkout_from}" | xargs -0 -- touch -m -t "${checked_out_revision_mtime:0:12}.${checked_out_revision_mtime:12}"
	#fasthash_debug "after setting checkout time for $dir $ref_name" #yeah

	if [[ -f .gitmodules ]]; then
		display_alert "Updating submodules" "" "ext"
		# FML: http://stackoverflow.com/a/17692710
		for i in $(git config -f .gitmodules --get-regexp path | awk '{ print $2 }'); do
			cd "${git_work_dir}" || exit
			local surl sref
			surl=$(git config -f .gitmodules --get "submodule.$i.url")
			sref=$(git config -f .gitmodules --get "submodule.$i.branch" || true)
			if [[ -n $sref ]]; then
				sref="branch:$sref"
			else
				sref="head"
			fi
			# @TODO: in case of the bundle stuff this will fail terribly
			fetch_from_repo "$surl" "$workdir/$i" "$sref"
		done
	fi

	display_alert "Final working copy size" "$(du -h -s | awk '{print $1}')" "git"
	#fasthash_debug "at the end of fetch_from_repo $dir $ref_name"
}

function git_fetch_from_bundle_file() {
	local bundle_file="${1}" remote_name="${2}" shallow_file="${3}"
	regular_git bundle verify "${bundle_file}"               # Make sure bundle is valid.
	regular_git remote add "${remote_name}" "${bundle_file}" # Add the remote pointing to the cold bundle file
	if [[ -f "${shallow_file}" ]]; then
		display_alert "Bundle is shallow" "${shallow_file}" "git"
		cp -p "${shallow_file}" ".git/shallow"
	fi
	improved_git_fetch --tags "${remote_name}" # Fetch it! (including tags!)
	display_alert "Bundle fetch '${remote_name}' completed, working copy size" "$(du -h -s | awk '{print $1}')" "git"
}

function download_git_bundle_from_http() {
	local bundle_file="${1}" bundle_url="${2}"
	if [[ ! -f "${git_cold_bundle_cache_file}" ]]; then                          # Download the bundle file if it does not exist.
		display_alert "Downloading Git cold bundle via HTTP" "${bundle_url}" "info" # This gonna take a while. And waste bandwidth
		run_host_command_logged wget --continue --progress=dot:giga --output-document="${bundle_file}" "${bundle_url}"
	else
		display_alert "Cold bundle file exists, using it" "${bundle_file}" "git"
	fi
}

function git_remove_cold_and_warm_bundle_remotes() {
	# Remove the cold bundle remote, otherwise it holds references that impede the shallow to actually work.
	if [[ ${has_git_cold_remote} -gt 0 ]]; then
		regular_git remote remove "${git_cold_bundle_remote_name}"
		has_git_cold_remote=0
	fi

	# Remove the warmup remote, otherwise it holds references forever.
	if [[ ${has_git_warm_remote} -gt 0 ]]; then
		regular_git remote remove "${GIT_WARM_REMOTE_NAME}"
		has_git_warm_remote=0
	fi
}

function git_handle_cold_and_warm_bundle_remotes() {

	local has_git_cold_remote=0
	local has_git_warm_remote=0
	local git_warm_remote_bundle_file git_warm_remote_bundle_cache_dir git_warm_remote_bundle_file_shallowfile
	local git_warm_remote_bundle_extra_fn=""

	# First check the warm remote bundle cache. If that exists, use that, and skip the cold bundle.
	if [[ "${do_warmup_remote}" == "yes" ]]; then
		if [[ "${GIT_WARM_REMOTE_NAME}" != "" ]] && [[ "${GIT_WARM_REMOTE_BUNDLE}" != "" ]]; then
			# Add extras to filename, for shallow by tag or revision
			if [[ "${GIT_WARM_REMOTE_SHALLOW_REVISION}" != "" ]]; then
				git_warm_remote_bundle_extra_fn="-shallow-rev-${GIT_WARM_REMOTE_SHALLOW_REVISION}"
			elif [[ "${GIT_WARM_REMOTE_SHALLOW_AT_TAG}" != "" ]]; then
				git_warm_remote_bundle_extra_fn="-shallow-tag-${GIT_WARM_REMOTE_SHALLOW_AT_TAG}"
			fi
			git_warm_remote_bundle_cache_dir="${SRC}/cache/gitbundles/warm"                                                                         # calculate the id, dir and name of local file and remote
			git_warm_remote_bundle_file="${git_warm_remote_bundle_cache_dir}/${GIT_WARM_REMOTE_BUNDLE}${git_warm_remote_bundle_extra_fn}.gitbundle" # final filename of bundle
			git_warm_remote_bundle_file_shallowfile="${git_warm_remote_bundle_file}.shallow"                                                        # it can be there's a shallow revision
			if [[ -f "${git_warm_remote_bundle_file}" ]]; then
				display_alert "Fetching from warm git bundle, wait" "${GIT_WARM_REMOTE_BUNDLE}" "info" # This is gonna take a long while...
				git_fetch_from_bundle_file "${git_warm_remote_bundle_file}" "${GIT_WARM_REMOTE_NAME}" "${git_warm_remote_bundle_file_shallowfile}"
				do_cold_bundle="no"   # Skip the cold bundle, below.
				do_warmup_remote="no" # Skip the warm bundle creation, below, too.
				has_git_warm_remote=1 # mark warm remote as added.
			else
				display_alert "Could not find warm bundle file" "${git_warm_remote_bundle_file}" "git"
			fi
		fi
	fi

	if [[ "${do_cold_bundle}" == "yes" ]]; then
		# If there's a cold bundle URL specified:
		# - if there's already a cold_bundle_xxx remote, move on.
		# - grab the bundle via http/https first, and fetch from that, into "cold_bundle_xxx" remote.
		# - do nothing else with this, it'll be used internally by git to avoid a huge fetch later.
		# - but, after this, the wanted branch will be fetched. signal has_git_cold_remote=1 for later.
		if [[ "${GIT_COLD_BUNDLE_URL}" != "" ]]; then
			local git_cold_bundle_id git_cold_bundle_cache_dir git_cold_bundle_cache_file git_cold_bundle_remote_name
			git_cold_bundle_cache_dir="${SRC}/cache/gitbundles/cold"                                  # calculate the id, dir and name of local file and remote
			git_cold_bundle_id="$(echo -n "${GIT_COLD_BUNDLE_URL}" | md5sum | awk '{print $1}')"      # md5 of the URL.
			git_cold_bundle_cache_file="${git_cold_bundle_cache_dir}/${git_cold_bundle_id}.gitbundle" # final filename of bundle
			git_cold_bundle_remote_name="cold_bundle_${git_cold_bundle_id}"                           # name of the remote that will point to bundle
			mkdir -p "${git_cold_bundle_cache_dir}"                                                   # make sure directory exists before downloading
			download_git_bundle_from_http "${git_cold_bundle_cache_file}" "${GIT_COLD_BUNDLE_URL}"
			display_alert "Fetching from cold git bundle, wait" "${git_cold_bundle_id}" "info" # This is gonna take a long while...
			git_fetch_from_bundle_file "${git_cold_bundle_cache_file}" "${git_cold_bundle_remote_name}"
			has_git_cold_remote=1 # marker for pruning logic below
		fi
	fi

	# If there's a warmup remote specified.
	# - if there's a cached warmup bundle file, add it as remote and fetch from it, and move on.
	# - add the warmup as remote, fetch from it; export it as a cached bundle for next time.
	if [[ "${do_warmup_remote}" == "yes" ]]; then
		if [[ "${GIT_WARM_REMOTE_NAME}" != "" ]] && [[ "${GIT_WARM_REMOTE_URL}" != "" ]] && [[ "${GIT_WARM_REMOTE_BRANCH}" != "" ]]; then

			display_alert "Using Warmup Remote before origin fetch" "${GIT_WARM_REMOTE_NAME} - ${GIT_WARM_REMOTE_BRANCH}" "git"
			regular_git remote add "${GIT_WARM_REMOTE_NAME}" "${GIT_WARM_REMOTE_URL}" # Add the remote to the warmup source
			has_git_warm_remote=1                                                     # mark as done. Will export the bundle!

			improved_git_fetch --no-tags "${GIT_WARM_REMOTE_NAME}" "${GIT_WARM_REMOTE_BRANCH}"          # Fetch the remote branch, but no tags
			display_alert "After warm bundle, working copy size" "$(du -h -s | awk '{print $1}')" "git" # Show size after bundle pull

			# Checkout that to a branch. We wanna have a local reference to what has been fetched.
			# @TODO: could be a param instead of FETCH_HEAD; would drop commits after that rev
			local git_warm_branch_name="warm__${GIT_WARM_REMOTE_BRANCH}"
			regular_git branch "${git_warm_branch_name}" FETCH_HEAD || true

			improved_git_fetch "${GIT_WARM_REMOTE_NAME}" "'refs/tags/${GIT_WARM_REMOTE_FETCH_TAGS}:refs/tags/${GIT_WARM_REMOTE_FETCH_TAGS}'" || true # Fetch the remote branch, but no tags
			display_alert "After warm bundle tags, working copy size" "$(du -h -s | awk '{print $1}')" "git"                                         # Show size after bundle pull

			# Lookup the tag (at the warm remote directly) to find the rev to shallow to.
			if [[ "${GIT_WARM_REMOTE_SHALLOW_AT_TAG}" != "" ]]; then
				display_alert "GIT_WARM_REMOTE_SHALLOW_AT_TAG" "${GIT_WARM_REMOTE_SHALLOW_AT_TAG}" "git"
				GIT_WARM_REMOTE_SHALLOW_AT_DATE="$(git tag --list --format="%(creatordate)" "${GIT_WARM_REMOTE_SHALLOW_AT_TAG}")"
				display_alert "GIT_WARM_REMOTE_SHALLOW_AT_TAG ${GIT_WARM_REMOTE_SHALLOW_AT_TAG} resulted in GIT_WARM_REMOTE_SHALLOW_AT_DATE" "Date: ${GIT_WARM_REMOTE_SHALLOW_AT_DATE}" "git"
			fi

			# At this stage, we might wanna make the local copy shallow and re-pack it.
			if [[ "${GIT_WARM_REMOTE_SHALLOW_AT_DATE}" != "" ]]; then
				display_alert "Making working copy shallow" "before date ${GIT_WARM_REMOTE_SHALLOW_AT_DATE}" "info"

				# 'git clone' is the only consistent, usable thing we can do to do this.
				# it does require a temporary dir, though. use one.

				local temp_git_dir="${git_work_dir}.making.shallow.temp"
				rm -rf "${temp_git_dir}"

				regular_git clone --no-checkout --progress --verbose \
					--single-branch --branch="${git_warm_branch_name}" \
					--tags --shallow-since="${GIT_WARM_REMOTE_SHALLOW_AT_DATE}" \
					"file://${git_work_dir}" "${temp_git_dir}"

				display_alert "After shallow clone, temp_git_dir" "$(du -h -s "${temp_git_dir}" | awk '{print $1}')" "git" # Show size after shallow

				# Get rid of original, replace with new. Move cwd so no warnings are produced.
				cd "${SRC}" || exit_with_error "Failed to move cwd away so we can remove" "${git_work_dir}"
				rm -rf "${git_work_dir}"
				mv -v "${temp_git_dir}" "${git_work_dir}"
				cd "${git_work_dir}" || exit_with_error "Failed to get new dir after clone" "${git_work_dir}"

				# dir switched, no more the original remotes. but origin is leftover, remove it
				regular_git remote remove origin || true
				has_git_cold_remote=0
				has_git_warm_remote=0

				display_alert "After shallow, working copy size" "$(du -h -s | awk '{print $1}')" "git" # Show size after shallow
			fi

			# Now git working copy has a precious state we might wanna preserve (export the bundle).
			if [[ "${GIT_WARM_REMOTE_BUNDLE}" != "" ]]; then
				mkdir -p "${git_warm_remote_bundle_cache_dir}"
				display_alert "Exporting warm remote bundle" "${git_warm_remote_bundle_file}" "info"
				regular_git bundle create "${git_warm_remote_bundle_file}" --all

				rm -f "${git_warm_remote_bundle_file_shallowfile}" # not shallow at first...
				if [[ -f ".git/shallow" ]]; then
					display_alert "Exported bundle is shallow" "Will copy to ${git_warm_remote_bundle_file_shallowfile}" "git"
					cp -p ".git/shallow" "${git_warm_remote_bundle_file_shallowfile}"
				fi

			fi
		fi
	fi

	# Make sure to remove the cold and warm bundle remote, otherwise it holds references for no good reason.
	git_remove_cold_and_warm_bundle_remotes
}
