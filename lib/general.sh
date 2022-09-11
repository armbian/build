#!/bin/bash
#
# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

# This file is a part of the Armbian build script
# https://github.com/armbian/build/

# Functions:
# cleaning
# exit_with_error
# get_package_list_hash
# create_sources_list
# clean_up_git
# waiter_local_git
# fetch_from_repo
# improved_git
# display_alert
# fingerprint_image
# distro_menu
# addtorepo
# repo-remove-old-packages
# wait_for_package_manager
# install_pkg_deb
# prepare_host_basic
# prepare_host
# get_urls
# download_and_verify
# show_developer_warning
# show_checklist_variables


# cleaning <target>
#
# target: what to clean
# "make" - "make clean" for selected kernel and u-boot
# "debs" - delete output/debs for board&branch
# "ubootdebs" - delete output/debs for uboot&board&branch
# "alldebs" - delete output/debs
# "cache" - delete output/cache
# "oldcache" - remove old output/cache
# "images" - delete output/images
# "sources" - delete output/sources
#

cleaning()
{
	case $1 in
		debs) # delete ${DEB_STORAGE} for current branch and family
		if [[ -d "${DEB_STORAGE}" ]]; then
			display_alert "Cleaning ${DEB_STORAGE} for" "$BOARD $BRANCH" "info"
			# easier than dealing with variable expansion and escaping dashes in file names
			find "${DEB_STORAGE}" -name "${CHOSEN_UBOOT}_*.deb" -delete
			find "${DEB_STORAGE}" \( -name "${CHOSEN_KERNEL}_*.deb" -o \
				-name "armbian-*.deb" -o \
				-name "${CHOSEN_KERNEL/image/dtb}_*.deb" -o \
				-name "${CHOSEN_KERNEL/image/headers}_*.deb" -o \
				-name "${CHOSEN_KERNEL/image/source}_*.deb" -o \
				-name "${CHOSEN_KERNEL/image/firmware-image}_*.deb" \) -delete
			[[ -n $RELEASE ]] && rm -f "${DEB_STORAGE}/${RELEASE}/${CHOSEN_ROOTFS}"_*.deb
			[[ -n $RELEASE ]] && rm -f "${DEB_STORAGE}/${RELEASE}/armbian-desktop-${RELEASE}"_*.deb
		fi
		;;

		ubootdebs) # delete ${DEB_STORAGE} for uboot, current branch and family
		if [[ -d "${DEB_STORAGE}" ]]; then
			display_alert "Cleaning ${DEB_STORAGE} for u-boot" "$BOARD $BRANCH" "info"
			# easier than dealing with variable expansion and escaping dashes in file names
			find "${DEB_STORAGE}" -name "${CHOSEN_UBOOT}_*.deb" -delete
		fi
		;;

		extras) # delete ${DEB_STORAGE}/extra/$RELEASE for all architectures
		if [[ -n $RELEASE && -d ${DEB_STORAGE}/extra/$RELEASE ]]; then
			display_alert "Cleaning ${DEB_STORAGE}/extra for" "$RELEASE" "info"
			rm -rf "${DEB_STORAGE}/extra/${RELEASE}"
		fi
		;;

		alldebs) # delete output/debs
		[[ -d "${DEB_STORAGE}" ]] && display_alert "Cleaning" "${DEB_STORAGE}" "info" && rm -rf "${DEB_STORAGE}"/*
		;;

		cache) # delete output/cache
		[[ -d "${SRC}"/cache/rootfs ]] && display_alert "Cleaning" "rootfs cache (all)" "info" && find "${SRC}"/cache/rootfs -type f -delete
		;;

		images) # delete output/images
		[[ -d "${DEST}"/images ]] && display_alert "Cleaning" "output/images" "info" && rm -rf "${DEST}"/images/*
		;;

		sources) # delete output/sources and output/buildpkg
		[[ -d "${SRC}"/cache/sources ]] && display_alert "Cleaning" "sources" "info" && rm -rf "${SRC}"/cache/sources/* "${DEST}"/buildpkg/*
		;;

		oldcache) # remove old `cache/rootfs` except for the newest 8 files
		if [[ -d "${SRC}"/cache/rootfs && $(ls -1 "${SRC}"/cache/rootfs/*.zst* 2> /dev/null | wc -l) -gt "${ROOTFS_CACHE_MAX}" ]]; then
			display_alert "Cleaning" "rootfs cache (old)" "info"
			(cd "${SRC}"/cache/rootfs; ls -t *.lz4 | sed -e "1,${ROOTFS_CACHE_MAX}d" | xargs -d '\n' rm -f)
			# Remove signatures if they are present. We use them for internal purpose
			(cd "${SRC}"/cache/rootfs; ls -t *.asc | sed -e "1,${ROOTFS_CACHE_MAX}d" | xargs -d '\n' rm -f)
		fi
		;;
	esac
}

# exit_with_error <message> <highlight>
#
# a way to terminate build process
# with verbose error message
#

exit_with_error()
{
	local _file
	local _line=${BASH_LINENO[0]}
	local _function=${FUNCNAME[1]}
	local _description=$1
	local _highlight=$2
	_file=$(basename "${BASH_SOURCE[1]}")
	local stacktrace="$(get_extension_hook_stracktrace "${BASH_SOURCE[*]}" "${BASH_LINENO[*]}")"

	display_alert "ERROR in function $_function" "$stacktrace" "err"
	display_alert "$_description" "$_highlight" "err"
	display_alert "Process terminated" "" "info"

	if [[ "${ERROR_DEBUG_SHELL}" == "yes" ]]; then
		display_alert "MOUNT" "${MOUNT}" "err"
		display_alert "SDCARD" "${SDCARD}" "err"
		display_alert "Here's a shell." "debug it" "err"
		bash < /dev/tty || true
	fi

	# TODO: execute run_after_build here?
	overlayfs_wrapper "cleanup"
	# unlock loop device access in case of starvation
	exec {FD}>/var/lock/armbian-debootstrap-losetup
	flock -u "${FD}"

	exit 255
}

# get_package_list_hash
#
# returns md5 hash for current package list and rootfs cache version

get_package_list_hash()
{
	local package_arr exclude_arr
	local list_content
	read -ra package_arr <<< "${DEBOOTSTRAP_LIST} ${PACKAGE_LIST}"
	read -ra exclude_arr <<< "${PACKAGE_LIST_EXCLUDE}"
	(
		printf "%s\n" "${package_arr[@]}"
		printf -- "-%s\n" "${exclude_arr[@]}"
	) | sort -u | md5sum | cut -d' ' -f 1
}

# create_sources_list <release> <basedir>
#
# <release>: bullseye|focal|jammy|sid
# <basedir>: path to root directory
#
create_sources_list()
{
	local release=$1
	local basedir=$2
	[[ -z $basedir ]] && exit_with_error "No basedir passed to create_sources_list"

	case $release in
	buster)
	cat <<-EOF > "${basedir}"/etc/apt/sources.list
	deb http://${DEBIAN_MIRROR} $release main contrib non-free
	#deb-src http://${DEBIAN_MIRROR} $release main contrib non-free

	deb http://${DEBIAN_MIRROR} ${release}-updates main contrib non-free
	#deb-src http://${DEBIAN_MIRROR} ${release}-updates main contrib non-free

	deb http://${DEBIAN_MIRROR} ${release}-backports main contrib non-free
	#deb-src http://${DEBIAN_MIRROR} ${release}-backports main contrib non-free

	deb http://${DEBIAN_SECURTY} ${release}/updates main contrib non-free
	#deb-src http://${DEBIAN_SECURTY} ${release}/updates main contrib non-free
	EOF
	;;

	bullseye|bookworm|trixie)
	cat <<-EOF > "${basedir}"/etc/apt/sources.list
	deb http://${DEBIAN_MIRROR} $release main contrib non-free
	#deb-src http://${DEBIAN_MIRROR} $release main contrib non-free

	deb http://${DEBIAN_MIRROR} ${release}-updates main contrib non-free
	#deb-src http://${DEBIAN_MIRROR} ${release}-updates main contrib non-free

	deb http://${DEBIAN_MIRROR} ${release}-backports main contrib non-free
	#deb-src http://${DEBIAN_MIRROR} ${release}-backports main contrib non-free

	deb http://${DEBIAN_SECURTY} ${release}-security main contrib non-free
	#deb-src http://${DEBIAN_SECURTY} ${release}-security main contrib non-free
	EOF
	;;

	sid) # sid is permanent unstable development and has no such thing as updates or security
	cat <<-EOF > "${basedir}"/etc/apt/sources.list
	deb http://${DEBIAN_MIRROR} $release main contrib non-free
	#deb-src http://${DEBIAN_MIRROR} $release main contrib non-free
	EOF
	;;

	focal|jammy)
	cat <<-EOF > "${basedir}"/etc/apt/sources.list
	deb http://${UBUNTU_MIRROR} $release main restricted universe multiverse
	#deb-src http://${UBUNTU_MIRROR} $release main restricted universe multiverse

	deb http://${UBUNTU_MIRROR} ${release}-security main restricted universe multiverse
	#deb-src http://${UBUNTU_MIRROR} ${release}-security main restricted universe multiverse

	deb http://${UBUNTU_MIRROR} ${release}-updates main restricted universe multiverse
	#deb-src http://${UBUNTU_MIRROR} ${release}-updates main restricted universe multiverse

	deb http://${UBUNTU_MIRROR} ${release}-backports main restricted universe multiverse
	#deb-src http://${UBUNTU_MIRROR} ${release}-backports main restricted universe multiverse
	EOF
	;;
	esac

	display_alert "Adding Armbian repository and authentication key" "/etc/apt/sources.list.d/armbian.list" "info"

	# apt-key add is getting deprecated
	APT_VERSION=$(chroot "${basedir}" /bin/bash -c "apt --version | cut -d\" \" -f2")
	if linux-version compare "${APT_VERSION}" ge 2.4.1; then
		# add armbian key
		mkdir -p "${basedir}"/usr/share/keyrings
		# change to binary form
		gpg --dearmor < "${SRC}"/config/armbian.key > "${basedir}"/usr/share/keyrings/armbian.gpg
		SIGNED_BY="[signed-by=/usr/share/keyrings/armbian.gpg] "
	else
		# use old method for compatibility reasons
		cp "${SRC}"/config/armbian.key "${basedir}"
		chroot "${basedir}" /bin/bash -c "cat armbian.key | apt-key add - > /dev/null 2>&1"
	fi

	# stage: add armbian repository and install key
	if [[ $DOWNLOAD_MIRROR == "china" ]]; then
		echo "deb ${SIGNED_BY}https://mirrors.tuna.tsinghua.edu.cn/armbian $RELEASE main ${RELEASE}-utils ${RELEASE}-desktop" > "${basedir}"/etc/apt/sources.list.d/armbian.list
	elif [[ $DOWNLOAD_MIRROR == "bfsu" ]]; then
	    echo "deb ${SIGNED_BY}http://mirrors.bfsu.edu.cn/armbian $RELEASE main ${RELEASE}-utils ${RELEASE}-desktop" > "${basedir}"/etc/apt/sources.list.d/armbian.list
	else
		echo "deb ${SIGNED_BY}http://"$([[ $BETA == yes ]] && echo "beta" || echo "apt" )".armbian.com $RELEASE main ${RELEASE}-utils ${RELEASE}-desktop" > "${basedir}"/etc/apt/sources.list.d/armbian.list
	fi

	# replace local package server if defined. Suitable for development
	[[ -n $LOCAL_MIRROR ]] && echo "deb ${SIGNED_BY}http://$LOCAL_MIRROR $RELEASE main ${RELEASE}-utils ${RELEASE}-desktop" > "${basedir}"/etc/apt/sources.list.d/armbian.list

	# disable repo if SKIP_ARMBIAN_REPO=yes
	if [[ "${SKIP_ARMBIAN_REPO}" == "yes" ]]; then
		display_alert "Disabling armbian repo" "${ARCH}-${RELEASE}" "wrn"
		mv "${SDCARD}"/etc/apt/sources.list.d/armbian.list "${SDCARD}"/etc/apt/sources.list.d/armbian.list.disabled
	fi

}


#
# This function retries Git operations to avoid failure in case remote is borked
# If the git team needs to call a remote server, use this function.
#
improved_git()
{

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

clean_up_git ()
{
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
waiter_local_git ()
{
	for arg in $@;do

		case $arg in
			url=*|https://*|git://*)	eval "local url=${arg/url=/}"
				;;
			dir=*|/*/*/*)	eval "local dir=${arg/dir=/}"
				;;
			*=*|*:*)	eval "local ${arg/:/=}"
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

	if [ "$(git rev-parse --git-dir 2>/dev/null)" != ".git" ]; then
		git init -q .

		# Run in the sub shell to avoid mixing environment variables.
		if [ -n "$VAR_SHALLOW_ORIGINAL" ]; then
			(
			$VAR_SHALLOW_ORIGINAL

			display_alert "Add original git sources" "$dir $name/$branch" "info"
			if [ "$(improved_git ls-remote -h $url $branch | \
				awk -F'/' '{if (NR == 1) print $NF}')" != "$branch" ];then
				display_alert "Bad $branch for $url in $VAR_SHALLOW_ORIGINAL"
				exit 177
			fi

			git remote add -t $branch $name $url

			# Handle an exception if the initial tag is the top of the branch
			# As v5.16 == HEAD
			if [ "${start_tag}.1" == "$(improved_git ls-remote -t $url ${start_tag}.1 | \
					awk -F'/' '{ print $NF }')" ]
			then
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
	if [ "$files_for_clean" != "0" ];then
		display_alert " Cleaning .... " "$files_for_clean files"
		clean_up_git $work_dir
	fi

	if [ "$name" != "$(git remote show | grep $name)" ];then
		git remote add -t $branch $name $url
	fi

	if ! $offline; then
		for t_name in $(git remote show);do
			improved_git fetch $t_name
		done
	fi

	# When switching, we use the concept of only "detached branch". Therefore,
	# we extract the hash from the tag, the branch name, or from the hash itself.
	# This serves as a check of the reachability of the extraction.
	# We do not use variables that characterize the current state of the git,
	# such as `HEAD` and `FETCH_HEAD`.
	reachability=false
	for var in obj tag commit branch;do
		eval pval=\$$var

		if [ -n "$pval" ] && [ "$pval" != *HEAD ]; then
			case $var in
				obj|tag|commit) obj=$pval ;;
				branch) obj=${name}/$branch ;;
			esac

			if  t_hash=$(git rev-parse $obj 2>/dev/null);then
				reachability=true
				break
			else
				display_alert "Variable $var=$obj unreachable for extraction"
			fi
		fi
	done

	if $reachability && [ "$t_hash" != "$(git rev-parse @ 2>/dev/null)" ];then
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
fetch_from_repo()
{
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

	[[ -z $ref || ( $ref != tag:* && $ref != branch:* && $ref != head && $ref != commit:* ) ]] && exit_with_error "Error in configuration"
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

	mkdir -p "${SRC}/cache/sources/${workdir}" 2>/dev/null || \
		exit_with_error "No path or no write permission" "${SRC}/cache/sources/${workdir}"

	cd "${SRC}/cache/sources/${workdir}" || exit

	# check if existing remote URL for the repo or branch does not match current one
	# may not be supported by older git versions
	#  Check the folder as a git repository.
	#  Then the target URL matches the local URL.

	if [[ "$(git rev-parse --git-dir 2>/dev/null)" == ".git" && \
		  "$url" != *"$(git remote get-url origin | sed 's/^.*@//' | sed 's/^.*\/\///' 2>/dev/null)" ]]; then
		display_alert "Remote URL does not match, removing existing local copy"
		rm -rf .git ./*
	fi

	if [[ "$(git rev-parse --git-dir 2>/dev/null)" != ".git" ]]; then
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
		local_hash=$(git rev-parse @ 2>/dev/null)

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
} #############################################################################

#--------------------------------------------------------------------------------------------------------------------------------
# Let's have unique way of displaying alerts
#--------------------------------------------------------------------------------------------------------------------------------
display_alert()
{
	# log function parameters to install.log
	[[ -n "${DEST}" ]] && echo "Displaying message: $@" >> "${DEST}"/${LOG_SUBPATH}/output.log

	local tmp=""
	[[ -n $2 ]] && tmp="[\e[0;33m $2 \x1B[0m]"

	case $3 in
		err)
		echo -e "[\e[0;31m error \x1B[0m] $1 $tmp"
		;;

		wrn)
		echo -e "[\e[0;35m warn \x1B[0m] $1 $tmp"
		;;

		ext)
		echo -e "[\e[0;32m o.k. \x1B[0m] \e[1;32m$1\x1B[0m $tmp"
		;;

		info)
		echo -e "[\e[0;32m o.k. \x1B[0m] $1 $tmp"
		;;

		*)
		echo -e "[\e[0;32m .... \x1B[0m] $1 $tmp"
		;;
	esac
}

#--------------------------------------------------------------------------------------------------------------------------------
# fingerprint_image <out_txt_file> [image_filename]
# Saving build summary to the image
#--------------------------------------------------------------------------------------------------------------------------------
fingerprint_image()
{
	cat <<-EOF > "${1}"
	--------------------------------------------------------------------------------
	Title:			${VENDOR} $REVISION ${BOARD^} $BRANCH
	Kernel:			Linux $VER
	Build date:		$(date +'%d.%m.%Y')
	Builder rev:		$BUILD_REPOSITORY_COMMIT
	Maintainer:		$MAINTAINER <$MAINTAINERMAIL>
	Authors:		https://www.armbian.com/authors
	Sources: 		https://github.com/armbian/
	Support: 		https://forum.armbian.com/
	Changelog: 		https://www.armbian.com/logbook/
	Documantation:		https://docs.armbian.com/
	EOF

	if [ -n "$2" ]; then
		cat <<-EOF >> "${1}"
		--------------------------------------------------------------------------------
		Partitioning configuration: $IMAGE_PARTITION_TABLE offset: $OFFSET
		Boot partition type: ${BOOTFS_TYPE:-(none)} ${BOOTSIZE:+"(${BOOTSIZE} MB)"}
		Root partition type: $ROOTFS_TYPE ${FIXED_IMAGE_SIZE:+"(${FIXED_IMAGE_SIZE} MB)"}

		CPU configuration: $CPUMIN - $CPUMAX with $GOVERNOR
		--------------------------------------------------------------------------------
		Verify GPG signature:
		gpg --verify $2.img.xz.asc

		Verify image file integrity:
		sha256sum --check $2.img.xz.sha

		Prepare SD card (four methods):
		xzcat $2.img.xz | pv | dd of=/dev/mmcblkX bs=1M
		dd if=$2.img of=/dev/mmcblkX bs=1M
		balena-etcher $2.img.xz -d /dev/mmcblkX
		balena-etcher $2.img -d /dev/mmcblkX
		EOF
	fi

	cat <<-EOF >> "${1}"
	--------------------------------------------------------------------------------
	$(cat "${SRC}"/LICENSE)
	--------------------------------------------------------------------------------
	EOF
}


#--------------------------------------------------------------------------------------------------------------------------------
# Create kernel boot logo from packages/blobs/splash/logo.png and packages/blobs/splash/spinner.gif (animated)
# and place to the file /lib/firmware/bootsplash
#--------------------------------------------------------------------------------------------------------------------------------
function boot_logo ()
{
display_alert "Building kernel splash logo" "$RELEASE" "info"

	LOGO=${SRC}/packages/blobs/splash/logo.png
	LOGO_WIDTH=$(identify $LOGO | cut -d " " -f 3 | cut -d x -f 1)
	LOGO_HEIGHT=$(identify $LOGO | cut -d " " -f 3 | cut -d x -f 2)
	THROBBER=${SRC}/packages/blobs/splash/spinner.gif
	THROBBER_WIDTH=$(identify $THROBBER | head -1 | cut -d " " -f 3 | cut -d x -f 1)
	THROBBER_HEIGHT=$(identify $THROBBER | head -1 | cut -d " " -f 3 | cut -d x -f 2)
	convert -alpha remove -background "#000000"	$LOGO "${SDCARD}"/tmp/logo.rgb
	convert -alpha remove -background "#000000" $THROBBER "${SDCARD}"/tmp/throbber%02d.rgb
	$PKG_PREFIX${SRC}/packages/blobs/splash/bootsplash-packer \
	--bg_red 0x00 \
	--bg_green 0x00 \
	--bg_blue 0x00 \
	--frame_ms 48 \
	--picture \
	--pic_width $LOGO_WIDTH \
	--pic_height $LOGO_HEIGHT \
	--pic_position 0 \
	--blob "${SDCARD}"/tmp/logo.rgb \
	--picture \
	--pic_width $THROBBER_WIDTH \
	--pic_height $THROBBER_HEIGHT \
	--pic_position 0x05 \
	--pic_position_offset 200 \
	--pic_anim_type 1 \
	--pic_anim_loop 0 \
	--blob "${SDCARD}"/tmp/throbber00.rgb \
	--blob "${SDCARD}"/tmp/throbber01.rgb \
	--blob "${SDCARD}"/tmp/throbber02.rgb \
	--blob "${SDCARD}"/tmp/throbber03.rgb \
	--blob "${SDCARD}"/tmp/throbber04.rgb \
	--blob "${SDCARD}"/tmp/throbber05.rgb \
	--blob "${SDCARD}"/tmp/throbber06.rgb \
	--blob "${SDCARD}"/tmp/throbber07.rgb \
	--blob "${SDCARD}"/tmp/throbber08.rgb \
	--blob "${SDCARD}"/tmp/throbber09.rgb \
	--blob "${SDCARD}"/tmp/throbber10.rgb \
	--blob "${SDCARD}"/tmp/throbber11.rgb \
	--blob "${SDCARD}"/tmp/throbber12.rgb \
	--blob "${SDCARD}"/tmp/throbber13.rgb \
	--blob "${SDCARD}"/tmp/throbber14.rgb \
	--blob "${SDCARD}"/tmp/throbber15.rgb \
	--blob "${SDCARD}"/tmp/throbber16.rgb \
	--blob "${SDCARD}"/tmp/throbber17.rgb \
	--blob "${SDCARD}"/tmp/throbber18.rgb \
	--blob "${SDCARD}"/tmp/throbber19.rgb \
	--blob "${SDCARD}"/tmp/throbber20.rgb \
	--blob "${SDCARD}"/tmp/throbber21.rgb \
	--blob "${SDCARD}"/tmp/throbber22.rgb \
	--blob "${SDCARD}"/tmp/throbber23.rgb \
	--blob "${SDCARD}"/tmp/throbber24.rgb \
	--blob "${SDCARD}"/tmp/throbber25.rgb \
	--blob "${SDCARD}"/tmp/throbber26.rgb \
	--blob "${SDCARD}"/tmp/throbber27.rgb \
	--blob "${SDCARD}"/tmp/throbber28.rgb \
	--blob "${SDCARD}"/tmp/throbber29.rgb \
	--blob "${SDCARD}"/tmp/throbber30.rgb \
	--blob "${SDCARD}"/tmp/throbber31.rgb \
	--blob "${SDCARD}"/tmp/throbber32.rgb \
	--blob "${SDCARD}"/tmp/throbber33.rgb \
	--blob "${SDCARD}"/tmp/throbber34.rgb \
	--blob "${SDCARD}"/tmp/throbber35.rgb \
	--blob "${SDCARD}"/tmp/throbber36.rgb \
	--blob "${SDCARD}"/tmp/throbber37.rgb \
	--blob "${SDCARD}"/tmp/throbber38.rgb \
	--blob "${SDCARD}"/tmp/throbber39.rgb \
	--blob "${SDCARD}"/tmp/throbber40.rgb \
	--blob "${SDCARD}"/tmp/throbber41.rgb \
	--blob "${SDCARD}"/tmp/throbber42.rgb \
	--blob "${SDCARD}"/tmp/throbber43.rgb \
	--blob "${SDCARD}"/tmp/throbber44.rgb \
	--blob "${SDCARD}"/tmp/throbber45.rgb \
	--blob "${SDCARD}"/tmp/throbber46.rgb \
	--blob "${SDCARD}"/tmp/throbber47.rgb \
	--blob "${SDCARD}"/tmp/throbber48.rgb \
	--blob "${SDCARD}"/tmp/throbber49.rgb \
	--blob "${SDCARD}"/tmp/throbber50.rgb \
	--blob "${SDCARD}"/tmp/throbber51.rgb \
	--blob "${SDCARD}"/tmp/throbber52.rgb \
	--blob "${SDCARD}"/tmp/throbber53.rgb \
	--blob "${SDCARD}"/tmp/throbber54.rgb \
	--blob "${SDCARD}"/tmp/throbber55.rgb \
	--blob "${SDCARD}"/tmp/throbber56.rgb \
	--blob "${SDCARD}"/tmp/throbber57.rgb \
	--blob "${SDCARD}"/tmp/throbber58.rgb \
	--blob "${SDCARD}"/tmp/throbber59.rgb \
	--blob "${SDCARD}"/tmp/throbber60.rgb \
	--blob "${SDCARD}"/tmp/throbber61.rgb \
	--blob "${SDCARD}"/tmp/throbber62.rgb \
	--blob "${SDCARD}"/tmp/throbber63.rgb \
	--blob "${SDCARD}"/tmp/throbber64.rgb \
	--blob "${SDCARD}"/tmp/throbber65.rgb \
	--blob "${SDCARD}"/tmp/throbber66.rgb \
	--blob "${SDCARD}"/tmp/throbber67.rgb \
	--blob "${SDCARD}"/tmp/throbber68.rgb \
	--blob "${SDCARD}"/tmp/throbber69.rgb \
	--blob "${SDCARD}"/tmp/throbber70.rgb \
	--blob "${SDCARD}"/tmp/throbber71.rgb \
	--blob "${SDCARD}"/tmp/throbber72.rgb \
	--blob "${SDCARD}"/tmp/throbber73.rgb \
	--blob "${SDCARD}"/tmp/throbber74.rgb \
	"${SDCARD}"/lib/firmware/bootsplash.armbian >/dev/null 2>&1
	if [[ $BOOT_LOGO == yes || $BOOT_LOGO == desktop && $BUILD_DESKTOP == yes ]]; then
		[[ -f "${SDCARD}"/boot/armbianEnv.txt ]] &&	grep -q '^bootlogo' "${SDCARD}"/boot/armbianEnv.txt && \
		sed -i 's/^bootlogo.*/bootlogo=true/' "${SDCARD}"/boot/armbianEnv.txt || echo 'bootlogo=true' >> "${SDCARD}"/boot/armbianEnv.txt
		[[ -f "${SDCARD}"/boot/boot.ini ]] &&	sed -i 's/^setenv bootlogo.*/setenv bootlogo "true"/' "${SDCARD}"/boot/boot.ini
	fi
	# enable additional services
	chroot "${SDCARD}" /bin/bash -c "systemctl --no-reload enable bootsplash-ask-password-console.path >/dev/null 2>&1"
	chroot "${SDCARD}" /bin/bash -c "systemctl --no-reload enable bootsplash-hide-when-booted.service >/dev/null 2>&1"
	chroot "${SDCARD}" /bin/bash -c "systemctl --no-reload enable bootsplash-show-on-shutdown.service >/dev/null 2>&1"
}



