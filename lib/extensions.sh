#!/usr/bin/env bash
# global variables managing the state of the extension manager. treat as private.
declare -A extension_function_info                # maps a function name to a string with KEY=VALUEs information about the defining extension
declare -i initialize_extension_manager_counter=0 # how many times has the extension manager initialized?
declare -A defined_hook_point_functions           # keeps a map of hook point functions that were defined and their extension info
declare -A hook_point_function_trace_sources      # keeps a map of hook point functions that were actually called and their source
declare -A hook_point_function_trace_lines        # keeps a map of hook point functions that were actually called and their source
declare fragment_manager_cleanup_file             # this is a file used to cleanup the manager's produced functions, for build_all_ng

# This is a helper function for calling hooks.
# It follows the pattern long used in the codebase for hook-like behaviour:
#    [[ $(type -t name_of_hook_function) == function ]] && name_of_hook_function
# but with the following added behaviors:
# 1) it allows for many arguments, and will treat each as a hook point.
#    this allows for easily kept backwards compatibility when renaming hooks, for example.
# 2) it will read the stdin and assume it's (Markdown) documentation for the hook point.
#    combined with heredoc in the call site, it allows for "inline" documentation about the hook
# notice: this is not involved in how the hook functions came to be. read below for that.
call_extension_method() {
	# First, consume the stdin and write metadata about the call.
	write_hook_point_metadata "$@"

	# @TODO: hack to handle stdin again, possibly with '< /dev/tty'

	# Then a sanity check, hook points should only be invoked after the manager has initialized.
	if [[ ${initialize_extension_manager_counter} -lt 1 ]]; then
		display_alert "Extension problem" "Call to call_extension_method() ($*: in ${BASH_SOURCE[1]- $(get_extension_hook_stracktrace "${BASH_SOURCE[*]}" "${BASH_LINENO[*]}")}) before extension manager is initialized." "err"
	fi

	# Log the hook call. Users might be wondering what/when is a good hook point to use, and this is visual aid.
	display_alert "Extension Method '${1}' being called from" "$(get_extension_hook_stracktrace "${BASH_SOURCE[*]}" "${BASH_LINENO[*]}")" "extensions"

	# Then call the hooks, if they are defined.
	for hook_name in "$@"; do
		display_alert "Extension Method being called: ${hook_name}" "hook: ${hook_name}" "extensions"
		if [[ $(type -t ${hook_name} || true) == function ]]; then
			${hook_name}
		fi
	done
}

