function do_capturing_defs() {
	# make sure to local with a value, otherwise they will appear in the list...
	local pre_exec_vars="" exit_code=0 post_exec_vars="" new_vars_list="" onevar="" all_vars_array=()
	pre_exec_vars="$(compgen -A variable | grep -E '[[:upper:]]+' | grep -v -e "^BASH_" | sort)"

	# run parameters passed
	"$@" || exit_code=$?

	post_exec_vars="$(compgen -A variable | grep -E '[[:upper:]]+' | grep -v -e "^BASH_" | sort)"
	new_vars_list="$(comm -13 <(echo "$pre_exec_vars") <(echo "${post_exec_vars}"))"

	for onevar in ${new_vars_list}; do
		# @TODO: rpardini: handle arrays and maps specially?
		all_vars_array+=("$(declare -p "${onevar}")")
	done
	#IFS=$'\n'
	CAPTURED_VARS="${all_vars_array[*]}"
	#display_alert "Vars defined during ${*@Q}:" "${CAPTURED_VARS}" "debug"
	unset all_vars_array post_exec_vars new_vars_list pre_exec_vars onevar join_by

	return ${exit_code}
}