DISTRIBUTIONS_DESC_DIR="config/distributions"

function distro_menu ()
{
# create a select menu for choosing a distribution based EXPERT status

	local distrib_dir="${1}"

	if [[ -d "${distrib_dir}" && -f "${distrib_dir}/support" ]]; then
		local support_level="$(cat "${distrib_dir}/support")"
		if [[ "${support_level}" != "supported" && $EXPERT != "yes" ]]; then
			:
		else
			local distro_codename="$(basename "${distrib_dir}")"
			local distro_fullname="$(cat "${distrib_dir}/name")"
			local expert_infos=""
			[[ $EXPERT == "yes" ]] && expert_infos="(${support_level})"
			options+=("${distro_codename}" "${distro_fullname} ${expert_infos}")
		fi
	fi

}


function distros_options() {
	for distrib_dir in "${DISTRIBUTIONS_DESC_DIR}/"*; do
		distro_menu "${distrib_dir}"
	done
}

function set_distribution_status() {

	local distro_support_desc_filepath="${SRC}/${DISTRIBUTIONS_DESC_DIR}/${RELEASE}/support"
	if [[ ! -f "${distro_support_desc_filepath}" ]]; then
		exit_with_error "Distribution ${distribution_name} does not exist"
	else
		DISTRIBUTION_STATUS="$(cat "${distro_support_desc_filepath}")"
	fi

	[[ "${DISTRIBUTION_STATUS}" != "supported" ]] && [[ "${EXPERT}" != "yes" ]] && exit_with_error "Armbian ${RELEASE} is unsupported and, therefore, only available to experts (EXPERT=yes)"

}