# what this does is a lot of bash mumbo-jumbo to find all board-,family-,config- or user-defined hook points.
# the meat of this is 'compgen -A function', which is bash builtin that lists all defined functions.
# it will then compose a full hook point (function) that calls all the implementing hooks.
# this centralized function will then be called by the regular Armbian build system, which is oblivious to how
# it came to be. (although it is encouraged to call hook points via call_extension_method() above)
# to avoid hard coding the list of hook-points (eg: user_config, image_tweaks_pre_customize, etc) we use
# a marker in the function names, namely "__" (two underscores) to determine the hook point.
initialize_extension_manager() {
	# before starting, auto-add extensions specified (eg, on the command-line) via the ENABLE_EXTENSIONS env var. Do it only once.
	[[ ${initialize_extension_manager_counter} -lt 1 ]] && [[ "${ENABLE_EXTENSIONS}" != "" ]] && {
		local auto_extension
		for auto_extension in $(echo "${ENABLE_EXTENSIONS}" | tr "," " "); do
			ENABLE_EXTENSION_TRACE_HINT="ENABLE_EXTENSIONS -> " enable_extension "${auto_extension}"
		done
	}

	# This marks the manager as initialized, no more extensions are allowed to load after this.
	export initialize_extension_manager_counter=$((initialize_extension_manager_counter + 1))

	# Extensions has its own work/tmp directory, defined by do_main_configuration, with build UUID. We just create it here, unless told not to.
	display_alert "Initializing EXTENSION_MANAGER_TMP_DIR" "${EXTENSION_MANAGER_TMP_DIR}" "debug"
	mkdir -p "${EXTENSION_MANAGER_TMP_DIR}"

	# Metadata about hook_point_calls. This is used to generate the documentation / example extensions
	[[ "${WRITE_EXTENSIONS_METADATA:-yes}" == "no" ]] && echo -n "" > "${EXTENSION_MANAGER_TMP_DIR}/hook_point_calls.txt"

	# Add trap handler to cleanup and not leave garbage behind when exiting.
	add_cleanup_handler cleanup_handler_extensions

	# log whats happening; extensions has its own log level. enable with SHOW_EXTENSIONS=yes
	display_alert "Initializing EXTENSION_MANAGER" "initializing extension manager" "extensions"

	# this is the all-important separator.
	local hook_extension_delimiter="__"

	# list all defined functions. filter only the ones that have the delimiter. get only the part before the delimiter.
	# sort them, and make them unique. the sorting is required for uniq to work, and does not affect the ordering of execution.
	# get them on a single line, space separated.
	local all_hook_points
	all_hook_points="$(compgen -A function | grep "${hook_extension_delimiter}" | awk -F "${hook_extension_delimiter}" '{print $1}' | sort | uniq | xargs echo -n)"

	declare -i hook_points_counter=0 hook_functions_counter=0 hook_point_functions_counter=0

	# initialize the cleanups file.
	fragment_manager_cleanup_file="${EXTENSION_MANAGER_TMP_DIR}/extension_function_cleanup.sh"
	echo "# cleanups: " > "${fragment_manager_cleanup_file}"

	local FUNCTION_SORT_OPTIONS="--general-numeric-sort --ignore-case" #  --random-sort could be used to introduce chaos
	local hook_point=""
	# now loop over the hook_points.
	for hook_point in ${all_hook_points}; do
		display_alert "Extensions hook point" "${hook_point}" "extensions"

		# check if the hook point is already defined as a function.
		# that can happen for example with user_config(), that can be implemented itself directly by a userpatches config.
		# for now, just warn, but we could devise a way to actually integrate it in the call list.
		# or: advise the user to rename their user_config() function to something like user_config__make_it_awesome()
		local existing_hook_point_function
		existing_hook_point_function="$(compgen -A function | grep "^${hook_point}\$" || true)"
		if [[ "${existing_hook_point_function}" == "${hook_point}" ]]; then
			display_alert "Extensions final sorted realnames" "${hook_point_functions}" "extensionstrace"
			display_alert "Extension conflict" "function ${hook_point} already defined! ignoring functions: $(compgen -A function | grep "^${hook_point}${hook_extension_delimiter}")" "wrn"
			continue
		fi

		# for each hook_point, obtain the list of implementing functions.
		# the sort order here is (very) relevant, since it determines final execution order.
		# so the name of the functions actually determine the ordering.
		local hook_point_functions hook_point_functions_pre_sort hook_point_functions_sorted_by_sort_id

		# Sorting. Multiple extensions (or even the same extension twice) can implement the same hook point
		# as long as they have different function names (the part after the double underscore __).
		# the order those will be called depends on the name; eg:
		# 'hook_point__033_be_awesome()' would be caller sooner than 'hook_point__799_be_even_more_awesome()'
		# independent from where they were defined or in which order the extensions containing them were added.
		# since requiring specific ordering could hamper portability, we reward extension authors who
		# don't mind ordering for writing just: 'hook_point__be_just_awesome()' which is automatically rewritten
		# as 'hook_point__500_be_just_awesome()'.
		# extension authors who care about ordering can use the 3-digit number, and use the context variables
		# HOOK_ORDER and HOOK_POINT_TOTAL_FUNCS to confirm in which order they're being run.

		# gather the real names of the functions (after the delimiter).
		hook_point_functions_pre_sort="$(compgen -A function | grep "^${hook_point}${hook_extension_delimiter}" | awk -F "${hook_extension_delimiter}" '{print $2}' | xargs echo -n)"
		display_alert "Extensions hook_point_functions_pre_sort" "${hook_point_functions_pre_sort}" "extensionstrace"

		# add "500_" to the names of function that do NOT start with a number.
		# keep a reference from the new names to the old names (we'll sort on the new, but invoke the old)
		declare -A hook_point_functions_sortname_to_realname
		declare -A hook_point_functions_realname_to_sortname
		for hook_point_function_realname in ${hook_point_functions_pre_sort}; do
			local sort_id="${hook_point_function_realname}"
			[[ ! $sort_id =~ ^[0-9] ]] && sort_id="500_${sort_id}"
			hook_point_functions_sortname_to_realname[${sort_id}]="${hook_point_function_realname}"
			hook_point_functions_realname_to_sortname[${hook_point_function_realname}]="${sort_id}"
		done

		# actually sort the sort_id's...
		# shellcheck disable=SC2086
		hook_point_functions_sorted_by_sort_id="$(echo "${hook_point_functions_realname_to_sortname[*]}" | tr " " "\n" | LC_ALL=C sort ${FUNCTION_SORT_OPTIONS} | xargs echo -n)"
		display_alert "Extensions hook_point_functions_sorted_by_sort_id" "${hook_point_functions_sorted_by_sort_id}" "extensionstrace"

		# then map back to the real names, keeping the order..
		hook_point_functions=""
		for hook_point_function_sortname in ${hook_point_functions_sorted_by_sort_id}; do
			hook_point_functions="${hook_point_functions} ${hook_point_functions_sortname_to_realname[${hook_point_function_sortname}]}"
		done
		# shellcheck disable=SC2086
		hook_point_functions="$(echo -n ${hook_point_functions})"
		display_alert "Extensions hook_point_functions (final sorted realnames)" "${hook_point_functions}" "extensionstrace"

		hook_point_functions_counter=0
		hook_points_counter=$((hook_points_counter + 1))

		# determine the variables we'll pass to the hook function during execution.
		# this helps the extension author create extensions that are portable between userpatches and official Armbian.
		# shellcheck disable=SC2089
		local common_function_vars="HOOK_POINT=\"${hook_point}\""

		# loop over the functions for this hook_point (keep a total for the hook point and a grand running total)
		for hook_point_function in ${hook_point_functions}; do
			hook_point_functions_counter=$((hook_point_functions_counter + 1))
			hook_functions_counter=$((hook_functions_counter + 1))
		done
		common_function_vars="${common_function_vars} HOOK_POINT_TOTAL_FUNCS=\"${hook_point_functions_counter}\""

		display_alert "Extensions hook_point: ${hook_point} will run ${hook_point_functions_counter} functions" "${hook_point_functions_counter}" "extensions"
		local temp_source_file_for_hook_point="${EXTENSION_MANAGER_TMP_DIR}/extension_function_definition.sh"

		hook_point_functions_loop_counter=0

		# prepare the cleanup for the function, so we can remove our mess at the end of the build.
		cat <<- FUNCTION_CLEANUP_FOR_HOOK_POINT >> "${fragment_manager_cleanup_file}"
			unset ${hook_point}
		FUNCTION_CLEANUP_FOR_HOOK_POINT

		# now compose a function definition. notice the heredoc. it will be written to tmp file, logged, then sourced.
		# theres a lot of opportunities here, but for now I keep it simple:
		# - execute functions in the order defined by ${hook_point_functions} above
		# - define call-specific environment variables, to help extension authors to write portable extensions (eg: EXTENSION_DIR)
		cat <<- FUNCTION_DEFINITION_HEADER > "${temp_source_file_for_hook_point}"
			${hook_point}() {
				display_alert "Extension-managed hook starting '${hook_point}': will run ${hook_point_functions_counter} functions" "${hook_point_functions}" "extensionstrace"
		FUNCTION_DEFINITION_HEADER

		for hook_point_function in ${hook_point_functions}; do
			hook_point_functions_loop_counter=$((hook_point_functions_loop_counter + 1))

			# store the full name in a hash, so we can track which were actually called later.
			defined_hook_point_functions["${hook_point}${hook_extension_delimiter}${hook_point_function}"]="DEFINED=yes ${extension_function_info["${hook_point}${hook_extension_delimiter}${hook_point_function}"]}"

			# prepare the call context
			local hook_point_function_variables="${common_function_vars}" # start with common vars... (eg: HOOK_POINT_TOTAL_FUNCS)
			# add the contextual extension info for the function (eg, EXTENSION_DIR)
			hook_point_function_variables="${hook_point_function_variables} ${extension_function_info["${hook_point}${hook_extension_delimiter}${hook_point_function}"]}"
			# add the current execution counter, so the extension author can know in which order it is being actually called
			hook_point_function_variables="${hook_point_function_variables} HOOK_ORDER=\"${hook_point_functions_loop_counter}\""

			# add it to our (not the call site!) environment. if we export those in the call site, the stack is corrupted.
			eval "${hook_point_function_variables}"

			# output the call, passing arguments, and also logging the output to the extensions log.
			# attention: don't pipe here (eg, capture output), otherwise hook function cant modify the environment (which is mostly the point)
			cat <<- FUNCTION_DEFINITION_CALLSITE >> "${temp_source_file_for_hook_point}"
				hook_point_function_trace_sources["${hook_point}${hook_extension_delimiter}${hook_point_function}"]="\${BASH_SOURCE[*]}"
				hook_point_function_trace_lines["${hook_point}${hook_extension_delimiter}${hook_point_function}"]="\${BASH_LINENO[*]}"
				display_alert "Extension Method ${hook_point}" "${hook_point_functions_loop_counter}/${hook_point_functions_counter} (ext:${EXTENSION:-built-in}) ${hook_point_function}" "extensionstrace"
				display_alert "Extension-managed hook starting ${hook_point_functions_loop_counter}/${hook_point_functions_counter}" "${hook_point}${hook_extension_delimiter}${hook_point_function}" "extensionstrace"
				${hook_point_function_variables} ${hook_point}${hook_extension_delimiter}${hook_point_function} "\$@"
				display_alert "Extension-managed hook finished ${hook_point_functions_loop_counter}/${hook_point_functions_counter}" "${hook_point}${hook_extension_delimiter}${hook_point_function}" "extensionstrace"
			FUNCTION_DEFINITION_CALLSITE

			# output the cleanup for the implementation as well.
			cat <<- FUNCTION_CLEANUP_FOR_HOOK_POINT_IMPLEMENTATION >> "${fragment_manager_cleanup_file}"
				unset ${hook_point}${hook_extension_delimiter}${hook_point_function}
			FUNCTION_CLEANUP_FOR_HOOK_POINT_IMPLEMENTATION

			# unset extension vars for the next loop.
			unset EXTENSION EXTENSION_DIR EXTENSION_FILE EXTENSION_ADDED_BY
		done

		cat <<- FUNCTION_DEFINITION_FOOTER >> "${temp_source_file_for_hook_point}"
			display_alert "Extension-managed hook ending '${hook_point}': completed" "${hook_point}" "extensionstrace"
			} # end ${hook_point}() function
		FUNCTION_DEFINITION_FOOTER

		# unsets, lest the next loop inherits them
		unset hook_point_functions hook_point_functions_sortname_to_realname hook_point_functions_realname_to_sortname

		# source the generated function.
		# shellcheck disable=SC1090
		source "${temp_source_file_for_hook_point}"

		rm -f "${temp_source_file_for_hook_point}"
	done

	# Dont show any output until we have more than 1 hook function (we implement one already, below)
	[[ ${hook_functions_counter} -gt 0 ]] &&
		display_alert "Extension manager" "processed ${hook_points_counter} Extension Methods calls and ${hook_functions_counter} Extension Method implementations" "info"

	return 0 # exit with success, short-circuit above.
}

