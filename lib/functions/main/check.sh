#!/usr/bin/env bash

###############################################################################
#
# string_is_contain()
# Check for the presence of a word in a string if the field separator is mixed.
# IFS can be "," comma " " space or ", " both or "\n" the end of a line.
# usage: if string_is_contain "word1 word2,word3" "word2"; then
#
string_is_contain() {
	[[ -z "$@" ]] && echo "err: ${FUNCNAME[0]}: Empty argument" >&2 && return 1
	[[ "$#" != 2 ]] && \
	echo "err: ${FUNCNAME[0]}: Invalid count of arguments: [$@]" >&2 && return 1
	local list=${1// /\\n}
	echo -e ${list//,/\\n} | grep -q "^$2$"
}

###############################################################################
#
# build_task_is_enabled()
#
# $1 - a single task name to check for BUILD_ONLY enablement
# return:
#   0 - if BUILD_ONLY if the task name is listed by BUILD_ONLY
#   1 - otherwise 
#
build_task_is_enabled() {
	string_is_contain "$BUILD_ONLY" "$1"
}

###############################################################################
#
# build_validate_buildOnly()
#
# This function validates the list of task names defined by global
# variable BUILD_ONLY versus the locally defined constant
# list __all_valid_buildOnly.
#
# In case of future extensions, please maintain the list of valid task names
# only here.
#
build_validate_buildOnly() {
	[[ -z $BUILD_ONLY ]] && display_alert "BUILD_ONLY has empty value" "call dialog" "err" && exit 1
	local _buildOnly="${BUILD_ONLY}"

	# constant list of all valid BUILD_ONLY task names - can be :comma: or :space: separated
	local _build_packages="$(list_of_main_packages)"
	local _build_default="$(default_task_list)"
	local _all_valid_buildOnly="$(default_task_list),$(list_of_bsp_desktop_packages)"

	# In this block we redefine the list of targets if a collective target
	# has been detected
	# collective target = "default"
	if string_is_contain "$_buildOnly" "default"
	then
		display_alert "BUILD_ONLY has task name:" "default" "wrn"
		display_alert "Redefine BUILD_ONLY to:" "$_build_default" "wrn"
		_buildOnly="$_build_default"
	fi

	# relace all :comma: by :space:
	_all_valid_buildOnly=${_all_valid_buildOnly//,/ }
	_buildOnly=${_buildOnly//,/ }

	local _invalidTaskNames=""
	for _taskName in ${_buildOnly}; do
		if ! string_is_contain "${_all_valid_buildOnly}" "$_taskName"
		then
			_invalidTaskNames+="${_taskName} "
		fi
	done

	if [[ -n $_invalidTaskNames ]]; then
		display_alert "BUILD_ONLY has invalid task name(s):" "${_invalidTaskNames}" "err"
		display_alert "Use BUILD_ONLY valid task names only:" "${_all_valid_buildOnly}" "ext"
		display_alert "Process aborted" "" "info"
		exit 1
	fi
	# Redefine BUILD_ONLY after changes.
	BUILD_ONLY="$_buildOnly"
}

