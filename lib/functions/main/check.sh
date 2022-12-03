#!/usr/bin/env bash

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
# variable BUIDL_ONLY versus the locally defined constant
# list __all_valid_buildOnly.
#
# In case of future extensions, please maintain the list of valid task names
# only here.
#
build_validate_buildOnly() {
	# constant list of all valid BUILD_ONLY task names - can be :comma: or :space: separated
	local _all_valid_buildOnly="u-boot kernel armbian-config armbian-zsh plymouth-theme-armbian armbian-firmware armbian-bsp chroot bootstrap"
	# remove all "
	local _buildOnly=${BUILD_ONLY//\"/}
	# relace all :comma: by :space:
	_all_valid_buildOnly=${_all_valid_buildOnly//,/ }
	_buildOnly=${_buildOnly//,/ }
	[[ -z $_buildOnly ]] && return
	local _invalidTaskNames=""
	for _taskName in ${_buildOnly}; do
		local _isFound=0
		for _supportedTaskName in ${_all_valid_buildOnly}; do
			[[ "$_taskName" == "$_supportedTaskName" ]] && _isFound=1 && break
		done
		if [[ $_isFound == 0 ]]; then
			[[ -z $_invalidTaskNames ]] && _invalidTaskNames="${_taskName}" || _invalidTaskNames="${_invalidTaskNames} ${_taskName}"
		fi
	done
	if [[ -n $_invalidTaskNames ]]; then
		display_alert "BUILD_ONLY has invalid task name(s):" "${_invalidTaskNames}" "err"
		display_alert "Use BUILD_ONLY valid task names only:" "${_all_valid_buildOnly}" "ext"
		display_alert "Process aborted" "" "info"
		exit 1
	fi
}

