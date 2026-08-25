function error_if_kernel_only_set() {
	if [[ "x${KERNEL_ONLY}x" != "xx" ]]; then
		display_alert "KERNEL_ONLY is not supported; use new" "./compile.sh kernel BOARD=${BOARD} BRANCH=${BRANCH} kernel" "err"
		exit_with_error "KERNEL_ONLY is set.This is not supported anymore. Please remove it, and use the new CLI commands."
		return 1
	fi
}

function error_if_lib_tag_set() {
	if [[ "x${LIB_TAG}x" != "xx" ]]; then
		exit_with_error "LIB_TAG is set.This is not supported anymore. Please remove it, and manage the git branches manually."
		return 1
	fi
}

# Backward-compatible renaming of build switches (scalar env-var parameters).
#
# To rename a switch without breaking existing configs and command lines, add an
# entry here mapping the OLD name to the NEW name. At build time, if the old
# switch is set and the new one is not, the old value is forwarded to the new
# name and a deprecation warning is printed. When both are set, the new one wins
# and the old one is ignored with a warning.
#
# This is for scalar switches only; it does not handle array parameters.
declare -g -A DEPRECATED_SWITCH_ALIASES=(
	# [OLD_SWITCH_NAME]="NEW_SWITCH_NAME"
	# e.g. [BUILD_ALL]="BUILD_MINIMAL"
)

# The dicts the CLI carries alongside the environment. The parsed-params one is
# read directly by early consumers rather than through the environment, and the
# relaunch ones are what get handed back to us when re-execing into Docker or
# sudo -- an alias has to be normalized in all of them, not just in the shell.
# The old-name value this pass wrote itself, per alias. The pass sets both names,
# so on a later call the old name is set whether or not the user ever touched it;
# comparing against what we wrote is what tells the two apart. A plain "handled"
# flag cannot: it would also silence a config file that sets the old name after
# an earlier pass had already synced the pair.
declare -g -A DEPRECATED_SWITCH_SYNCED=()

declare -g -a DEPRECATED_SWITCH_DICTS=(
	ARMBIAN_PARSED_CMDLINE_PARAMS
	ARMBIAN_CLI_RELAUNCH_PARAMS
	ARMBIAN_CLI_RELAUNCH_ENVS
)

# Each takes the dict's *name*; a nameref keeps these eval-free. All three are
# no-ops when the dict does not exist yet, since the early pass runs before some
# of them are declared.
function deprecated_switch_dict_has() {
	declare -p "${1}" &> /dev/null || return 1
	declare -n dict_ref="${1}"
	[[ -v "dict_ref[${2}]" ]]
}

function deprecated_switch_dict_get() {
	declare -p "${1}" &> /dev/null || return 0
	declare -n dict_ref="${1}"
	printf '%s' "${dict_ref[${2}]-}"
}

function deprecated_switch_dict_set() {
	declare -p "${1}" &> /dev/null || return 0
	declare -n dict_ref="${1}"
	dict_ref["${2}"]="${3}"
}

# Keeps an aliased pair of switches in agreement, in the environment and in
# every CLI dict that mentions either name.
#
# Both names are left set on purpose. Renaming a switch should not oblige anyone
# to go and update every consumer in the tree, nor every board/family config
# that still spells it the old way: registering the alias is enough, and moving
# the consumers over is optional and can happen later. Unsetting the old name
# here would break exactly those consumers.
#
# The new name wins when the two disagree. Once they agree there is nothing to
# do, which is what makes the pass idempotent -- it is called early, before the
# pre_run loop and the Docker checks read the parsed params, and again after
# config files have been sourced, since those can set old names too.
function apply_deprecated_switch_aliases() {
	local old new dict value
	for old in "${!DEPRECATED_SWITCH_ALIASES[@]}"; do
		new="${DEPRECATED_SWITCH_ALIASES[${old}]}"

		# Look for each name in the environment first, then in the dicts.
		local old_set="no" new_set="no" old_value="" new_value=""
		if [[ -v "${old}" ]]; then
			local -n _ref="${old}"
			old_value="${_ref}"
			unset -n _ref
			old_set="yes"
		fi
		if [[ -v "${new}" ]]; then
			local -n _ref="${new}"
			new_value="${_ref}"
			unset -n _ref
			new_set="yes"
		fi
		for dict in "${DEPRECATED_SWITCH_DICTS[@]}"; do
			if [[ "${old_set}" == "no" ]] && deprecated_switch_dict_has "${dict}" "${old}"; then
				old_value="$(deprecated_switch_dict_get "${dict}" "${old}")"
				old_set="yes"
			fi
			if [[ "${new_set}" == "no" ]] && deprecated_switch_dict_has "${dict}" "${new}"; then
				new_value="$(deprecated_switch_dict_get "${dict}" "${new}")"
				new_set="yes"
			fi
		done

		# only act when one of them was actually set by the user
		[[ "${old_set}" == "yes" || "${new_set}" == "yes" ]] || continue

		if [[ "${new_set}" == "yes" ]]; then
			value="${new_value}"
		else
			value="${old_value}"
		fi

		# Did the user actually supply the old name, or is it just what we wrote
		# on an earlier pass? Warn only for the former -- including when both
		# names were set to the same value, which is still a use of a deprecated
		# switch and would otherwise pass in silence.
		local user_set_old="no"
		if [[ "${old_set}" == "yes" ]]; then
			if [[ ! -v "DEPRECATED_SWITCH_SYNCED[${old}]" || "${old_value}" != "${DEPRECATED_SWITCH_SYNCED[${old}]}" ]]; then
				user_set_old="yes"
			fi
		fi
		if [[ "${user_set_old}" == "yes" ]]; then
			if [[ "${new_set}" == "yes" && "${old_value}" != "${new_value}" ]]; then
				display_alert "Deprecated switch '${old}' ignored" "'${new}' is set and wins; remove '${old}' from your config/command line" "warn"
			else
				display_alert "Deprecated switch '${old}' is deprecated" "use '${new}' instead; both names carry the value for now" "warn"
			fi
		fi
		DEPRECATED_SWITCH_SYNCED["${old}"]="${value}"

		deprecated_switch_set_both "${old}" "${new}" "${value}"
	done
}

# Give both names the resolved value: in the environment, and in every dict that
# already mentions either of them. Dicts that mention neither are left alone.
function deprecated_switch_set_both() {
	local old="${1}" new="${2}" value="${3}" dict name
	for name in "${old}" "${new}"; do
		# carry the export attribute across; created unexported, a forwarded
		# switch would be invisible to everything we exec, the relaunch included
		if [[ "${!old@a}" == *x* || "${!new@a}" == *x* ]]; then
			declare -g -x "${name}=${value}"
		else
			declare -g "${name}=${value}"
		fi
	done
	for dict in "${DEPRECATED_SWITCH_DICTS[@]}"; do
		deprecated_switch_dict_has "${dict}" "${old}" || deprecated_switch_dict_has "${dict}" "${new}" || continue
		deprecated_switch_dict_set "${dict}" "${old}" "${value}"
		deprecated_switch_dict_set "${dict}" "${new}" "${value}"
	done
}