adding_packages()
{
# add deb files to repository if they are not already there

	display_alert "Checking and adding to repository $release" "$3" "ext"
	for f in "${DEB_STORAGE}${2}"/*.deb
	do
		local name version arch
		name=$(dpkg-deb -I "${f}" | grep Package | awk '{print $2}')
		version=$(dpkg-deb -I "${f}" | grep Version | awk '{print $2}')
		arch=$(dpkg-deb -I "${f}" | grep Architecture | awk '{print $2}')
		# add if not already there
		aptly repo search -architectures="${arch}" -config="${SCRIPTPATH}config/${REPO_CONFIG}" "${1}" 'Name (% '${name}'), $Version (='${version}'), $Architecture (='${arch}')' &>/dev/null
		if [[ $? -ne 0 ]]; then
			display_alert "Adding ${1}" "$name" "info"
			aptly repo add -force-replace=true -config="${SCRIPTPATH}config/${REPO_CONFIG}" "${1}" "${f}" &>/dev/null
		fi
	done

}




addtorepo()
{
# create repository
# parameter "remove" dumps all and creates new
# parameter "delete" remove incoming directory if publishing is succesful
# function: cycle trough distributions

	local distributions=("stretch" "bionic" "buster" "bullseye" "focal" "hirsute" "impish" "jammy" "sid")
	#local distributions=($(grep -rw config/distributions/*/ -e 'supported' | cut -d"/" -f3))
	local errors=0

	for release in "${distributions[@]}"; do

		ADDING_PACKAGES="false"
		if [[ -d "config/distributions/${release}/" ]]; then
			[[ -n "$(cat config/distributions/${release}/support | grep "csc\|supported" 2>/dev/null)" ]] && ADDING_PACKAGES="true"
		else
			display_alert "Skipping adding packages (not supported)" "$release" "wrn"
			continue
		fi

		local forceoverwrite=""

		# let's drop from publish if exits
		if [[ -n $(aptly publish list -config="${SCRIPTPATH}config/${REPO_CONFIG}" -raw | awk '{print $(NF)}' | grep "${release}") ]]; then
			aptly publish drop -config="${SCRIPTPATH}config/${REPO_CONFIG}" "${release}" > /dev/null 2>&1
		fi

		# create local repository if not exist
		if [[ -z $(aptly repo list -config="${SCRIPTPATH}config/${REPO_CONFIG}" -raw | awk '{print $(NF)}' | grep "${release}") ]]; then
			display_alert "Creating section" "main" "info"
			aptly repo create -config="${SCRIPTPATH}config/${REPO_CONFIG}" -distribution="${release}" -component="main" \
			-comment="Armbian main repository" "${release}" >/dev/null
		fi

		if [[ -z $(aptly repo list -config="${SCRIPTPATH}config/${REPO_CONFIG}" -raw | awk '{print $(NF)}' | grep "^utils") ]]; then
			aptly repo create -config="${SCRIPTPATH}config/${REPO_CONFIG}" -distribution="${release}" -component="utils" \
			-comment="Armbian utilities (backwards compatibility)" utils >/dev/null
		fi
		if [[ -z $(aptly repo list -config="${SCRIPTPATH}config/${REPO_CONFIG}" -raw | awk '{print $(NF)}' | grep "${release}-utils") ]]; then
			aptly repo create -config="${SCRIPTPATH}config/${REPO_CONFIG}" -distribution="${release}" -component="${release}-utils" \
			-comment="Armbian ${release} utilities" "${release}-utils" >/dev/null
		fi
		if [[ -z $(aptly repo list -config="${SCRIPTPATH}config/${REPO_CONFIG}" -raw | awk '{print $(NF)}' | grep "${release}-desktop") ]]; then
			aptly repo create -config="${SCRIPTPATH}config/${REPO_CONFIG}" -distribution="${release}" -component="${release}-desktop" \
			-comment="Armbian ${release} desktop" "${release}-desktop" >/dev/null
		fi


		# adding main
		if find "${DEB_STORAGE}"/ -maxdepth 1 -type f -name "*.deb" 2>/dev/null | grep -q .; then
			[[ "${ADDING_PACKAGES}" == true ]] && adding_packages "$release" "" "main"
		else
			aptly repo add -config="${SCRIPTPATH}config/${REPO_CONFIG}" "${release}" "${SCRIPTPATH}config/templates/example.deb" >/dev/null
		fi

		local COMPONENTS="main"

		# adding main distribution packages
		if find "${DEB_STORAGE}/${release}" -maxdepth 1 -type f -name "*.deb" 2>/dev/null | grep -q .; then
			[[ "${ADDING_PACKAGES}" == true ]] && adding_packages "${release}-utils" "/${release}" "release packages"
		else
			# workaround - add dummy package to not trigger error
			aptly repo add -config="${SCRIPTPATH}config/${REPO_CONFIG}" "${release}" "${SCRIPTPATH}config/templates/example.deb" >/dev/null
		fi

		# adding release-specific utils
		if find "${DEB_STORAGE}/extra/${release}-utils" -maxdepth 1 -type f -name "*.deb" 2>/dev/null | grep -q .; then
			[[ "${ADDING_PACKAGES}" == true ]] && adding_packages "${release}-utils" "/extra/${release}-utils" "release utils"
		else
			aptly repo add -config="${SCRIPTPATH}config/${REPO_CONFIG}" "${release}-utils" "${SCRIPTPATH}config/templates/example.deb" >/dev/null
		fi
		COMPONENTS="${COMPONENTS} ${release}-utils"

		# adding desktop
		if find "${DEB_STORAGE}/extra/${release}-desktop" -maxdepth 1 -type f -name "*.deb" 2>/dev/null | grep -q .; then
			[[ "${ADDING_PACKAGES}" == true ]] && adding_packages "${release}-desktop" "/extra/${release}-desktop" "desktop"
		else
			# workaround - add dummy package to not trigger error
			aptly repo add -config="${SCRIPTPATH}config/${REPO_CONFIG}" "${release}-desktop" "${SCRIPTPATH}config/templates/example.deb" >/dev/null
		fi
		COMPONENTS="${COMPONENTS} ${release}-desktop"

		local mainnum utilnum desknum
		mainnum=$(aptly repo show -with-packages -config="${SCRIPTPATH}config/${REPO_CONFIG}" "${release}" | grep "Number of packages" | awk '{print $NF}')
		utilnum=$(aptly repo show -with-packages -config="${SCRIPTPATH}config/${REPO_CONFIG}" "${release}-desktop" | grep "Number of packages" | awk '{print $NF}')
		desknum=$(aptly repo show -with-packages -config="${SCRIPTPATH}config/${REPO_CONFIG}" "${release}-utils" | grep "Number of packages" | awk '{print $NF}')

		if [ $mainnum -gt 0 ] && [ $utilnum -gt 0 ] && [ $desknum -gt 0 ]; then

			# publish
			aptly publish \
			-acquire-by-hash \
			-passphrase="${GPG_PASS}" \
			-origin="Armbian" \
			-label="Armbian" \
			-config="${SCRIPTPATH}config/${REPO_CONFIG}" \
			-component="${COMPONENTS// /,}" \
			-distribution="${release}" repo "${release}" ${COMPONENTS//main/} >/dev/null

			if [[ $? -ne 0 ]]; then
				display_alert "Publishing failed" "${release}" "err"
				errors=$((errors+1))
				exit 0
			fi
		else
			errors=$((errors+1))
			local err_txt=": All components must be present: main, utils and desktop for first build"
		fi

	done

	# cleanup
	display_alert "Cleaning repository" "${DEB_STORAGE}" "info"
	aptly db cleanup -config="${SCRIPTPATH}config/${REPO_CONFIG}"

	# display what we have
	echo ""
	display_alert "List of local repos" "local" "info"
	(aptly repo list -config="${SCRIPTPATH}config/${REPO_CONFIG}") | grep -E packages

	# remove debs if no errors found
	if [[ $errors -eq 0 ]]; then
		if [[ "$2" == "delete" ]]; then
			display_alert "Purging incoming debs" "all" "ext"
			find "${DEB_STORAGE}" -name "*.deb" -type f -delete
		fi
	else
		display_alert "There were some problems $err_txt" "leaving incoming directory intact" "err"
	fi

}




