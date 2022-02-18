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
	display_alert "fetch_from_repo" "$*" "debug"
	local url=$1
	local dir=$2
	local ref=$3
	local ref_subdir=$4
	local git_work_dir

	# Set GitHub mirror before anything else touches $url
	url=${url//'https://github.com/'/$GITHUB_SOURCE}

	# The 'offline' variable must always be set to 'true' or 'false'
	if [ "$OFFLINE_WORK" == "yes" ]; then
		local offline=true
	else
		local offline=false
	fi

	[[ -z $ref || ($ref != tag:* && $ref != branch:* && $ref != head && $ref != commit:*) ]] && exit_with_error "Error in configuration"
	local ref_type=${ref%%:*}
	if [[ $ref_type == head ]]; then
		local ref_name=HEAD
	else
		local ref_name=${ref##*:}
	fi

	display_alert "Getting sources from Git" "$dir $ref_name" "info"

	local workdir=$dir
	if [[ $ref_subdir == yes ]]; then
		workdir=$dir/$ref_name
	fi

	git_work_dir="${SRC}/cache/sources/${workdir}"

	mkdir -p "${git_work_dir}" || exit_with_error "No path or no write permission" "${git_work_dir}"

	cd "${git_work_dir}" || exit

	display_alert "Git working dir" "${git_work_dir}" "debug"


	# "Sanity check" since we only support one "origin"
	if [[ "$(git rev-parse --git-dir)" == ".git" && "$url" != *"$(git remote get-url origin | sed 's/^.*@//' | sed 's/^.*\/\///')" ]]; then
		exit_with_error "Remote URL does not match. Stopping!" "${git_work_dir} $dir $ref_name" "warn"
	fi

	if [[ "$(git rev-parse --git-dir)" != ".git" ]]; then
		display_alert "Creating local copy" "$dir $ref_name"
		improved_git init -q --initial-branch="armbian_unused_initial_branch" .
		improved_git remote add origin "${url}"
		offline=false # Force only, we'll need to fetch.
	fi

	local changed=false

	# when we work offline we simply return the sources to their original state
	if ! $offline; then
		local local_hash
		local_hash=$(git rev-parse @ 2> /dev/null || true) # Don't fail nor output anything if failure

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

		display_alert "Git local_hash vs remote_hash" "${local_hash} vs ${remote_hash}" "debug"

	fi # offline

	if [[ $changed == true ]]; then

		# If there's a cold bundle URL specified:
		# - if there's already a cold_bundle_xxx remote, move on.
		# - grab the bundle via http/https first, and fetch from that, into "cold_bundle_xxx" remote.
		# - do nothing else with this, it'll be used internally by git to avoid a huge fetch later.
		# - but, after this, the wanted branch will be fetched. signal has_fetched_from_bundle=1 for later.
		local has_fetched_from_bundle=0
		if [[ "${GIT_COLD_BUNDLE_URL}" != "" ]]; then
			local git_cold_bundle_id git_cold_bundle_cache_dir git_cold_bundle_cache_file git_cold_bundle_remote_id git_cold_bundle_fetched_marker_file
			# calculate the id, dir and name of local file and remote
			git_cold_bundle_cache_dir="${SRC}/cache/gitbundles"
			mkdir -p "${git_cold_bundle_cache_dir}"
			git_cold_bundle_id="$(echo -n "${GIT_COLD_BUNDLE_URL}" | md5sum | awk '{print $1}')" # md5 of the URL.
			git_cold_bundle_cache_file="${git_cold_bundle_cache_dir}/${git_cold_bundle_id}.gitbundle"
			git_cold_bundle_remote_id="cold_bundle_${git_cold_bundle_id}"
			git_cold_bundle_fetched_marker_file=".git/fetched-from-bundle-${git_cold_bundle_id}"

			display_alert "There's a " "${GIT_COLD_BUNDLE_URL} -- ${git_cold_bundle_id} -- file: ${git_cold_bundle_cache_file}" "debug"

			# Don't do if already done before for this bundle.
			if [[ ! -f "${git_cold_bundle_fetched_marker_file}" ]]; then

				# Download the bundle file if it does not exist.
				if [[ ! -f "${git_cold_bundle_cache_file}" ]]; then
					display_alert "Downloading cold bundle from remote server" "${GIT_COLD_BUNDLE_URL}" "debug"
					run_host_command_logged wget --continue --output-document="${git_cold_bundle_cache_file}" "${GIT_COLD_BUNDLE_URL}"
				else
					display_alert "Cold bundle file exists, using it" "${git_cold_bundle_cache_file}" "debug"
				fi

				# Make sure bundle is valid.
				improved_git bundle verify "${git_cold_bundle_cache_file}"

				# Get a list of remotes in the repo; add remote to bundle if it does not exist, and fetch from it.
				# This should be done only once per workdir, so I use a marker file to denote completion.
				if git remote get-url "${git_cold_bundle_remote_id}" 2> /dev/null; then
					display_alert "Git already has bundle remote" "incomplete fetch? ${git_cold_bundle_id}" "debug"
				else
					improved_git remote add "${git_cold_bundle_remote_id}" "${git_cold_bundle_cache_file}" # Add the remote pointing to the cold bundle file
				fi

				display_alert "Fetching from git bundle, wait" "${git_cold_bundle_id}" "info"
				improved_git_fetch --tags "${git_cold_bundle_remote_id}"                                           # Fetch it! and all its tags, too.
				has_fetched_from_bundle=1                                                                          # marker for pruning logic below
				echo "${remote_hash}" > "${git_cold_bundle_fetched_marker_file}"                                   # marker for future invocation
				display_alert "Bundle fetch completed, working copy size" "$(du -h -s | awk '{print $1}')" "debug" # Show size after bundle pull

			fi
		fi

		# @TODO: If there's a warmup remote specified: (for u-boot and others)
		# - if there's already a warmup remote, move on.
		# - if there's a cached warmup bundle file, add it as remote and fetch from it, and move on.
		# - add the warmup as remote, fetch from it; export it as a cached bundle for next time.

		# remote was updated, fetch and check out updates, but not tags; tags pull their respective commits too, making it a huge fetch.
		display_alert "Fetching updates from origin" "$dir $ref_name"
		case $ref_type in
			branch | commit) improved_git_fetch --tags origin "${ref_name}" ;;
			tag) improved_git_fetch --tags origin tags/"${ref_name}" ;;
			head) improved_git_fetch --tags origin HEAD ;;
		esac
		display_alert "Origin fetch completed, working copy size" "$(du -h -s | awk '{print $1}')" "debug" # Show size again

		display_alert "Checking out" "$dir $ref_name"
		improved_git checkout -f -q FETCH_HEAD
		improved_git clean -q -d -f
		display_alert "After checkout, working copy size" "$(du -h -s | awk '{print $1}')" "debug" # Show size after bundle pull

		#if [[ $has_fetched_from_bundle -gt 0 ]]; then
		#	display_alert "Pre-pruning, working copy size" "$(du -h -s | awk '{print $1}')" "debug" # Show size after bundle pull
		#	echo -n "${remote_hash}" > .git/shallow                                                 # commit to keep for shallowing, can be something else. for now is full prune.
		#	improved_git remote remove "${git_cold_bundle_remote_id}"
		#	improved_git reflog expire --expire=0 --all
		#	improved_git gc --prune=all
		#fi

	elif [[ -n $(git status -uno --porcelain --ignore-submodules=all) ]]; then # if not changed, but dirty...
		display_alert "Cleaning git dir" "$(git status -s | wc -l) files"         # working directory is not clean, show it
		improved_git checkout -f -q HEAD                                          # Return the files that are tracked by git to the initial state.
		improved_git clean -q -d -f                                               # Files that are not tracked by git and were added when the patch was applied must be removed.
	else                                                                       # not changed, not dirty.
		display_alert "Up to date" "$dir $ref_name at revision ${local_hash}"     # working directory is clean, nothing to do
	fi

	display_alert "Final working copy size" "$(du -h -s | awk '{print $1}')" "debug"

	if [[ -f .gitmodules ]]; then
		display_alert "Updating submodules" "" "ext"
		# FML: http://stackoverflow.com/a/17692710
		for i in $(git config -f .gitmodules --get-regexp path | awk '{ print $2 }'); do
			cd "${git_work_dir}" || exit
			local surl sref
			surl=$(git config -f .gitmodules --get "submodule.$i.url")
			sref=$(git config -f .gitmodules --get "submodule.$i.branch")
			if [[ -n $sref ]]; then
				sref="branch:$sref"
			else
				sref="head"
			fi
			fetch_from_repo "$surl" "$workdir/$i" "$sref"
		done
	fi
}
