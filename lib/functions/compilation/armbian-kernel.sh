#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

# Forced .config options for all Armbian kernels.

# This is an internal/core extension.
function armbian_kernel_config__disable_module_compression() {
	kernel_config_modifying_hashes+=("CONFIG_MODULE_COMPRESS_NONE=y" "CONFIG_MODULE_SIG=n" "CONFIG_LOCALVERSION_AUTO=n" "DEBUG_INFO=n")
	if [[ -f .config ]]; then
		display_alert "Disabling module compression and signing / debug / auto version" "armbian-kernel" "debug"
		# DONE: Disable: signing, and compression of modules, for speed.
		kernel_config_set_n CONFIG_MODULE_COMPRESS_XZ # No use double-compressing modules
		kernel_config_set_n CONFIG_MODULE_COMPRESS_ZSTD
		kernel_config_set_n CONFIG_MODULE_COMPRESS_GZIP
		kernel_config_set_y CONFIG_MODULE_COMPRESS_NONE

		kernel_config_set_n CONFIG_SECURITY_LOCKDOWN_LSM
		kernel_config_set_n CONFIG_MODULE_SIG # No use signing modules

		# DONE: Disable: version shenanigans
		kernel_config_set_n CONFIG_LOCALVERSION_AUTO # This causes a mismatch between what Armbian wants and what make produces.

		# DONE: Disable: debug option
		kernel_config_set_n DEBUG_INFO # Armbian doesn't know how to package a debug kernel.

		# @TODO: Enable the options for the extrawifi/drivers; so we don't need to worry about them when updating configs
	fi
}

# Helpers for manipulating kernel config.
function kernel_config_set_m() {
	declare module="$1"
	display_alert "Enabling kernel module" "${module}=m" "debug"
	run_host_command_logged ./scripts/config --module "$module"
}

function kernel_config_set_y() {
	declare config="$1"
	display_alert "Enabling kernel config/built-in" "${config}=y" "debug"
	run_host_command_logged ./scripts/config --enable "${config}"
}

function kernel_config_set_n() {
	declare config="$1"
	display_alert "Disabling kernel config/module" "${config}=n" "debug"
	run_host_command_logged ./scripts/config --disable "${config}"
}
