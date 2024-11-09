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
	kernel_config_modifying_hashes+=("CONFIG_MODULE_COMPRESS_NONE=y" "CONFIG_MODULE_SIG=n" "CONFIG_LOCALVERSION_AUTO=n" "EXPERT=y")
	if [[ -f .config ]]; then
		display_alert "Enable CONFIG_EXPERT=y" "armbian-kernel" "debug"
		kernel_config_set_y EXPERT # Too many config options are hidden behind EXPERT=y, lets have it always on

		display_alert "Disabling module compression and signing / debug / auto version" "armbian-kernel" "debug"
		# DONE: Disable: signing, and compression of modules, for speed.
		kernel_config_set_n CONFIG_MODULE_COMPRESS_XZ # No use double-compressing modules
		kernel_config_set_n CONFIG_MODULE_COMPRESS_ZSTD
		kernel_config_set_n CONFIG_MODULE_COMPRESS_GZIP

		if linux-version compare "${KERNEL_MAJOR_MINOR}" ge 6.12; then
			kernel_config_set_n CONFIG_MODULE_COMPRESS # Introduced in 6.12 (see https://github.com/torvalds/linux/commit/c7ff693fa2094ba0a9d0a20feb4ab1658eff9c33)
		elif linux-version compare "${KERNEL_MAJOR_MINOR}" ge 6.0; then
			kernel_config_set_y CONFIG_MODULE_COMPRESS_NONE # Introduced in 6.0
		else
			kernel_config_set_n CONFIG_MODULE_COMPRESS # Only available up to 5.12
		fi

		kernel_config_set_n CONFIG_SECURITY_LOCKDOWN_LSM
		kernel_config_set_n CONFIG_MODULE_SIG # No use signing modules

		# DONE: Disable: version shenanigans
		kernel_config_set_n CONFIG_LOCALVERSION_AUTO      # This causes a mismatch between what Armbian wants and what make produces.
		kernel_config_set_string CONFIG_LOCALVERSION '""' # Must be empty; make is later invoked with LOCALVERSION and it adds up
	fi
}

function armbian_kernel_config__enable_config_access_in_live_system() {
	kernel_config_modifying_hashes+=("CONFIG_IKCONFIG_PROC=y")
	if [[ -f .config ]]; then
		kernel_config_set_y CONFIG_IKCONFIG      # This information can be extracted from the kernel image file with the script scripts/extract-ikconfig and used as input to rebuild the current kernel or to build another kernel
		kernel_config_set_y CONFIG_IKCONFIG_PROC # This option enables access to the kernel configuration file through /proc/config.gz
	fi
}

function armbian_kernel_config__restore_enable_gpio_sysfs() {
	kernel_config_modifying_hashes+=("CONFIG_GPIO_SYSFS=y")
	if [[ -f .config ]]; then
		kernel_config_set_y CONFIG_GPIO_SYSFS # This was a victim of not having EXPERT=y due to some _DEBUG conflicts in old times. Re-enable it forcefully.
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
	display_alert "Setting kernel config/module string" "${config}=${value}" "debug"
	run_host_command_logged ./scripts/config --set-str "${config}" "${value}"
}

function kernel_config_set_val() {
	declare config="$1"
	declare value="${2}"
	display_alert "Setting kernel config/module value" "${config}=${value}" "debug"
	run_host_command_logged ./scripts/config --set-val "${config}" "${value}"
}