cleanup_extension_manager() {
	if [[ -f "${fragment_manager_cleanup_file}" ]]; then
		display_alert "Cleaning up" "extension manager" "info"
		# shellcheck disable=SC1090 # dynamic source, thanks, shellcheck
		source "${fragment_manager_cleanup_file}" # this will unset all the functions.
		rm -f "${fragment_manager_cleanup_file}"  # also remove the file.
		unset fragment_manager_cleanup_file       # and unset the var.
	fi

	# reset/unset the variables used
	initialize_extension_manager_counter=0
	unset extension_function_info defined_hook_point_functions hook_point_function_trace_sources hook_point_function_trace_lines fragment_manager_cleanup_file
}

function cleanup_handler_extensions() {
	display_alert "yeah the extensions trap handler..." "cleanup_handler_extensions" "cleanup"
	cleanup_extension_manager

	# cleanup our tmpdir.
	if [[ -d "${EXTENSION_MANAGER_TMP_DIR}" ]]; then
		rm -rf "${EXTENSION_MANAGER_TMP_DIR}"
	fi
	unset EXTENSION_MANAGER_TMP_DIR
}

# why not eat our own dog food?
# process everything that happened during extension related activities
# and write it to the log. also, move the log from the .tmp dir to its
# final location. this will make run_after_build() "hot" (eg, emit warnings)
run_after_build__999_finish_extension_manager() {
	# export these maps, so the hook can access them and produce useful stuff.
	export defined_hook_point_functions hook_point_function_trace_sources

	# eat our own dog food, pt2.
	call_extension_method "extension_metadata_ready" <<- 'EXTENSION_METADATA_READY'
		*meta-Meta time!*
		Implement this hook to work with/on the meta-data made available by the extension manager.
		Interesting stuff to process:
		- `"${EXTENSION_MANAGER_TMP_DIR}/hook_point_calls.txt"` contains a list of all hook points called, in order.
		- For each hook_point in the list, more files will have metadata about that hook point.
		  - `${EXTENSION_MANAGER_TMP_DIR}/hook_point.orig.md` contains the hook documentation at the call site (inline docs), hopefully in Markdown format.
		  - `${EXTENSION_MANAGER_TMP_DIR}/hook_point.compat` contains the compatibility names for the hooks.
		  - `${EXTENSION_MANAGER_TMP_DIR}/hook_point.exports` contains _exported_ environment variables.
		  - `${EXTENSION_MANAGER_TMP_DIR}/hook_point.vars` contains _all_ environment variables.
		- `${defined_hook_point_functions}` is a map of _all_ the defined hook point functions and their extension information.
		- `${hook_point_function_trace_sources}` is a map of all the hook point functions _that were really called during the build_ and their BASH_SOURCE information.
		- `${hook_point_function_trace_lines}` is the same, but BASH_LINENO info.
		After this hook is done, the `${EXTENSION_MANAGER_TMP_DIR}` will be removed.
	EXTENSION_METADATA_READY
}

