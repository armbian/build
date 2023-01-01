#!/usr/bin/env bash
#
# This function retries Git operations to avoid failure in case remote is borked
# If the git team needs to call a remote server, use this function.
#
improved_git() {

	local realgit=$(command -v git)
	local retries=3
	local delay=10
	local count=1
	while [ $count -lt $retries ]; do
		$realgit "$@"
		if [[ $? -eq 0 || -f .git/index.lock ]]; then
			retries=0
			break
		fi
		let count=$count+1
		sleep $delay
	done

}

clean_up_git() {
	local target_dir=$1

	# Files that are not tracked by git and were added
	# when the patch was applied must be removed.
	git -C $target_dir clean -qdf

	# Return the files that are tracked by git to the initial state.
	git -C $target_dir checkout -qf HEAD
}

# used : waiter_local_git arg1='value' arg2:'value'
#		 waiter_local_git \
#			url='https://github.com/megous/linux' \
#			name='megous' \
#			dir='linux-mainline/5.14' \
#			branch='orange-pi-5.14' \
#			obj=<tag|commit> or tag:$tag ...
# An optional parameter for switching to a git object such as a tag, commit,
# or a specific branch. The object must exist in the local repository.
# This optional parameter takes precedence. If it is specified, then
# the commit state corresponding to the specified git object will be extracted
# to the working directory. Otherwise, the commit corresponding to the top of
# the branch will be extracted.
# The settings for the kernel variables of the original kernel
# VAR_SHALLOW_ORIGINAL=var_origin_kernel must be in the main script
# before calling the function
waiter_local_git() {
	for arg in $@; do

		case $arg in
			url=* | https://* | git://*)
				eval "local url=${arg/url=/}"
				;;
			dir=* | /*/*/*)
				eval "local dir=${arg/dir=/}"
				;;
			*=* | *:*)
				eval "local ${arg/:/=}"
				;;
		esac

	done

	# Required variables cannot be empty.
	for var in url name dir branch; do
		[ "${var#*=}" == "" ] && exit_with_error "Error in configuration"
	done

	local reachability

	# The 'offline' variable must always be set to 'true' or 'false'
	if [ "$OFFLINE_WORK" == "yes" ]; then
		local offline=true
	else
		local offline=false
	fi

	local work_dir="$(realpath ${SRC}/cache/sources)/$dir"
	mkdir -p $work_dir
	cd $work_dir || exit_with_error

	display_alert "Checking git sources" "$dir $url$name/$branch" "info"

	if [ "$(git rev-parse --git-dir 2> /dev/null)" != ".git" ]; then
		git init -q .

		# Run in the sub shell to avoid mixing environment variables.
		if [ -n "$VAR_SHALLOW_ORIGINAL" ]; then
			(
				$VAR_SHALLOW_ORIGINAL

				display_alert "Add original git sources" "$dir $name/$branch" "info"
				if [ "$(improved_git ls-remote -h $url $branch |
					awk -F'/' '{if (NR == 1) print $NF}')" != "$branch" ]; then
					display_alert "Bad $branch for $url in $VAR_SHALLOW_ORIGINAL"
					exit 177
				fi

				git remote add -t $branch $name $url

				# Handle an exception if the initial tag is the top of the branch
				# As v5.16 == HEAD
				if [ "${start_tag}.1" == "$(improved_git ls-remote -t $url ${start_tag}.1 |
					awk -F'/' '{ print $NF }')" ]; then
					improved_git fetch --shallow-exclude=$start_tag $name
				else
					improved_git fetch --depth 1 $name
				fi
				improved_git fetch --deepen=1 $name
				# For a shallow clone, this works quickly and saves space.
				git gc
			)

			[ "$?" == "177" ] && exit
		fi
	fi

	files_for_clean="$(git status -s | wc -l)"
	if [ "$files_for_clean" != "0" ]; then
		display_alert " Cleaning .... " "$files_for_clean files"
		clean_up_git $work_dir
	fi

	if [ "$name" != "$(git remote show | grep $name)" ]; then
		git remote add -t $branch $name $url
	fi

	if ! $offline; then
		for t_name in $(git remote show); do
			improved_git fetch $t_name
		done
	fi

	# When switching, we use the concept of only "detached branch". Therefore,
	# we extract the hash from the tag, the branch name, or from the hash itself.
	# This serves as a check of the reachability of the extraction.
	# We do not use variables that characterize the current state of the git,
	# such as `HEAD` and `FETCH_HEAD`.
	reachability=false
	for var in obj tag commit branch; do
		eval pval=\$$var

		if [ -n "$pval" ] && [ "$pval" != *HEAD ]; then
			case $var in
				obj | tag | commit) obj=$pval ;;
				branch) obj=${name}/$branch ;;
			esac

			if t_hash=$(git rev-parse $obj 2> /dev/null); then
				reachability=true
				break
			else
				display_alert "Variable $var=$obj unreachable for extraction"
			fi
		fi
	done

	if $reachability && [ "$t_hash" != "$(git rev-parse @ 2> /dev/null)" ]; then
		# Switch "detached branch" as hash
		display_alert "Switch $obj = $t_hash"
		git checkout -qf $t_hash
	else
		# the working directory corresponds to the target commit,
		# nothing needs to be done
		display_alert "Up to date"
	fi
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
	local url=$1
	local dir=$2
	local ref=$3
	local ref_subdir=$4

	# Set GitHub mirror before anything else touches $url
	url=${url//'https://github.com/'/$GITHUB_SOURCE'/'}

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

	display_alert "Checking git sources" "$dir $ref_name" "info"

	# get default remote branch name without cloning
	# local ref_name=$(git ls-remote --symref $url HEAD | grep -o 'refs/heads/\S*' | sed 's%refs/heads/%%')
	# for git:// protocol comparing hashes of "git ls-remote -h $url" and "git ls-remote --symref $url HEAD" is needed

	if [[ $ref_subdir == yes ]]; then
		local workdir=$dir/$ref_name
	else
		local workdir=$dir
	fi

	mkdir -p "${SRC}/cache/sources/${workdir}" 2> /dev/null ||
		exit_with_error "No path or no write permission" "${SRC}/cache/sources/${workdir}"

	cd "${SRC}/cache/sources/${workdir}" || exit

	# check if existing remote URL for the repo or branch does not match current one
	# may not be supported by older git versions
	#  Check the folder as a git repository.
	#  Then the target URL matches the local URL.

	if [[ "$(git rev-parse --git-dir 2> /dev/null)" == ".git" &&
	"$url" != *"$(git remote get-url origin | sed 's/^.*@//' | sed 's/^.*\/\///' 2> /dev/null)" ]]; then
		display_alert "Remote URL does not match, removing existing local copy"
		rm -rf .git ./*
	fi

	if [[ "$(git rev-parse --git-dir 2> /dev/null)" != ".git" ]]; then
		display_alert "Creating local copy"
		git init -q .
		git remote add origin "${url}"
		# Here you need to upload from a new address
		offline=false
	fi

	local changed=false

	# when we work offline we simply return the sources to their original state
	if ! $offline; then
		local local_hash
		local_hash=$(git rev-parse @ 2> /dev/null)

		case $ref_type in
			branch)
				# TODO: grep refs/heads/$name
				local remote_hash
				remote_hash=$(improved_git ls-remote -h "${url}" "$ref_name" | head -1 | cut -f1)
				[[ -z $local_hash || "${local_hash}" != "${remote_hash}" ]] && changed=true
				;;

			tag)
				local remote_hash
				remote_hash=$(improved_git ls-remote -t "${url}" "$ref_name" | cut -f1)
				if [[ -z $local_hash || "${local_hash}" != "${remote_hash}" ]]; then
					remote_hash=$(improved_git ls-remote -t "${url}" "$ref_name^{}" | cut -f1)
					[[ -z $remote_hash || "${local_hash}" != "${remote_hash}" ]] && changed=true
				fi
				;;

			head)
				local remote_hash
				remote_hash=$(improved_git ls-remote "${url}" HEAD | cut -f1)
				[[ -z $local_hash || "${local_hash}" != "${remote_hash}" ]] && changed=true
				;;

			commit)
				[[ -z $local_hash || $local_hash == "@" ]] && changed=true
				;;
		esac

	fi # offline

	if [[ $changed == true ]]; then

		# remote was updated, fetch and check out updates
		display_alert "Fetching updates"
		case $ref_type in
			branch) improved_git fetch --depth 200 origin "${ref_name}" ;;
			tag) improved_git fetch --depth 200 origin tags/"${ref_name}" ;;
			head) improved_git fetch --depth 200 origin HEAD ;;
		esac

		# commit type needs support for older git servers that doesn't support fetching id directly
		if [[ $ref_type == commit ]]; then

			improved_git fetch --depth 200 origin "${ref_name}"

			# cover old type
			if [[ $? -ne 0 ]]; then

				display_alert "Commit checkout not supported on this repository. Doing full clone." "" "wrn"
				improved_git pull
				git checkout -fq "${ref_name}"
				display_alert "Checkout out to" "$(git --no-pager log -2 --pretty=format:"$ad%s [%an]" | head -1)" "info"

			else

				display_alert "Checking out"
				git checkout -f -q FETCH_HEAD
				git clean -qdf

			fi
		else

			display_alert "Checking out"
			git checkout -f -q FETCH_HEAD
			git clean -qdf

		fi
	elif [[ -n $(git status -uno --porcelain --ignore-submodules=all) ]]; then
		# working directory is not clean
		display_alert " Cleaning .... " "$(git status -s | wc -l) files"

		# Return the files that are tracked by git to the initial state.
		git checkout -f -q HEAD

		# Files that are not tracked by git and were added
		# when the patch was applied must be removed.
		git clean -qdf
	else
		# working directory is clean, nothing to do
		display_alert "Up to date"
	fi

	if [[ -f .gitmodules ]]; then
		display_alert "Updating submodules" "" "ext"
		# FML: http://stackoverflow.com/a/17692710
		for i in $(git config -f .gitmodules --get-regexp path | awk '{ print $2 }'); do
			cd "${SRC}/cache/sources/${workdir}" || exit
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