repo-manipulate()
{
# repository manipulation
# "show" displays packages in each repository
# "server" serve repository - useful for local diagnostics
# "unique" manually select which package should be removed from all repositories
# "update" search for new files in output/debs* to add them to repository
# "purge" leave only last 5 versions

	local DISTROS=("stretch" "bionic" "buster" "bullseye" "focal" "hirsute" "impish" "jammy" "sid")
	#local DISTROS=($(grep -rw config/distributions/*/ -e 'supported' | cut -d"/" -f3))

	case $@ in

		serve)
			# display repository content
			display_alert "Serving content" "common utils" "ext"
			aptly serve -listen=$(ip -f inet addr | grep -Po 'inet \K[\d.]+' | grep -v 127.0.0.1 | head -1):80 -config="${SCRIPTPATH}config/${REPO_CONFIG}"
			exit 0
			;;

		show)
			# display repository content
			for release in "${DISTROS[@]}"; do
				display_alert "Displaying repository contents for" "$release" "ext"
				aptly repo show -with-packages -config="${SCRIPTPATH}config/${REPO_CONFIG}" "${release}" | tail -n +7
				aptly repo show -with-packages -config="${SCRIPTPATH}config/${REPO_CONFIG}" "${release}-desktop" | tail -n +7
			done
			display_alert "Displaying repository contents for" "common utils" "ext"
			aptly repo show -with-packages -config="${SCRIPTPATH}config/${REPO_CONFIG}" utils | tail -n +7
			echo "done."
			exit 0
			;;

		unique)
			# which package should be removed from all repositories
			IFS=$'\n'
			while true; do
				LIST=()
				for release in "${DISTROS[@]}"; do
					LIST+=( $(aptly repo show -with-packages -config="${SCRIPTPATH}config/${REPO_CONFIG}" "${release}" | tail -n +7) )
					LIST+=( $(aptly repo show -with-packages -config="${SCRIPTPATH}config/${REPO_CONFIG}" "${release}-desktop" | tail -n +7) )
				done
				LIST+=( $(aptly repo show -with-packages -config="${SCRIPTPATH}config/${REPO_CONFIG}" utils | tail -n +7) )
				LIST=( $(echo "${LIST[@]}" | tr ' ' '\n' | sort -u))
				new_list=()
				# create a human readable menu
				for ((n=0;n<$((${#LIST[@]}));n++));
				do
					new_list+=( "${LIST[$n]}" )
					new_list+=( "" )
				done
				LIST=("${new_list[@]}")
				LIST_LENGTH=$((${#LIST[@]}/2));
				exec 3>&1
				TARGET_VERSION=$(dialog --cancel-label "Cancel" --backtitle "BACKTITLE" --no-collapse --title "Remove packages from repositories" --clear --menu "Delete" $((9+${LIST_LENGTH})) 82 65 "${LIST[@]}" 2>&1 1>&3)
				exitstatus=$?;
				exec 3>&-
				if [[ $exitstatus -eq 0 ]]; then
					for release in "${DISTROS[@]}"; do
						aptly repo remove -config="${SCRIPTPATH}config/${REPO_CONFIG}"  "${release}" "$TARGET_VERSION"
						aptly repo remove -config="${SCRIPTPATH}config/${REPO_CONFIG}"  "${release}-desktop" "$TARGET_VERSION"
					done
					aptly repo remove -config="${SCRIPTPATH}config/${REPO_CONFIG}" "utils" "$TARGET_VERSION"
				else
					exit 1
				fi
				aptly db cleanup -config="${SCRIPTPATH}config/${REPO_CONFIG}" > /dev/null 2>&1
			done
			;;

		update)
			# display full help test
			# run repository update
			addtorepo "update" ""
			# add a key to repo
			cp "${SCRIPTPATH}"config/armbian.key "${REPO_STORAGE}"/public/
			exit 0
			;;

		purge)
			for release in "${DISTROS[@]}"; do
				repo-remove-old-packages "$release" "armhf" "5"
				repo-remove-old-packages "$release" "arm64" "5"
				repo-remove-old-packages "$release" "amd64" "5"
				repo-remove-old-packages "$release" "all" "5"
				aptly -config="${SCRIPTPATH}config/${REPO_CONFIG}" -passphrase="${GPG_PASS}" publish update "${release}" > /dev/null 2>&1
			done
			exit 0
			;;

                purgeedge)
                        for release in "${DISTROS[@]}"; do
				repo-remove-old-packages "$release" "armhf" "3" "edge"
				repo-remove-old-packages "$release" "arm64" "3" "edge"
				repo-remove-old-packages "$release" "amd64" "3" "edge"
				repo-remove-old-packages "$release" "all" "3" "edge"
				aptly -config="${SCRIPTPATH}config/${REPO_CONFIG}" -passphrase="${GPG_PASS}" publish update "${release}" > /dev/null 2>&1
                        done
                        exit 0
                        ;;


		purgesource)
			for release in "${DISTROS[@]}"; do
				aptly repo remove -config="${SCRIPTPATH}config/${REPO_CONFIG}" "${release}" 'Name (% *-source*)'
				aptly -config="${SCRIPTPATH}config/${REPO_CONFIG}" -passphrase="${GPG_PASS}" publish update "${release}"  > /dev/null 2>&1
			done
			aptly db cleanup -config="${SCRIPTPATH}config/${REPO_CONFIG}" > /dev/null 2>&1
			exit 0
			;;
		*)

			echo -e "Usage: repository show | serve | unique | create | update | purge | purgesource\n"
			echo -e "\n show           = display repository content"
			echo -e "\n serve          = publish your repositories on current server over HTTP"
			echo -e "\n unique         = manually select which package should be removed from all repositories"
			echo -e "\n update         = updating repository"
			echo -e "\n purge          = removes all but last 5 versions"
			echo -e "\n purgeedge      = removes all but last 3 edge versions"
			echo -e "\n purgesource    = removes all sources\n\n"
			exit 0
			;;

	esac

}




# Removes old packages in the received repo
#
# $1: Repository
# $2: Architecture
# $3: Amount of packages to keep
# $4: Additional search pattern
repo-remove-old-packages() {
	local repo=$1
	local arch=$2
	local keep=$3
	for pkg in $(aptly repo search -config="${SCRIPTPATH}config/${REPO_CONFIG}" "${repo}" "Architecture ($arch)" | grep -v "ERROR: no results" | sort -t '.' -nk4 | grep -e "$4"); do
		local pkg_name
		count=0
		pkg_name=$(echo "${pkg}" | cut -d_ -f1)
		for subpkg in $(aptly repo search -config="${SCRIPTPATH}config/${REPO_CONFIG}" "${repo}" "Name ($pkg_name)"  | grep -v "ERROR: no results" | sort -rt '.' -nk4); do
			((count+=1))
			if [[ $count -gt $keep ]]; then
			pkg_version=$(echo "${subpkg}" | cut -d_ -f2)
			aptly repo remove -config="${SCRIPTPATH}config/${REPO_CONFIG}" "${repo}" "Name ($pkg_name), Version (= $pkg_version)"
			fi
		done
    done
}




# wait_for_package_manager
#
# * installation will break if we try to install when package manager is running
#
wait_for_package_manager()
{
	# exit if package manager is running in the back
	while true; do
		if [[ "$(fuser /var/lib/dpkg/lock 2>/dev/null; echo $?)" != 1 && "$(fuser /var/lib/dpkg/lock-frontend 2>/dev/null; echo $?)" != 1 ]]; then
				display_alert "Package manager is running in the background." "Please wait! Retrying in 30 sec" "wrn"
				sleep 30
			else
				break
		fi
	done
}



# Installing debian packages or package files in the armbian build system.
# The function accepts four optional parameters:
# autoupdate - If the installation list is not empty then update first.
# upgrade, clean - the same name for apt
# verbose - detailed log for the function
#
# list="pkg1 pkg2 pkg3 pkgbadname pkg-1.0 | pkg-2.0 pkg5 (>= 9)"
# or list="pkg1 pkg2 /path-to/output/debs/file-name.deb"
# install_pkg_deb upgrade verbose $list
# or
# install_pkg_deb autoupdate $list
#
# If the package has a bad name, we will see it in the log file.
# If there is an LOG_OUTPUT_FILE variable and it has a value as
# the full real path to the log file, then all the information will be there.
#
# The LOG_OUTPUT_FILE variable must be defined in the calling function
# before calling the install_pkg_deb function and unset after.
#
install_pkg_deb ()
{
	local list=""
	local listdeb=""
	local log_file
	local add_for_install
	local for_install
	local need_autoup=false
	local need_upgrade=false
	local need_clean=false
	local need_verbose=false
	local _line=${BASH_LINENO[0]}
	local _function=${FUNCNAME[1]}
	local _file=$(basename "${BASH_SOURCE[1]}")
	local tmp_file=$(mktemp /tmp/install_log_XXXXX)
	export DEBIAN_FRONTEND=noninteractive

	if [ -d $(dirname $LOG_OUTPUT_FILE) ]; then
		log_file=${LOG_OUTPUT_FILE}
	else
		log_file="${SRC}/output/${LOG_SUBPATH}/install.log"
	fi

	for p in $*;do
		case $p in
			autoupdate) need_autoup=true; continue ;;
			upgrade) need_upgrade=true; continue ;;
			clean) need_clean=true; continue ;;
			verbose) need_verbose=true; continue ;;
			\||\(*|*\)) continue ;;
			*[.]deb) listdeb+=" $p"; continue ;;
			*) list+=" $p" ;;
		esac
	done

	# This is necessary first when there is no apt cache.
	if $need_upgrade; then
		apt-get -q update || echo "apt cannot update" >>$tmp_file
		apt-get -y upgrade || echo "apt cannot upgrade" >>$tmp_file
	fi

	# Install debian package files
	if [ -n "$listdeb" ];then
		for f in $listdeb;do
			# Calculate dependencies for installing the package file
			add_for_install=" $(
				dpkg-deb -f $f Depends | awk '{gsub(/[,]/, "", $0); print $0}'
			)"

			echo -e "\nfile $f depends on:\n$add_for_install"  >>$log_file
			install_pkg_deb $add_for_install
			dpkg -i $f 2>>$log_file
			dpkg-query -W \
					   -f '${binary:Package;-27} ${Version;-23}\n' \
					   $(dpkg-deb -f $f Package) >>$log_file
		done
	fi

	# If the package is not installed, check the latest
	# up-to-date version in the apt cache.
	# Exclude bad package names and send a message to the log.
	for_install=$(
	for p in $list;do
	  if $(dpkg-query -W -f '${db:Status-Abbrev}' $p |& awk '/ii/{exit 1}');then
		apt-cache  show $p -o APT::Cache::AllVersions=no |& \
		awk -v p=$p -v tmp_file=$tmp_file \
		'/^Package:/{print $2} /^E:/{print "Bad package name: ",p >>tmp_file}'
	  fi
	done
	)

	# This information should be logged.
	if [ -s $tmp_file ]; then
		echo -e "\nInstalling packages in function: $_function" "[$_file:$_line]" \
		>>$log_file
		echo -e "\nIncoming list:" >>$log_file
		printf "%-30s %-30s %-30s %-30s\n" $list >>$log_file
		echo "" >>$log_file
		cat $tmp_file >>$log_file
	fi

	if [ -n "$for_install" ]; then
		if $need_autoup; then
			apt-get -q update
			apt-get -y upgrade
		fi
		apt-get install -qq -y --no-install-recommends $for_install
		echo -e "\nPackages installed:" >>$log_file
		dpkg-query -W \
		  -f '${binary:Package;-27} ${Version;-23}\n' \
		  $for_install >>$log_file

	fi

	# We will show the status after installation all listed
	if $need_verbose; then
		echo -e "\nstatus after installation:" >>$log_file
		dpkg-query -W \
		  -f '${binary:Package;-27} ${Version;-23} [ ${Status} ]\n' \
		  $list >>$log_file
	fi

	if $need_clean;then apt-get clean; fi
	rm $tmp_file
}



