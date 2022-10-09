#!/usr/bin/env bash

# This is called like this:
#	declare -A -g ARMBIAN_PARSED_CMDLINE_PARAMS=()
#	declare -a -g ARMBIAN_NON_PARAM_ARGS=()
#	parse_cmdline_params "${@}" # which fills the vars above, being global.
function parse_cmdline_params() {
	declare -A -g ARMBIAN_PARSED_CMDLINE_PARAMS=()
	declare -a -g ARMBIAN_NON_PARAM_ARGS=()

	# loop over the arguments parse them out
	local arg
	for arg in "${@}"; do
		if [[ "${arg}" == *=* ]]; then # contains an equal sign. it's a param.
			local param_name param_value param_value_desc
			param_name=${arg%%=*}
			param_value=${arg##*=}
			param_value_desc="${param_value:-(empty)}"
			ARMBIAN_PARSED_CMDLINE_PARAMS["${param_name}"]="${param_value}" # For current run.
			ARMBIAN_CLI_RELAUNCH_PARAMS["${param_name}"]="${param_value}"   # For relaunch.
			display_alert "Command line: parsed parameter '$param_name' to" "${param_value_desc}" "debug"
		elif [[ "x${arg}x" != "xx" ]]; then # not a param, not empty, store it in the non-param array for later usage
			local non_param_value="${arg}"
			local non_param_value_desc="${non_param_value:-(empty)}"
			display_alert "Command line: storing non-param argument" "${non_param_value_desc}" "debug"
			ARMBIAN_NON_PARAM_ARGS+=("${non_param_value}")
		fi
	done
}

# This can be called early on, or later after having sourced the config. Show what is happening.
# This is called:
# apply_cmdline_params_to_env "reason" # reads from global ARMBIAN_PARSED_CMDLINE_PARAMS
function apply_cmdline_params_to_env() {
	declare -A -g ARMBIAN_PARSED_CMDLINE_PARAMS # Hopefully this has values
	declare __my_reason="${1}"
	shift

	# Loop over the dictionary and apply the values to the environment.
	for param_name in "${!ARMBIAN_PARSED_CMDLINE_PARAMS[@]}"; do
		local param_value param_value_desc current_env_value
		# get the current value from the environment
		current_env_value="${!param_name}"
		current_env_value_desc="${current_env_value:-(empty)}"
		# get the new value from the dictionary
		param_value="${ARMBIAN_PARSED_CMDLINE_PARAMS[${param_name}]}"
		param_value_desc="${param_value:-(empty)}"

		# Compare, log, and apply.
		if [[ "${current_env_value}" != "${param_value}" ]]; then
			display_alert "Applying cmdline param" "'$param_name': '${current_env_value_desc}' --> '${param_value_desc}' ${__my_reason}" "cmdline"
			# use `declare -g` to make it global, we're in a function.
			eval "declare -g $param_name=\"$param_value\""
		else
			# rpardini: strategic amount of spacing in log files show the kinda neuroticism that drives me.
			display_alert "Skip     cmdline param" "'$param_name': already set to '${param_value_desc}' ${__my_reason}" "info"
		fi
	done
}

function armbian_prepare_cli_command_to_run() {
	local command_id="${1}"
	display_alert "Preparing to run command" "${command_id}" "debug"
	ARMBIAN_COMMAND="${command_id}"
	ARMBIAN_COMMAND_HANDLER="${ARMBIAN_COMMANDS_TO_HANDLERS_DICT[${command_id}]}"
	ARMBIAN_COMMAND_VARS="${ARMBIAN_COMMANDS_TO_VARS_DICT[${command_id}]}"
	# @TODO: actually set the vars...

	local set_vars_for_command=""
	if [[ "x${ARMBIAN_COMMAND_VARS}x" != "xx" ]]; then
		# Loop over them, expanding...
		for var_piece in ${ARMBIAN_COMMAND_VARS}; do
			local var_decl="declare -g ${var_piece};"
			display_alert "Command handler: setting variable" "${var_decl}" "debug"
			set_vars_for_command+=" ${var_decl}"
		done
	fi

	local pre_run_function_name="cli_${ARMBIAN_COMMAND_HANDLER}_pre_run"
	local run_function_name="cli_${ARMBIAN_COMMAND_HANDLER}_run"

	# Reset the functions.
	function armbian_cli_pre_run_command() {
		display_alert "No pre-run function for command" "${ARMBIAN_COMMAND}" "warn"
	}
	function armbian_cli_run_command() {
		display_alert "No run function for command" "${ARMBIAN_COMMAND}" "warn"
	}

	# Materialize functions to call that specific command.
	if [[ $(type -t "${pre_run_function_name}" || true) == function ]]; then
		eval "$(
			cat <<- EOF
				display_alert "Setting up pre-run function for command" "${ARMBIAN_COMMAND}: ${pre_run_function_name}" "debug"
				function armbian_cli_pre_run_command() {
					# Set the variables defined in ARMBIAN_COMMAND_VARS
					${set_vars_for_command}
					display_alert "Calling pre-run function for command" "${ARMBIAN_COMMAND}: ${pre_run_function_name}" "debug"
					${pre_run_function_name}
				}
			EOF
		)"
	fi

	if [[ $(type -t "${run_function_name}" || true) == function ]]; then
		eval "$(
			cat <<- EOF
				display_alert "Setting up run function for command" "${ARMBIAN_COMMAND}: ${run_function_name}" "debug"
				function armbian_cli_run_command() {
					# Set the variables defined in ARMBIAN_COMMAND_VARS
					${set_vars_for_command}
					display_alert "Calling run function for command" "${ARMBIAN_COMMAND}: ${run_function_name}" "debug"
					${run_function_name}
				}
			EOF
		)"
	fi
}