# This is called by call_extension_method(). To say the truth, this should be in an extension. But then it gets too meta for anyone's head.
write_hook_point_metadata() {
	# Dont do anything if told not to.
	[[ "${WRITE_EXTENSIONS_METADATA:-yes}" == "no" ]] && return 0

	local main_hook_point_name="$1"

	[[ ! -d "${EXTENSION_MANAGER_TMP_DIR}" ]] && mkdir -p "${EXTENSION_MANAGER_TMP_DIR}"
	cat - > "${EXTENSION_MANAGER_TMP_DIR}/${main_hook_point_name}.orig.md" # Write the hook point documentation received via stdin to a tmp file for later processing.
	shift
	echo -n "$@" > "${EXTENSION_MANAGER_TMP_DIR}/${main_hook_point_name}.compat"       # log the 2nd+ arguments too (those are the alternative/compatibility names), separate file.
	compgen -A export > "${EXTENSION_MANAGER_TMP_DIR}/${main_hook_point_name}.exports" # capture the exported env vars.
	compgen -A variable > "${EXTENSION_MANAGER_TMP_DIR}/${main_hook_point_name}.vars"  # capture all env vars.

	# add to the list of hook points called, in order.
	echo "${main_hook_point_name}" >> "${EXTENSION_MANAGER_TMP_DIR}/hook_point_calls.txt"
}