# prepare_host_basic
#
# * installs only basic packages
#
prepare_host_basic()
{

	# command:package1 package2 ...
	# list of commands that are neeeded:packages where this command is
	local check_pack install_pack
	local checklist=(
			"dialog:dialog"
			"fuser:psmisc"
			"getfacl:acl"
			"uuid:uuid uuid-runtime"
			"curl:curl"
			"gpg:gnupg"
			"gawk:gawk"
			)

	for check_pack in "${checklist[@]}"; do
	        if ! which ${check_pack%:*} >/dev/null; then local install_pack+=${check_pack#*:}" "; fi
	done

	if [[ -n $install_pack ]]; then
		display_alert "Installing basic packages" "$install_pack"
		sudo bash -c "apt-get -qq update && apt-get install -qq -y --no-install-recommends $install_pack"
	fi

}




# prepare_host
#
# * checks and installs necessary packages
# * creates directory structure
# * changes system settings
#
prepare_host()
{
	display_alert "Preparing" "host" "info"

	# The 'offline' variable must always be set to 'true' or 'false'
	if [ "$OFFLINE_WORK" == "yes" ]; then
		local offline=true
	else
		local offline=false
	fi

	# wait until package manager finishes possible system maintanace
	wait_for_package_manager

	# fix for Locales settings
	if ! grep -q "^en_US.UTF-8 UTF-8" /etc/locale.gen; then
		sudo sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
		sudo locale-gen
	fi

	export LC_ALL="en_US.UTF-8"

	# packages list for host
	# NOTE: please sync any changes here with the Dockerfile and Vagrantfile

	local hostdeps="acl aptly aria2 bc binfmt-support bison btrfs-progs       \
	build-essential  ca-certificates ccache cpio cryptsetup curl              \
	debian-archive-keyring debian-keyring debootstrap device-tree-compiler    \
	dialog dirmngr dosfstools dwarves f2fs-tools fakeroot flex gawk           \
	gcc-arm-linux-gnueabi gcc-aarch64-linux-gnu gdisk gpg busybox             \
	imagemagick jq kmod libbison-dev libc6-dev-armhf-cross libcrypto++-dev    \
	libelf-dev libfdt-dev libfile-fcntllock-perl parallel libmpc-dev          \
	libfl-dev liblz4-tool libncurses-dev libpython2.7-dev libssl-dev          \
	libusb-1.0-0-dev linux-base locales lzop ncurses-base ncurses-term        \
	nfs-kernel-server ntpdate p7zip-full parted patchutils pigz pixz          \
	pkg-config pv python3-dev python3-distutils qemu-user-static rsync swig   \
	systemd-container u-boot-tools udev unzip uuid-dev wget whiptail zip      \
	zlib1g-dev zstd"

  if [[ $(dpkg --print-architecture) == amd64 ]]; then

	hostdeps+=" distcc lib32ncurses-dev lib32stdc++6 libc6-i386"
	grep -q i386 <(dpkg --print-foreign-architectures) || dpkg --add-architecture i386

  elif [[ $(dpkg --print-architecture) == arm64 ]]; then

	hostdeps+="gcc-arm-none-eabi libc6 libc6-amd64-cross qemu"

  else

	display_alert "Please read documentation to set up proper compilation environment"
	display_alert "https://www.armbian.com/using-armbian-tools/"
	exit_with_error "Running this tool on non x86_64 build host is not supported"

  fi

	# Add support for Ubuntu 20.04, 21.04 and Mint 20.x
	if [[ $HOSTRELEASE =~ ^(focal|impish|hirsute|jammy|ulyana|ulyssa|bullseye|uma|una)$ ]]; then
		hostdeps+=" python2 python3"
		ln -fs /usr/bin/python2.7 /usr/bin/python2
		ln -fs /usr/bin/python2.7 /usr/bin/python
	else
		hostdeps+=" python libpython-dev"
	fi

	display_alert "Build host OS release" "${HOSTRELEASE:-(unknown)}" "info"

	# Ubuntu 21.04.x (Hirsute) x86_64 is the only fully supported host OS release
	# Using Docker/VirtualBox/Vagrant is the only supported way to run the build script on other Linux distributions
	#
	# NO_HOST_RELEASE_CHECK overrides the check for a supported host system
	# Disable host OS check at your own risk. Any issues reported with unsupported releases will be closed without discussion
	if [[ -z $HOSTRELEASE || "buster bullseye focal impish hirsute jammy debbie tricia ulyana ulyssa uma una" != *"$HOSTRELEASE"* ]]; then
		if [[ $NO_HOST_RELEASE_CHECK == yes ]]; then
			display_alert "You are running on an unsupported system" "${HOSTRELEASE:-(unknown)}" "wrn"
			display_alert "Do not report any errors, warnings or other issues encountered beyond this point" "" "wrn"
		else
			exit_with_error "It seems you ignore documentation and run an unsupported build system: ${HOSTRELEASE:-(unknown)}"
		fi
	fi

	if grep -qE "(Microsoft|WSL)" /proc/version; then
		if [ -f /.dockerenv ]; then
			display_alert "Building images using Docker on WSL2 may fail" "" "wrn"
		else
			exit_with_error "Windows subsystem for Linux is not a supported build environment"
		fi
	fi

	if systemd-detect-virt -q -c; then
		display_alert "Running in container" "$(systemd-detect-virt)" "info"
		# disable apt-cacher unless NO_APT_CACHER=no is not specified explicitly
		if [[ $NO_APT_CACHER != no ]]; then
			display_alert "apt-cacher is disabled in containers, set NO_APT_CACHER=no to override" "" "wrn"
			NO_APT_CACHER=yes
		fi
		CONTAINER_COMPAT=yes
		# trying to use nested containers is not a good idea, so don't permit EXTERNAL_NEW=compile
		if [[ $EXTERNAL_NEW == compile ]]; then
			display_alert "EXTERNAL_NEW=compile is not available when running in container, setting to prebuilt" "" "wrn"
			EXTERNAL_NEW=prebuilt
		fi
		SYNC_CLOCK=no
	fi


	# Skip verification if you are working offline
	if ! $offline; then

	# warning: apt-cacher-ng will fail if installed and used both on host and in
	# container/chroot environment with shared network
	# set NO_APT_CACHER=yes to prevent installation errors in such case
	if [[ $NO_APT_CACHER != yes ]]; then hostdeps+=" apt-cacher-ng"; fi

	export EXTRA_BUILD_DEPS=""
	call_extension_method "add_host_dependencies" <<- 'ADD_HOST_DEPENDENCIES'
	*run before installing host dependencies*
	you can add packages to install, space separated, to ${EXTRA_BUILD_DEPS} here.
	ADD_HOST_DEPENDENCIES

	if [ -n "${EXTRA_BUILD_DEPS}" ]; then hostdeps+=" ${EXTRA_BUILD_DEPS}"; fi

	display_alert "Installing build dependencies"
	# don't prompt for apt cacher selection
	sudo echo "apt-cacher-ng    apt-cacher-ng/tunnelenable      boolean false" | sudo debconf-set-selections

	LOG_OUTPUT_FILE="${DEST}"/${LOG_SUBPATH}/hostdeps.log
	install_pkg_deb "autoupdate $hostdeps"
	unset LOG_OUTPUT_FILE

	update-ccache-symlinks

	export FINAL_HOST_DEPS="$hostdeps ${EXTRA_BUILD_DEPS}"
	call_extension_method "host_dependencies_ready" <<- 'HOST_DEPENDENCIES_READY'
	*run after all host dependencies are installed*
	At this point we can read `${FINAL_HOST_DEPS}`, but changing won't have any effect.
	All the dependencies, including the default/core deps and the ones added via `${EXTRA_BUILD_DEPS}`
	are installed at this point. The system clock has not yet been synced.
	HOST_DEPENDENCIES_READY


	# sync clock
	if [[ $SYNC_CLOCK != no ]]; then
		display_alert "Syncing clock" "host" "info"
		ntpdate -s "${NTP_SERVER:-pool.ntp.org}"
	fi

	# create directory structure
	mkdir -p "${SRC}"/{cache,output} "${USERPATCHES_PATH}"
	if [[ -n $SUDO_USER ]]; then
		chgrp --quiet sudo cache output "${USERPATCHES_PATH}"
		# SGID bit on cache/sources breaks kernel dpkg packaging
		chmod --quiet g+w,g+s output "${USERPATCHES_PATH}"
		# fix existing permissions
		find "${SRC}"/output "${USERPATCHES_PATH}" -type d ! -group sudo -exec chgrp --quiet sudo {} \;
		find "${SRC}"/output "${USERPATCHES_PATH}" -type d ! -perm -g+w,g+s -exec chmod --quiet g+w,g+s {} \;
	fi
	mkdir -p "${DEST}"/debs-beta/extra "${DEST}"/debs/extra "${DEST}"/{config,debug,patch} "${USERPATCHES_PATH}"/overlay "${SRC}"/cache/{sources,hash,hash-beta,toolchain,utility,rootfs} "${SRC}"/.tmp

# build aarch64
	if [[ $(dpkg --print-architecture) == amd64 ]]; then
		if [[ "${SKIP_EXTERNAL_TOOLCHAINS}" != "yes" ]]; then

			# bind mount toolchain if defined
			if [[ -d "${ARMBIAN_CACHE_TOOLCHAIN_PATH}" ]]; then
				mountpoint -q "${SRC}"/cache/toolchain && umount -l "${SRC}"/cache/toolchain
				mount --bind "${ARMBIAN_CACHE_TOOLCHAIN_PATH}" "${SRC}"/cache/toolchain
			fi

			display_alert "Checking for external GCC compilers" "" "info"
			# download external Linaro compiler and missing special dependencies since they are needed for certain sources

			local toolchains=(
				"gcc-linaro-aarch64-none-elf-4.8-2013.11_linux.tar.xz"
				"gcc-linaro-arm-none-eabi-4.8-2014.04_linux.tar.xz"
				"gcc-linaro-arm-linux-gnueabihf-4.8-2014.04_linux.tar.xz"
				"gcc-linaro-7.4.1-2019.02-x86_64_arm-linux-gnueabi.tar.xz"
				"gcc-linaro-7.4.1-2019.02-x86_64_aarch64-linux-gnu.tar.xz"
				"gcc-arm-8.3-2019.03-x86_64-arm-linux-gnueabihf.tar.xz"
				"gcc-arm-8.3-2019.03-x86_64-aarch64-linux-gnu.tar.xz"
				"gcc-arm-9.2-2019.12-x86_64-arm-none-linux-gnueabihf.tar.xz"
				"gcc-arm-9.2-2019.12-x86_64-aarch64-none-linux-gnu.tar.xz"
				"gcc-arm-11.2-2022.02-x86_64-arm-none-linux-gnueabihf.tar.xz"
				"gcc-arm-11.2-2022.02-x86_64-aarch64-none-linux-gnu.tar.xz"
				)

			USE_TORRENT_STATUS=${USE_TORRENT}
			USE_TORRENT="no"
			for toolchain in ${toolchains[@]}; do
				local toolchain_zip="${SRC}/cache/toolchain/${toolchain}"
				local toolchain_dir="${toolchain_zip%.tar.*}"
				if [[ ! -f "${toolchain_dir}/.download-complete" ]]; then
					download_and_verify "_toolchain" "${toolchain}"
					[[ ! -f "${toolchain_zip}" ]] && exit_with_error "Failed to download toolchain" "${toolchain}"

					display_alert "decompressing"
					pv -p -b -r -c -N "[ .... ] ${toolchain}" "${toolchain_zip}" | xz -dc | tar xp --xattrs --no-same-owner --overwrite
					if [[ $? -ne 0 ]]; then
						rm -rf "${toolchain_dir}"
						exit_with_error "Failed to decompress toolchain" "${toolchain}"
					fi

					touch "${toolchain_dir}/.download-complete"
					rm -rf "${toolchain_zip}"* # Also delete asc file
				fi
			done
			USE_TORRENT=${USE_TORRENT_STATUS}

			local existing_dirs=( $(ls -1 "${SRC}"/cache/toolchain) )
			for dir in ${existing_dirs[@]}; do
				local found=no
				for toolchain in ${toolchains[@]}; do
					[[ $dir == ${toolchain%.tar.*} ]] && found=yes
				done
				if [[ $found == no ]]; then
					display_alert "Removing obsolete toolchain" "$dir"
					rm -rf "${SRC}/cache/toolchain/${dir}"
				fi
			done
		else
			display_alert "Ignoring toolchains" "SKIP_EXTERNAL_TOOLCHAINS: ${SKIP_EXTERNAL_TOOLCHAINS}" "info"
		fi
	fi

  fi # check offline

	# enable arm binary format so that the cross-architecture chroot environment will work
	if [[ $KERNEL_ONLY != yes ]]; then
		modprobe -q binfmt_misc
		mountpoint -q /proc/sys/fs/binfmt_misc/ || mount binfmt_misc -t binfmt_misc /proc/sys/fs/binfmt_misc
		if [[ "$(arch)" != "aarch64" ]]; then
			test -e /proc/sys/fs/binfmt_misc/qemu-arm || update-binfmts --enable qemu-arm
			test -e /proc/sys/fs/binfmt_misc/qemu-aarch64 || update-binfmts --enable qemu-aarch64
		fi
	fi

	[[ ! -f "${USERPATCHES_PATH}"/customize-image.sh ]] && cp "${SRC}"/config/templates/customize-image.sh.template "${USERPATCHES_PATH}"/customize-image.sh

	if [[ ! -f "${USERPATCHES_PATH}"/README ]]; then
		rm -f "${USERPATCHES_PATH}"/readme.txt
		echo 'Please read documentation about customizing build configuration' > "${USERPATCHES_PATH}"/README
		echo 'https://www.armbian.com/using-armbian-tools/' >> "${USERPATCHES_PATH}"/README

		# create patches directory structure under USERPATCHES_PATH
		find "${SRC}"/patch -maxdepth 2 -type d ! -name . | sed "s%/.*patch%/$USERPATCHES_PATH%" | xargs mkdir -p
	fi

	# check free space (basic)
	local freespace=$(findmnt --target "${SRC}" -n -o AVAIL -b 2>/dev/null) # in bytes
	if [[ -n $freespace && $(( $freespace / 1073741824 )) -lt 10 ]]; then
		display_alert "Low free space left" "$(( $freespace / 1073741824 )) GiB" "wrn"
		# pause here since dialog-based menu will hide this message otherwise
		echo -e "Press \e[0;33m<Ctrl-C>\x1B[0m to abort compilation, \e[0;33m<Enter>\x1B[0m to ignore and continue"
		read
	fi
}




function get_urls()
{
	local catalog=$1
	local filename=$2

	case $catalog in
		toolchain)
			local CCODE=$(curl --silent --fail https://dl.armbian.com/geoip | jq '.continent.code' -r)
			local urls=(
				# "https://dl.armbian.com/_toolchain/${filename}"
				# "${ARMBIAN_MIRROR}/${filename}"

				$( curl --silent --fail  "https://dl.armbian.com/mirrors" \
					| jq -r "(${CCODE:+.${CCODE} // } .default) | .[]" \
					| sed "s#\$#/_toolchain/${filename}#"
				)
			)
			;;

		rootfs)
			local CCODE=$(curl --silent --fail  https://cache.armbian.com/geoip | jq '.continent.code' -r)
			local urls=(
				# "https://cache.armbian.com/rootfs/${ROOTFSCACHE_VERSION}/${filename}"

				$( curl --silent --fail  "https://cache.armbian.com/mirrors" \
					| jq -r "(${CCODE:+.${CCODE} // } .default) | .[]" \
					| sed "s#\$#/rootfs/${ROOTFSCACHE_VERSION}/${filename}#"
				)
			)
			;;

		*)
			exit_with_error "Unknown catalog" "$catalog" >&2
			return
			;;
	esac

	echo "${urls[@]}"
}