function parse_each_cmdline_arg_as_command_param_or_config() {
	local is_command="no" is_config="no" command_handler conf_path conf_sh_path config_file=""
	local argument="${1}"

	# lookup if it is a command.
	if [[ -n "${ARMBIAN_COMMANDS_TO_HANDLERS_DICT[${argument}]}" ]]; then
		is_command="yes"
		command_handler="${ARMBIAN_COMMANDS_TO_HANDLERS_DICT[${argument}]}"
		display_alert "Found command!" "${argument} is handled by '${command_handler}'" "debug"
	fi

	# see if we can find config file in userpatches. can be either config-${argument}.conf or config-${argument}.conf.sh
	conf_path="${SRC}/userpatches/config-${argument}.conf"
	conf_sh_path="${SRC}/userpatches/config-${argument}.conf.sh"

	# early safety net: immediately bomb if we find both forms of config. it's too confusing. choose one.
	if [[ -f ${conf_path} && -f ${conf_sh_path} ]]; then
		exit_with_error "Found both config-${argument}.conf and config-${argument}.conf.sh in userpatches. Please remove one."
		exit 1
	elif [[ -f ${conf_sh_path} ]]; then
		config_file="${conf_sh_path}"
		is_config="yes"
	elif [[ -f ${conf_path} ]]; then
		config_file="${conf_path}"
		is_config="yes"
	fi

	# Sanity check. If we have both a command and a config, bomb.
	if [[ "${is_command}" == "yes" && "${is_config}" == "yes" ]]; then
		exit_with_error "You cannot have a configuration file named '${config_file}'. '${argument}' is a command name and is reserved for internal Armbian usage. Sorry. Please rename your config file and pass its name it an argument, and I'll use it. PS: You don't need a config file for 'docker' anymore, Docker is all managed by Armbian now."
	elif [[ "${is_config}" == "yes" ]]; then # we have a config only
		display_alert "Adding config file to list" "${config_file}" "debug"
		ARMBIAN_CONFIG_FILES+=("${config_file}")    # full path to be sourced
		ARMBIAN_CLI_RELAUNCH_CONFIGS+="${argument}" # name reference to be relaunched
	elif [[ "${is_command}" == "yes" ]]; then    # we have a command, only.
		# sanity check. we can't have more than one command. decide!
		if [[ -n "${ARMBIAN_COMMAND}" ]]; then
			exit_with_error "You cannot specify more than one command. You have '${ARMBIAN_COMMAND}' and '${argument}'. Please decide which one you want to run and pass only that one."
			exit 1
		fi
		ARMBIAN_COMMAND="${argument}" # too early for armbian_prepare_cli_command_to_run "${argument}"
	else
		# We've an unknown argument. Alert now, bomb later.
		ARMBIAN_HAS_UNKNOWN_ARG="yes"
		display_alert "Unknown argument" "${argument}" "err"
	fi
}

# Produce relaunch parameters. Add the running configs, arguments, and command.
# Declare and use ARMBIAN_CLI_RELAUNCH_ARGS as "${ARMBIAN_CLI_RELAUNCH_ARGS[@]}"
function produce_relaunch_parameters() {
	declare -g -a ARMBIAN_CLI_RELAUNCH_ARGS=()
	# add the running parameters from ARMBIAN_CLI_RELAUNCH_PARAMS dict
	for param in "${!ARMBIAN_CLI_RELAUNCH_PARAMS[@]}"; do
		ARMBIAN_CLI_RELAUNCH_ARGS+=("${param}=${ARMBIAN_CLI_RELAUNCH_PARAMS[${param}]}")
	done
	# add the running configs
	for config in ${ARMBIAN_CLI_RELAUNCH_CONFIGS}; do
		ARMBIAN_CLI_RELAUNCH_ARGS+=("${config}")
	done
	display_alert "Produced relaunch args:" "ARMBIAN_CLI_RELAUNCH_ARGS: ${ARMBIAN_CLI_RELAUNCH_ARGS[*]}" "debug"
	# @TODO: add the command. if we have one.

}
