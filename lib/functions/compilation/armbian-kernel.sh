#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

# Forced .config options for all Armbian kernels.
# Please note: Manually changing options doesn't check the validity of the .config file. This is done at next make time. Check for warnings in build log.

# This is an internal/core extension.
function armbian_kernel_config__disable_various_options() {
	kernel_config_modifying_hashes+=("CONFIG_MODULE_COMPRESS_NONE=y" "CONFIG_MODULE_SIG=n" "CONFIG_LOCALVERSION_AUTO=n" "DEBUG_KERNEL=n")
	if [[ -f .config ]]; then
		display_alert "Disabling module compression and signing / debug / auto version" "armbian-kernel" "debug"
		# DONE: Disable: signing, and compression of modules, for speed.
		kernel_config_set_n CONFIG_MODULE_COMPRESS_XZ # No use double-compressing modules
		kernel_config_set_n CONFIG_MODULE_COMPRESS_ZSTD
		kernel_config_set_n CONFIG_MODULE_COMPRESS_GZIP

		if linux-version compare "${KERNEL_MAJOR_MINOR}" ge 6.0; then
			kernel_config_set_y CONFIG_MODULE_COMPRESS_NONE	# Introduced in 6.0
		else
			kernel_config_set_n CONFIG_MODULE_COMPRESS # Only available up to 5.12
		fi

		kernel_config_set_n CONFIG_SECURITY_LOCKDOWN_LSM
		kernel_config_set_n CONFIG_MODULE_SIG # No use signing modules

		# DONE: Disable: version shenanigans
		kernel_config_set_n CONFIG_LOCALVERSION_AUTO      # This causes a mismatch between what Armbian wants and what make produces.
		kernel_config_set_string CONFIG_LOCALVERSION '""' # Must be empty; make is later invoked with LOCALVERSION and it adds up

		# DONE: Disable: debug option
		kernel_config_set_n DEBUG_KERNEL	# Armbian doesn't know how to package a debug kernel.
		kernel_config_set_n EXPERT			# This needs to be disabled as well since DEBUG_KERNEL=y is a dependency for EXPERT=y, meaning DEBUG_KERNEL would be re-enabled automatically if EXPERT is enabled
		#kernel_config_set_y DEBUG_INFO_NONE # Do not build the kernel with debugging information, which will result in a faster and smaller build. (NOTE: Not needed (?) when DEBUG_KERNEL=n and EXPERT=n since all DEBUG_INFO options are missing anyway in that case)
		kernel_config_set_n GDB_SCRIPTS

		if linux-version compare "${KERNEL_MAJOR_MINOR}" le 6.5; then
			kernel_config_set_n EMBEDDED	# Only present up to 6.5; this option forces EXPERT=y so it needs to be disabled
		fi

		# @TODO: Enable the options for the extrawifi/drivers; so we don't need to worry about them when updating configs
	fi
}

function armbian_kernel_config__enable_config_access_in_live_system() {
	kernel_config_modifying_hashes+=("CONFIG_IKCONFIG_PROC=y")
	if [[ -f .config ]]; then
		kernel_config_set_y CONFIG_IKCONFIG			# This information can be extracted from the kernel image file with the script scripts/extract-ikconfig and used as input to rebuild the current kernel or to build another kernel
		kernel_config_set_y CONFIG_IKCONFIG_PROC	# This option enables access to the kernel configuration file through /proc/config.gz
	fi
}

# +++++++++++ HELPERS CORNER +++++++++++
#
# Helpers for manipulating kernel config.
#
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

	# Only set to "n" if the config option can be found in the config file.
	# Otherwise the option would maybe be considered as misconfiguration.
	if grep -qE "(\b${config}\=|CONFIG_${config}\=)" .config; then
		run_host_command_logged ./scripts/config --disable "${config}"
	elif grep -qE "(\b${config} is not set|\bCONFIG_${config} is not set)" .config; then
		display_alert "Kernel config/module was already disabled" "${config}=n skipped" "debug"
	else
		display_alert "Kernel config/module was not found in the config file" "${config}=n was not added to prevent misconfiguration" "debug"
	fi

}

function kernel_config_set_string() {
	declare config="$1"
	declare value="${2}"
	display_alert "Setting kernel config/module" "${config}=${value}" "debug"
	run_host_command_logged ./scripts/config --set-str "${config}" "${value}"
}
