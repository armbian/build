#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function do_capturing_defs() {
	# make sure to local with a value, otherwise they will appear in the list...
	declare pre_exec_vars="" post_exec_vars="" new_vars_list="" onevar="" all_vars_array=()
	pre_exec_vars="$(compgen -A variable)"

	# run parameters passed. if this fails, so will we, immediately, and not capture anything correctly.
	# if you ever find stacks referring here, please look at the caller and $1
	"$@"

	post_exec_vars="$(compgen -A variable)"

	new_vars_list="$(comm -13 <(echo "$pre_exec_vars" | grep -E '[[:upper:]]+' | grep -v -e "^BASH_" | sort) <(echo "${post_exec_vars}" | grep -E '[[:upper:]]+' | grep -v -e "^BASH_" | sort))"

	for onevar in ${new_vars_list}; do
		all_vars_array+=("$(declare -p "${onevar}")")
	done

	declare -g CAPTURED_VARS_NAMES="${new_vars_list}"
	declare -ga CAPTURED_VARS_ARRAY=("${all_vars_array[@]}")
	unset all_vars_array post_exec_vars new_vars_list pre_exec_vars onevar

	return 0 # return success explicitly , preemptively preventing short-circuit problems.
}
