# Expected variables
# - aggregated_content
# - potential_paths
# - separator
# Write to variables :
# - aggregated_content
aggregate_content() {
	[[ "${CONFIG_DEFS_ONLY}" == "yes" ]] && return 0 # Don't write to disk in this case.
	LOG_OUTPUT_FILE="$SRC/output/${LOG_SUBPATH}/potential-paths.log"
	echo -e "Potential paths :" >> "${LOG_OUTPUT_FILE}"
	show_checklist_variables potential_paths
	for filepath in ${potential_paths}; do
		if [[ -f "${filepath}" ]]; then
			echo -e "${filepath/"$SRC"\//} yes" >> "${LOG_OUTPUT_FILE}"
			aggregated_content+=$(cat "${filepath}")
			aggregated_content+="${separator}"
			#		else
			#			echo -e "${filepath/"$SRC"\//} no\n" >> "${LOG_OUTPUT_FILE}"
		fi

	done
	echo "" >> "${LOG_OUTPUT_FILE}"
	unset LOG_OUTPUT_FILE
}

get_all_potential_paths() {
	local root_dirs="${AGGREGATION_SEARCH_ROOT_ABSOLUTE_DIRS}"
	local rel_dirs="${1}"
	local sub_dirs="${2}"
	local looked_up_subpath="${3}"
	for root_dir in ${root_dirs}; do
		for rel_dir in ${rel_dirs}; do
			for sub_dir in ${sub_dirs}; do
				potential_paths+="${root_dir}/${rel_dir}/${sub_dir}/${looked_up_subpath} "
			done
		done
	done
	# for ppath in ${potential_paths}; do
	#  	echo "Checking for ${ppath}"
	#  	if [[ -f "${ppath}" ]]; then
	#  		echo "OK !|"
	#  	else
	#  		echo "Nope|"
	#  	fi
	# done
}

# Environment variables expected :
# - aggregated_content
# Arguments :
# 1. File to look up in each directory
# 2. The separator to add between each concatenated file
# 3. Relative directories paths added to ${3}
# 4. Relative directories paths added to ${4}
#
# The function will basically generate a list of potential paths by
# generating all the potential paths combinations leading to the
# looked up file
# ${AGGREGATION_SEARCH_ROOT_ABSOLUTE_DIRS}/${3}/${4}/${1}
# Then it will concatenate the content of all the available files
# into ${aggregated_content}
#
# TODO :
# ${4} could be removed by just adding the appropriate paths to ${3}
# dynamically for each case
# (debootstrap, cli, desktop environments, desktop appgroups, ...)

aggregate_all_root_rel_sub() {
	local separator="${2}"

	local potential_paths=""
	get_all_potential_paths "${3}" "${4}" "${1}"

	aggregate_content
}

aggregate_all_debootstrap() {
	local sub_dirs_to_check=". "
	if [[ ! -z "${SELECTED_CONFIGURATION+x}" ]]; then
		sub_dirs_to_check+="config_${SELECTED_CONFIGURATION}"
	fi
	aggregate_all_root_rel_sub "${1}" "${2}" "${DEBOOTSTRAP_SEARCH_RELATIVE_DIRS}" "${sub_dirs_to_check}"
}

aggregate_all_cli() {
	local sub_dirs_to_check=". "
	if [[ ! -z "${SELECTED_CONFIGURATION+x}" ]]; then
		sub_dirs_to_check+="config_${SELECTED_CONFIGURATION}"
	fi
	aggregate_all_root_rel_sub "${1}" "${2}" "${CLI_SEARCH_RELATIVE_DIRS}" "${sub_dirs_to_check}"
}

aggregate_all_desktop() {
	aggregate_all_root_rel_sub "${1}" "${2}" "${DESKTOP_ENVIRONMENTS_SEARCH_RELATIVE_DIRS}" "."
	aggregate_all_root_rel_sub "${1}" "${2}" "${DESKTOP_APPGROUPS_SEARCH_RELATIVE_DIRS}" "${DESKTOP_APPGROUPS_SELECTED}"
}

one_line() {
	local aggregate_func_name="${1}"
	local aggregated_content=""
	shift 1
	$aggregate_func_name "${@}"
	cleanup_list aggregated_content
}

cleanup_list() {
	local varname="${1}"
	local list_to_clean="${!varname}"
	list_to_clean="${list_to_clean#"${list_to_clean%%[![:space:]]*}"}"
	list_to_clean="${list_to_clean%"${list_to_clean##*[![:space:]]}"}"
	echo ${list_to_clean}
}

# is a formatted output of the values of variables
# from the list at the place of the function call.
#
# The LOG_OUTPUT_FILE variable must be defined in the calling function
# before calling the `show_checklist_variables` function and unset after.
#
show_checklist_variables() {
	[[ "${CONFIG_DEFS_ONLY}" == "yes" ]] && return 0 # Don't write to disk in this case.
	local checklist=$*
	local var pval
	local log_file=${LOG_OUTPUT_FILE:-"${SRC}"/output/${LOG_SUBPATH}/trash.log}
	local _line=${BASH_LINENO[0]}
	local _function=${FUNCNAME[1]}
	local _file=$(basename "${BASH_SOURCE[1]}")

	echo -e "Show variables in function: $_function" "[$_file:$_line]\n" >> $log_file

	for var in $checklist; do
		eval pval=\$$var
		echo -e "\n$var =:" >> $log_file
		if [ $(echo "$pval" | gawk -F"/" '{print NF}') -ge 4 ]; then
			printf "%s\n" $pval >> $log_file
		else
			printf "%-30s %-30s %-30s %-30s\n" $pval >> $log_file
		fi
	done
}
