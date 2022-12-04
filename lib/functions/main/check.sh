#!/usr/bin/env bash

###############################################################################
#
# string_is_contain()
# Check for the presence of a word in a string if the field separator is mixed.
# IFS can be "," comma " " space or ", " both or "\n" the end of a line.
# usage: if string_is_contain "word1 word2,word3" "word2"; then
#
string_is_contain() {
	[[ -z "$@" ]] || [[ "$#" != 2 ]] && \
	echo "err: ${FUNCNAME[0]}: Bud argument $@" >&2 && return 1
	local list=${1// /\\n}
	echo -e ${list//,/\\n} | grep -q "^$2$"
}

###############################################################################
#
# build_task_is_enabled()
#
# $1: _taskNameToCheck - a single task name to check for BUILD_ONLY enablement
# return:
#   0 - if BUILD_ONLY is empty or if the task name is listed by BUILD_ONLY
#   1 - otherwise 
#
build_task_is_enabled() {
	# remove all "
	local _taskNameToCheck=${1//\"/}
	local _buildOnly=${BUILD_ONLY//\"/}
	# An empty _buildOnly allows any taskname
	[[ -z $_buildOnly ]] && return 0
	_buildOnly=${_buildOnly//,/ }
	for _buildOnlyTaskName in ${_buildOnly}; do
		[[ "$_taskNameToCheck" == "$_buildOnlyTaskName" ]] && return 0
	done
	return 1
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
	local _build_packages="u-boot,kernel,armbian-config,armbian-zsh,plymouth-theme-armbian,armbian-firmware,armbian-bsp"
	local _build_default="$_build_packages bootstrap"
	local _all_valid_buildOnly="$_build_default chroot"

	# collective target = "default"
	if string_is_contain "$_buildOnly" "default"
	then
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