# can be called by board, family, config or user to make sure an extension is included.
# single argument is the extension name.
# will look for it in /userpatches/extensions first.
# if not found there will look in /extensions
# if not found will exit 17
declare -i enable_extension_recurse_counter=0
declare -a enable_extension_recurse_stack
enable_extension() {
	local extension_name="$1"
	local extension_dir extension_file extension_file_in_dir extension_floating_file
	local stacktrace

	if [[ "${SHOW_DEBUG}" == "yes" ]]; then
		stacktrace="${ENABLE_EXTENSION_TRACE_HINT}$(get_extension_hook_stracktrace "${BASH_SOURCE[*]}" "${BASH_LINENO[*]}")"
		display_alert "Enabling extension" "${extension_name} :: added by ${stacktrace}" "debug"
	else
		[[ "${enable_extension_quiet:-no}" != "yes" ]] && display_alert "Enabling extension" "${extension_name}" ""
	fi

	# first a check, has the extension manager already initialized? then it is too late to enable_extension(). bail.
	if [[ ${initialize_extension_manager_counter} -gt 0 ]]; then
		stacktrace="${ENABLE_EXTENSION_TRACE_HINT}$(get_extension_hook_stracktrace "${BASH_SOURCE[*]}" "${BASH_LINENO[*]}")"
		display_alert "Extension problem" "already initialized -- too late to add '${extension_name}' (trace: ${stacktrace})" "err"
		exit 2
	fi

	# check the counter. if recurring, add to the stack and return success
	if [[ $enable_extension_recurse_counter -gt 1 ]]; then
		enable_extension_recurse_stack+=("${extension_name}")
		return 0
	fi

	# increment the counter
	enable_extension_recurse_counter=$((enable_extension_recurse_counter + 1))

	# there are many opportunities here. too many, actually. let userpatches override just some functions, etc.
	for extension_base_path in "${SRC}/userpatches/extensions" "${SRC}/extensions"; do
		extension_dir="${extension_base_path}/${extension_name}"
		extension_file_in_dir="${extension_dir}/${extension_name}.sh"
		extension_floating_file="${extension_base_path}/${extension_name}.sh"

		if [[ -d "${extension_dir}" ]] && [[ -f "${extension_file_in_dir}" ]]; then
			extension_file="${extension_file_in_dir}"
			break
		elif [[ -f "${extension_floating_file}" ]]; then
			extension_dir="${extension_base_path}" # this is misleading. only directory-based extensions should have this.
			extension_file="${extension_floating_file}"
			break
		fi
	done

	# After that, we should either have extension_file and extension_dir, or throw.
	if [[ ! -f "${extension_file}" ]]; then
		echo "ERR: Extension problem -- cant find extension '${extension_name}' anywhere - called by ${BASH_SOURCE[1]}"
		exit 17 # exit, forcibly. no way we can recover from this, and next extensions will get bogus errors as well.
	fi

	local before_function_list after_function_list new_function_list

	# store a list of existing functions at this point, before sourcing the extension.
	before_function_list="$(compgen -A function)"

	# shellcheck disable=SC1090
	source "${extension_file}"

	# decrement the recurse counter, so calls to this method are allowed again.
	enable_extension_recurse_counter=$((enable_extension_recurse_counter - 1))

	# get a new list of functions after sourcing the extension
	after_function_list="$(compgen -A function)"

	# compare before and after, thus getting the functions defined by the extension.
	# comm is oldskool. we like it. go "man comm" to understand -13 below
	new_function_list="$(comm -13 <(echo "$before_function_list" | sort) <(echo "$after_function_list" | sort))"

	# iterate over defined functions, store them in global associative array extension_function_info
	for newly_defined_function in ${new_function_list}; do
		#echo "func: ${newly_defined_function} has DIR: ${extension_dir}"
		extension_function_info["${newly_defined_function}"]="EXTENSION=\"${extension_name}\" EXTENSION_DIR=\"${extension_dir}\" EXTENSION_FILE=\"${extension_file}\" EXTENSION_ADDED_BY=\"${stacktrace}\""
	done

	# snapshot, then clear, the stack
	local -a stack_snapshot=("${enable_extension_recurse_stack[@]}")
	enable_extension_recurse_stack=()

	# process the stacked snapshot, finally enabling the extensions
	for stacked_extension in "${stack_snapshot[@]}"; do
		ENABLE_EXTENSION_TRACE_HINT="RECURSE ${stacktrace} ->" enable_extension "${stacked_extension}"
	done

}

