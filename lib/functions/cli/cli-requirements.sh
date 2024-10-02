#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function cli_requirements_pre_run() {
	declare -g ARMBIAN_COMMAND_REQUIRE_BASIC_DEPS="yes" # Require prepare_host_basic to run before the command.

	if [[ "$(uname)" != "Linux" ]]; then
		display_alert "Not running on Linux" "refusing to run 'requirements'" "err"
		exit 1
	fi

	if [[ "${EUID}" == "0" ]]; then # we're already root. Either running as real root, or already sudo'ed.
		display_alert "Already running as root" "great" "debug"
	else
		# Fail, installing requirements is not allowed as non-root.
		exit_with_error "This command requires root privileges - refusing to run"
	fi
}

function cli_requirements_run() {
	initialize_extension_manager # initialize the extension manager.
	declare -a -g host_dependencies=()

	obtain_and_check_host_release_and_arch # Sets HOSTRELEASE & validates it for sanity; also HOSTARCH
	host_release="${HOSTRELEASE}" host_arch="${HOSTARCH}" early_prepare_host_dependencies

	LOG_SECTION="install_host_dependencies" do_with_logging install_host_dependencies "for requirements command"
	declare -i -g -r prepare_host_has_already_run=1 # global, readonly. fool the rest of the script into thinking we've already run prepare_host.

	if [[ "${ARMBIAN_INSIDE_DOCKERFILE_BUILD}" == "yes" ]]; then
		# Include python/pip packages in the Dockerfile build.
		deploy_to_non_cache_dir="yes" prepare_python_and_pip

		# During the Dockerfile build, we want to pre-download ORAS/shellcheck/shfmt so it's included in the image.
		# We need to change the deployment directory to something not in ./cache, so it's baked into the image.
		deploy_to_non_cache_dir="yes" run_tool_oras       # download-only, to non-cache dir.
		deploy_to_non_cache_dir="yes" run_tool_shellcheck # download-only, to non-cache dir.
		deploy_to_non_cache_dir="yes" run_tool_batcat     # download-only, to non-cache dir.

		# @TODO: shfmt
	fi

	display_alert "Done with" "@host dependencies" "cachehit"
}
