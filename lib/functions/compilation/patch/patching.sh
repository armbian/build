# advanced_patch <dest> <family> <board> <target> <branch> <description>
#
# parameters:
# <dest>: u-boot, kernel, atf
# <family>: u-boot: u-boot, u-boot-neo; kernel: sun4i-default, sunxi-next, ...
# <board>: cubieboard, cubieboard2, cubietruck, ...
# <target>: optional subdirectory
# <description>: additional description text
#
# priority:
# $USERPATCHES_PATH/<dest>/<family>/target_<target>
# $USERPATCHES_PATH/<dest>/<family>/board_<board>
# $USERPATCHES_PATH/<dest>/<family>/branch_<branch>
# $USERPATCHES_PATH/<dest>/<family>
# $SRC/patch/<dest>/<family>/target_<target>
# $SRC/patch/<dest>/<family>/board_<board>
# $SRC/patch/<dest>/<family>/branch_<branch>
# $SRC/patch/<dest>/<family>
#
advanced_patch() {
	local dest=$1
	local family=$2
	local board=$3
	local target=$4
	local branch=$5
	local description=$6

	display_alert "Started patching process for" "$dest $description" "info"
	display_alert "Looking for user patches in" "userpatches/$dest/$family" "info"

	local names=()
	local dirs=(
		"$USERPATCHES_PATH/$dest/$family/target_${target}:[\e[33mu\e[0m][\e[34mt\e[0m]"
		"$USERPATCHES_PATH/$dest/$family/board_${board}:[\e[33mu\e[0m][\e[35mb\e[0m]"
		"$USERPATCHES_PATH/$dest/$family/branch_${branch}:[\e[33mu\e[0m][\e[33mb\e[0m]"
		"$USERPATCHES_PATH/$dest/$family:[\e[33mu\e[0m][\e[32mc\e[0m]"
		"$SRC/patch/$dest/$family/target_${target}:[\e[32ml\e[0m][\e[34mt\e[0m]"
		"$SRC/patch/$dest/$family/board_${board}:[\e[32ml\e[0m][\e[35mb\e[0m]"
		"$SRC/patch/$dest/$family/branch_${branch}:[\e[32ml\e[0m][\e[33mb\e[0m]"
		"$SRC/patch/$dest/$family:[\e[32ml\e[0m][\e[32mc\e[0m]"
	)
	local links=()

	# required for "for" command
	shopt -s nullglob dotglob
	# get patch file names
	for dir in "${dirs[@]}"; do
		for patch in ${dir%%:*}/*.patch; do
			names+=($(basename "${patch}"))
		done
		# add linked patch directories
		if [[ -d ${dir%%:*} ]]; then
			local findlinks
			findlinks=$(find "${dir%%:*}" -maxdepth 1 -type l -print0 2>&1 | xargs -0)
			[[ -n $findlinks ]] && readarray -d '' links < <(find "${findlinks}" -maxdepth 1 -type f -follow -print -iname "*.patch" -print | grep "\.patch$" | sed "s|${dir%%:*}/||g" 2>&1)
		fi
	done
	# merge static and linked
	names=("${names[@]}" "${links[@]}")
	# remove duplicates
	local names_s=($(echo "${names[@]}" | tr ' ' '\n' | LC_ALL=C sort -u | tr '\n' ' '))
	# apply patches
	for name in "${names_s[@]}"; do
		for dir in "${dirs[@]}"; do
			if [[ -f ${dir%%:*}/$name ]]; then
				if [[ -s ${dir%%:*}/$name ]]; then
					process_patch_file "${dir%%:*}/$name" "${dir##*:}"
				else
					display_alert "* ${dir##*:} $name" "skipped"
				fi
				break # next name
			fi
		done
	done
}

# process_patch_file <file> <description>
#
# parameters:
# <file>: path to patch file
# <status>: additional status text
#
process_patch_file() {
	local patch=$1
	local status=$2
	local patch_date

	# get the modification date of the patch. make it not less than MIN_PATCH_AGE, if set.
	# [[CC]YY]MMDDhhmm[.ss] time format
	patch_date=$(get_file_modification_time "${patch}")

	# detect and remove files which patch will create
	lsdiff -s --strip=1 "${patch}" | grep '^+' | awk '{print $2}' | xargs -I % sh -c 'rm -f %'

	# store an array of the files that patch will modify, we'll set their modification times after the fact
	declare -a patched_files
	mapfile -t patched_files < <(lsdiff -s --strip=1 "${patch}" | awk '{print $2}')

	# @TODO: try patching with `git am` first, so git contains the patch commit info/msg. -- For future git-based hashing.
	# shellcheck disable=SC2015 # noted, thanks. I need to handle exit code here.
	patch --batch -p1 -N < "${patch}" && {
		set_files_modification_time "${patch_date}" "${patched_files[@]}"
		display_alert "* $status $(basename "${patch}")" "" "info"
	} || {
		display_alert "* $status $(basename "${patch}")" "failed" "wrn"
		[[ $EXIT_PATCHING_ERROR == yes ]] && exit_with_error "Aborting due to" "EXIT_PATCHING_ERROR"
	}
	return 0 # short-circuit above, avoid exiting with error
}
function new_process_patch_file() {
	local patch="$1"                           # full filename
	local status="$2"                          # message, may contain ANSI
	local relative_patch="${patch##"${SRC}"/}" # ${FOO##prefix} remove prefix from FOO

	# report_fashtash_should_execute is report_fasthash returns true only if we're supposed to apply the patch on disk.
	if report_fashtash_should_execute file "${patch}" "Apply patch ${relative_patch}"; then
		# detect and remove files which patch will create
		lsdiff -s --strip=1 "${patch}" | grep '^+' | awk '{print $2}' | xargs -I % sh -c 'rm -f %'

		# @TODO: try patching with `git am` first, so git contains the patch commit info/msg. -- For future git-based hashing.
		# shellcheck disable=SC2015 # noted, thanks. I need to handle exit code here.
		patch --batch -p1 -N < "${patch}" && {
			display_alert "* ${status} ${relative_patch}" "" "info" || true
		} || {
			display_alert "* ${status} ${relative_patch}" "failed" "wrn"
			[[ $EXIT_PATCHING_ERROR == yes ]] && exit_with_error "Aborting due to EXIT_PATCHING_ERROR" "Patch ${relative_patch} failed"
		}
		mark_fasthash_done # will do git commit, associate fasthash to real hash.
	fi

	return 0 # short-circuit above, avoid exiting with error
}

# apply_patch_series <target dir> <full path to series_file_full_path file>
apply_patch_series() {
	local target_dir="${1}"
	local series_file_full_path="${2}"
	local included_list skip_list skip_count counter=1 base_dir
	base_dir="$(dirname "${series_file_full_path}")"
	included_list="$(awk '$0 !~ /^#.*|^-.*|^$/' "${series_file_full_path}")"
	included_count=$(echo -n "${included_list}" | wc -w)
	skip_list="$(awk '$0 ~ /^-.*/{print $NF}' "${series_file_full_path}")"
	skip_count=$(echo -n "${skip_list}" | wc -w)
	display_alert "apply a series of " "[$(echo -n "$included_list" | wc -w)] patches" "info"
	[[ ${skip_count} -gt 0 ]] && display_alert "skipping" "[${skip_count}] patches" "warn"
	cd "${target_dir}" || exit 1

	for p in $included_list; do
		process_patch_file "${base_dir}/${p}" "${counter}/${included_count}"
		counter=$((counter + 1))
	done
	display_alert "done applying patch series " "[$(echo -n "$included_list" | wc -w)] patches" "info"
}