# This looks up and enables _all_ existing extensions.
# The reasoning is simple: during Dockerfile build, we wanna have all the hostdeps defined, even if we're not gonna use them.
function enable_all_extensions_builtin_and_user() {
	declare -a extension_list=()
	declare -a ext_dirs=("${SRC}/extensions" "${SRC}/userpatches/extensions")
	declare -a ignore_extensions=("sample-extension")

	# Extensions are files of the format <dir>/extension_name.sh or <dir>/extension_name/extension_name.sh
	for ext_dir in "${ext_dirs[@]}"; do
		if [[ -d "${ext_dir}" ]]; then
			declare -a ext_list_dir=()
			mapfile -t ext_list_dir < <(find "${ext_dir}" -maxdepth 2 -type f -name "*.sh")
			extension_list+=("${ext_list_dir[@]}")
		fi
	done

	# loop over the files found; remove the prefix
	for extension_file in "${extension_list[@]}"; do
		extension_file="${extension_file#${SRC}/}"
		extension_file="${extension_file%.sh}"
		extension_name="${extension_file##*/}"
		# skip, if extension_name is in the ignore_extensions array
		if [[ " ${ignore_extensions[*]} " == *" ${extension_name} "* ]]; then
			continue
		fi
		# enable the extensions, quietly.
		enable_extension_quiet="yes" enable_extension "${extension_name}"
	done
}

# Fancy placeholder for future ideas. allow any core function to be hooked. maybe with "voters" infrastructure?
function do_with_hooks() {
	"$@"
}