download_and_verify()
{

	local catalog=${1#_}
	local remotedir=$1
	local filename=$2
	local localdir=$SRC/cache/${remotedir//_}
	local dirname=${filename//.tar.xz}

	local keys=(
		"8F427EAF" # Linaro Toolchain Builder
		"9F0E78D5" # Igor Pecovnik
	)

	local aria2_options=(
		# Display
		--console-log-level=error
		--summary-interval=0
		--download-result=hide

		# Meta
		--server-stat-if="${SRC}/cache/.aria2/server_stats"
		--server-stat-of="${SRC}/cache/.aria2/server_stats"
		--dht-file-path="${SRC}/cache/.aria2/dht.dat"
		--rpc-save-upload-metadata=false
		--auto-save-interval=0

		# File
		--auto-file-renaming=false
		--allow-overwrite=true
		--file-allocation=trunc

		# Connection
		--disable-ipv6=$DISABLE_IPV6
		--connect-timeout=10
		--timeout=10
		--allow-piece-length-change=true
		--max-connection-per-server=2
		--lowest-speed-limit=500K

		# BT
		--seed-time=0
		--bt-stop-timeout=30
	)

        if [[ $DOWNLOAD_MIRROR == china ]]; then
			local server="https://mirrors.tuna.tsinghua.edu.cn/armbian-releases/"
		elif [[ $DOWNLOAD_MIRROR == bfsu ]]; then
			local server="https://mirrors.bfsu.edu.cn/armbian-releases/"
		else
			local server=${ARMBIAN_MIRROR}
        fi

	# rootfs has its own infra
	if [[ "${remotedir}" == "_rootfs" ]]; then
		local server="https://cache.armbian.com/"
		remotedir="rootfs/$ROOTFSCACHE_VERSION"
	fi

	# switch to china mirror if US timeouts
	timeout 10 curl --location --head --fail --silent ${server}${remotedir}/${filename} 2>&1 >/dev/null
	if [[ $? -ne 7 && $? -ne 22 && $? -ne 0 ]]; then
		display_alert "Timeout from $server" "retrying" "info"
		server="https://mirrors.tuna.tsinghua.edu.cn/armbian-releases/"

		# switch to another china mirror if tuna timeouts
		timeout 10 curl --location --head --fail --silent ${server}${remotedir}/${filename} 2>&1 >/dev/null
		if [[ $? -ne 7 && $? -ne 22 && $? -ne 0 ]]; then
			display_alert "Timeout from $server" "retrying" "info"
			server="https://mirrors.bfsu.edu.cn/armbian-releases/"
		fi
	fi

	# check if file exists on remote server before running aria2 downloader
	timeout 10 curl --location --head --fail --silent ${server}${remotedir}/${filename} 2>&1 >/dev/null
	[[ $? -ne 0 ]] && return

	cd "${localdir}" || exit

	# use local signature file
	if [[ -f "${SRC}/config/torrents/${filename}.asc" ]]; then
		local torrent="${SRC}/config/torrents/${filename}.torrent"
		ln -sf "${SRC}/config/torrents/${filename}.asc" "${localdir}/${filename}.asc"
	else
		# download signature file
		aria2c "${aria2_options[@]}" \
			--continue=false \
			--dir="${localdir}" --out="${filename}.asc" \
			$(get_urls "${catalog}" "${filename}.asc")

		local rc=$?
		if [[ $rc -ne 0 ]]; then
			# Except `not found`
			[[ $rc -ne 3 ]] && display_alert "Failed to download signature file. aria2 exit code:" "$rc" "wrn"
			return $rc
		fi

		[[ ${USE_TORRENT} == "yes" ]] \
		&& local torrent="$(get_urls "${catalog}" "${filename}.torrent")"
	fi

	# download torrent first
	if [[ ${USE_TORRENT} == "yes" ]]; then

		display_alert "downloading using torrent network" "$filename"
		aria2c "${aria2_options[@]}" \
			--follow-torrent=mem \
			--dir="${localdir}" \
			${torrent}

		# mark complete
		[[ $? -eq 0 ]] && touch "${localdir}/${filename}.complete"

	fi


	# direct download if torrent fails
	if [[ ! -f "${localdir}/${filename}.complete" ]]; then
		if [[ ! `timeout 10 curl --location --head --fail --silent ${server}${remotedir}/${filename} 2>&1 >/dev/null` ]]; then
			display_alert "downloading using http(s) network" "$filename"
			aria2c "${aria2_options[@]}" \
				--dir="${localdir}" --out="${filename}" \
				$(get_urls "${catalog}" "${filename}")

			# mark complete
			[[ $? -eq 0 ]] && touch "${localdir}/${filename}.complete" && echo ""

		fi
	fi

	if [[ -f ${localdir}/${filename}.asc ]]; then

		if grep -q 'BEGIN PGP SIGNATURE' "${localdir}/${filename}.asc"; then

			if [[ ! -d "${SRC}"/cache/.gpg ]]; then
				mkdir -p "${SRC}"/cache/.gpg
				chmod 700 "${SRC}"/cache/.gpg
				touch "${SRC}"/cache/.gpg/gpg.conf
				chmod 600 "${SRC}"/cache/.gpg/gpg.conf
			fi

			for key in "${keys[@]}"; do
				gpg --homedir "${SRC}/cache/.gpg" --no-permission-warning \
					--list-keys "${key}" >> "${DEST}/${LOG_SUBPATH}/output.log" 2>&1 \
				|| gpg --homedir "${SRC}/cache/.gpg" --no-permission-warning \
					${http_proxy:+--keyserver-options http-proxy="${http_proxy}"} \
					--keyserver "hkp://keyserver.ubuntu.com:80" \
					--recv-keys "${key}" >> "${DEST}/${LOG_SUBPATH}/output.log" 2>&1 \
				|| exit_with_error "Failed to recieve key" "${key}"
			done

			gpg --homedir "${SRC}"/cache/.gpg --no-permission-warning --trust-model always \
				-q --verify "${localdir}/${filename}.asc" >> "${DEST}/${LOG_SUBPATH}/output.log" 2>&1
			[[ ${PIPESTATUS[0]} -eq 0 ]] && verified=true && display_alert "Verified" "PGP" "info"

		else

			md5sum -c --status "${localdir}/${filename}.asc" && verified=true && display_alert "Verified" "MD5" "info"

		fi

		if [[ $verified != true ]]; then
			exit_with_error "verification failed"
		fi

	fi
}




show_developer_warning()
{
	local temp_rc
	temp_rc=$(mktemp)
	cat <<-'EOF' > "${temp_rc}"
	screen_color = (WHITE,RED,ON)
	EOF
	local warn_text="You are switching to the \Z1EXPERT MODE\Zn

	This allows building experimental configurations that are provided
	\Z1AS IS\Zn to developers and expert users,
	\Z1WITHOUT ANY RESPONSIBILITIES\Zn from the Armbian team:

	- You are using these configurations \Z1AT YOUR OWN RISK\Zn
	- Bug reports related to the dev kernel, CSC, WIP and EOS boards
	\Z1will be closed without a discussion\Zn
	- Forum posts related to dev kernel, CSC, WIP and EOS boards
	should be created in the \Z2\"Community forums\"\Zn section
	"
	DIALOGRC=$temp_rc dialog --title "Expert mode warning" --backtitle "${backtitle}" --colors --defaultno --no-label "I do not agree" \
		--yes-label "I understand and agree" --yesno "$warn_text" "${TTY_Y}" "${TTY_X}"
	[[ $? -ne 0 ]] && exit_with_error "Error switching to the expert mode"
	SHOW_WARNING=no
}

# is a formatted output of the values of variables
# from the list at the place of the function call.
#
# The LOG_OUTPUT_FILE variable must be defined in the calling function
# before calling the `show_checklist_variables` function and unset after.
#
show_checklist_variables ()
{
	local checklist=$*
	local var pval
	local log_file=${LOG_OUTPUT_FILE:-"${SRC}"/output/${LOG_SUBPATH}/trash.log}
	local _line=${BASH_LINENO[0]}
	local _function=${FUNCNAME[1]}
	local _file=$(basename "${BASH_SOURCE[1]}")

	echo -e "Show variables in function: $_function" "[$_file:$_line]\n" >>$log_file

	for var in $checklist;do
		eval pval=\$$var
		echo -e "\n$var =:" >>$log_file
		if [ $(echo "$pval" | awk -F"/" '{print NF}') -ge 4 ];then
			printf "%s\n" $pval >>$log_file
		else
			printf "%-30s %-30s %-30s %-30s\n" $pval >>$log_file
		fi
	done
}
