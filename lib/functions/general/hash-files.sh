function calculate_hash_for_all_files_in_dirs() {
	declare -a dirs_to_hash=("$@")
	declare -a files_to_hash=()
	for dir in "${dirs_to_hash[@]}"; do
		# skip if dir doesn't exist...
		if [[ ! -d "${dir}" ]]; then
			display_alert "calculate_hash_for_all_files_in_dirs" "skipping non-existent dir \"${dir}\"" "warn"
			continue
		fi
		declare found_files="no"
		# shellcheck disable=SC2044 # lets expand... # -L: follow symlinks
		for file in $(find -L "${dir}" -type f); do
			files_to_hash+=("${file}")
			found_files="yes"
		done
		if [[ "${found_files}" == "no" ]]; then
			display_alert "calculate_hash_for_all_files_in_dirs" "empty dir \"${dir}\"" "debug"
		fi
	done

	#display_alert "calculate_hash_for_all_files_in_dirs" "files_to_hash_sorted: ${#files_to_hash_sorted[@]}" "warn"
	#display_alert "calculate_hash_for_all_files_in_dirs" "files_to_hash_sorted: ${files_to_hash_sorted[*]}" "warn"

	calculate_hash_for_files "${files_to_hash[@]}"
}

function calculate_hash_for_files() {
	hash_files="undetermined" # outer scope

	# relativize the files to SRC
	declare -a files_to_hash=("$@")
	declare -a files_to_hash_relativized=()
	for file in "${files_to_hash[@]}"; do
		# remove the SRC/ from the file name
		file="${file#${SRC}/}"
		files_to_hash_relativized+=("${file}")
	done

	# sort the array files_to_hash; use sort and readfile
	declare -a files_to_hash_sorted
	mapfile -t files_to_hash_sorted < <(for one in "${files_to_hash_relativized[@]}"; do echo "${one}"; done | LC_ALL=C sort -h) # "human" sorting

	display_alert "calculate_hash_for_files:" "files_to_hash_sorted: ${files_to_hash_sorted[*]}" "debug"
	declare full_hash
	full_hash="$(cd "${SRC}" && sha256sum "${files_to_hash_sorted[@]}")"
	hash_files="$(echo "${full_hash}" | sha256sum | cut -d' ' -f1)" # hash of hashes
	hash_files="${hash_files:0:16}"                                 # shorten it to 16 characters

	if [[ "${SHOW_DEBUG}" == "yes" ]]; then
		display_alert "Hash for files:" "$hash_files" "debug"
		display_alert "Full hash input for files:" "\n${full_hash}\n" "debug"
	fi
}