userpatch_create() {
	# create commit to start from clean source
	git add .
	git -c user.name='Armbian User' -c user.email='user@example.org' commit -q -m "Cleaning working copy"

	local patch="$DEST/patch/$1-$LINUXFAMILY-$BRANCH.patch"

	# apply previous user debug mode created patches
	if [[ -f $patch ]]; then
		display_alert "Applying existing $1 patch" "$patch" "wrn" && patch --batch --silent -p1 -N < "${patch}"
		# read title of a patch in case Git is configured
		if [[ -n $(git config user.email) ]]; then
			COMMIT_MESSAGE=$(cat "${patch}" | grep Subject | sed -n -e '0,/PATCH/s/.*PATCH]//p' | xargs)
			display_alert "Patch name extracted" "$COMMIT_MESSAGE" "wrn"
		fi
	fi

	# prompt to alter source
	display_alert "Make your changes in this directory:" "$(pwd)" "wrn"
	display_alert "Press <Enter> after you are done" "waiting" "wrn"
	read -r < /dev/tty
	tput cuu1
	git add .
	# create patch out of changes
	if ! git diff-index --quiet --cached HEAD; then
		# If Git is configured, create proper patch and ask for a name
		if [[ -n $(git config user.email) ]]; then
			display_alert "Add / change patch name" "$COMMIT_MESSAGE" "wrn"
			read -e -p "Patch description: " -i "$COMMIT_MESSAGE" COMMIT_MESSAGE
			[[ -z "$COMMIT_MESSAGE" ]] && COMMIT_MESSAGE="Patching something"
			git commit -s -m "$COMMIT_MESSAGE"
			git format-patch -1 HEAD --stdout --signature="Created with Armbian build tools https://github.com/armbian/build" > "${patch}"
			PATCHFILE=$(git format-patch -1 HEAD)
			rm $PATCHFILE # delete the actual file
			# create a symlink to have a nice name ready
			find $DEST/patch/ -type l -delete # delete any existing
			ln -sf $patch $DEST/patch/$PATCHFILE
		else
			git diff --staged > "${patch}"
		fi
		display_alert "You will find your patch here:" "$patch" "info"
	else
		display_alert "No changes found, skipping patch creation" "" "wrn"
	fi
	git reset --soft HEAD~
	for i in {3..1..1}; do echo -n "$i." && sleep 1; done
}
