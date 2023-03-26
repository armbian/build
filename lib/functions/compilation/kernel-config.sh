#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function prepare_kernel_config_core_or_userpatches() {
	# LINUXCONFIG is set or exit_with_error
	[[ -z "${LINUXCONFIG}" ]] && exit_with_error "LINUXCONFIG not set: '${LINUXCONFIG}'"

	if [[ -f $USERPATCHES_PATH/$LINUXCONFIG.config ]]; then
		display_alert "Using kernel config provided by user" "userpatches/$LINUXCONFIG.config" "info"
		kernel_config_source_filename="${USERPATCHES_PATH}/${LINUXCONFIG}.config"
	elif [[ -f "${USERPATCHES_PATH}/config/kernel/${LINUXCONFIG}.config" ]]; then
		display_alert "Using kernel config provided by user in config/kernel folder" "config/kernel/${LINUXCONFIG}.config" "info"
		kernel_config_source_filename="${USERPATCHES_PATH}/config/kernel/${LINUXCONFIG}.config"
	else
		display_alert "Using kernel config file" "config/kernel/$LINUXCONFIG.config" "info"
		kernel_config_source_filename="${SRC}/config/kernel/${LINUXCONFIG}.config"
	fi
}

function kernel_config() {
	# check $kernel_work_dir is set and exists, or bail
	[[ -z "${kernel_work_dir}" ]] && exit_with_error "kernel_work_dir is not set"
	[[ ! -d "${kernel_work_dir}" ]] && exit_with_error "kernel_work_dir does not exist: ${kernel_work_dir}"
	declare previous_config_filename=".config.armbian.previous"
	declare kernel_config_source_filename="" # which actual .config was used?

	LOG_SECTION="kernel_config_initialize" do_with_logging do_with_hooks kernel_config_initialize

	if [[ "${KERNEL_CONFIGURE}" == "yes" ]]; then
		# This piece is interactive, no logging
		display_alert "Starting (interactive) kernel ${KERNEL_MENUCONFIG:-menuconfig}" "${LINUXCONFIG}" "debug"
		run_kernel_make_dialog "${KERNEL_MENUCONFIG:-menuconfig}"

		# Export, but log about it too.
		LOG_SECTION="kernel_config_export" do_with_logging do_with_hooks kernel_config_export
	fi

	LOG_SECTION="kernel_config_finalize" do_with_logging do_with_hooks kernel_config_finalize
}

function kernel_config_initialize() {
	display_alert "Configuring kernel" "${LINUXCONFIG}" "info"
	cd "${kernel_work_dir}" || exit_with_error "kernel_work_dir does not exist: ${kernel_work_dir}"

	# If a `.config` already exists (from previous build), store it, preserving date.
	# We will compare the result of the new configuration to it, and if the contents are the same, we'll restore the original date.
	# This way we avoid unnecessary recompilation of the kernel; even if the .config contents
	# have not changed, the date will be different, and Kbuild will at least re-link everything.
	if [[ -f "${kernel_work_dir}/.config" ]]; then
		display_alert "Preserving previous kernel configuration" "${previous_config_filename}" "debug"
		run_host_command_logged cp -pv "${kernel_work_dir}/.config" "${kernel_work_dir}/${previous_config_filename}"
	fi

	# copy kernel config from configuration, userpatches
	if [[ "${KERNEL_KEEP_CONFIG}" == yes && -f "${DEST}"/config/$LINUXCONFIG.config ]]; then
		display_alert "Using previously-exported kernel config" "${DEST}/config/$LINUXCONFIG.config" "info"
		run_host_command_logged cp -pv "${DEST}/config/${LINUXCONFIG}.config" "${kernel_work_dir}/.config"
	else
		prepare_kernel_config_core_or_userpatches
		run_host_command_logged cp -pv "${kernel_config_source_filename}" "${kernel_work_dir}/.config"
	fi

	# Start by running olddefconfig -- always.
	# It "updates" the config, using defaults from Kbuild files in the source tree.
	# It is worthy noting that on the first run, it builds the tools, so the host-side compiler has to be working,
	# regardless of the cross-build toolchain.
	cd "${kernel_work_dir}" || exit_with_error "kernel_work_dir does not exist: ${kernel_work_dir}"
	run_kernel_make olddefconfig

	# Call the extensions. This is _also_ done during the kernel artifact's prepare_version, for consistent caching.
	call_extensions_kernel_config

	display_alert "Kernel configuration" "${LINUXCONFIG}" "info"
}

function call_extensions_kernel_config() {
	# Run the core-armbian config modifications here, built-in extensions:
	call_extension_method "armbian_kernel_config" <<- 'ARMBIAN_KERNEL_CONFIG'
		*Armbian-core default hook point for pre-olddefconfig Kernel config modifications*
		NOT for user consumption. Do NOT use this hook, this is internal to Armbian.
		Instead, use `custom_kernel_config` which runs later and can undo anything done by this step.
		Important: this hook might be run multiple times, and one of them might not have a .config in place.
		Either way, the hook _must_ add representative changes to the `kernel_config_modifying_hashes` array, for kernel config hashing.
	ARMBIAN_KERNEL_CONFIG

	# Custom hooks receive a clean / updated config; depending on their modifications, they may need to run olddefconfig again.
	call_extension_method "custom_kernel_config" <<- 'CUSTOM_KERNEL_CONFIG'
		*Kernel .config is in place, still clean from git version*
		Called after ${LINUXCONFIG}.config is put in place (.config).
		A good place to customize the .config directly.
		Armbian default Kconfig modifications have already been applied and can be overriden.
		Important: this hook might be run multiple times, and one of them might not have a .config in place.
		Either way, the hook _must_ add representative changes to the `kernel_config_modifying_hashes` array, for kernel config hashing.
	CUSTOM_KERNEL_CONFIG
}

function kernel_config_finalize() {
	# Now, compare the .config with the previous one, and if they are the same, restore the original date.
	# This way we avoid unnecessary recompilation of the kernel; even if the .config contents
	# have not changed, the date will be different, and Kbuild will at least re-link everything.
	if [[ -f "${kernel_work_dir}/${previous_config_filename}" ]]; then
		# from "man cmp": Exit status is 0 if inputs are the same, 1 if different, 2 if trouble.
		if cmp "${kernel_work_dir}/.config" "${kernel_work_dir}/${previous_config_filename}"; then
			display_alert "Kernel configuration unchanged from previous run" "optimizing for fast rebuilds" "cachehit"
			run_host_command_logged cp -pv "${kernel_work_dir}/${previous_config_filename}" "${kernel_work_dir}/.config"
		else
			display_alert "Kernel configuration changed from previous build" "optimizing for correctness" "info"
			# ad: added lines; de: deleted lines; hd: header lines; ln: line numbers
			# run_host_command_logged diff -u --color=always "--palette='rs=0:hd=1:ad=33:de=37:ln=36'" "${kernel_work_dir}/${previous_config_filename}" "${kernel_work_dir}/.config" "|| true" # no errors please
		fi
		# either way, remove the previous file
		run_host_command_logged rm -f "${kernel_work_dir}/${previous_config_filename}"
	fi
}

function kernel_config_export() {
	# store kernel config in easily reachable place
	mkdir -p "${DEST}"/config
	display_alert "Exporting new kernel config" "$DEST/config/$LINUXCONFIG.config" "info"
	run_host_command_logged cp -pv .config "${DEST}/config/${LINUXCONFIG}.config"

	# store back into original LINUXCONFIG too, if it came from there, so it's pending commits when done.
	if [[ "${kernel_config_source_filename}" != "" ]]; then
		display_alert "Exporting new kernel config - git commit pending" "${kernel_config_source_filename}" "info"
		run_host_command_logged cp -pv .config "${kernel_config_source_filename}"

		# export defconfig
		run_kernel_make savedefconfig
		run_host_command_logged cp -pv defconfig "${DEST}/config/${LINUXCONFIG}.defconfig"
		run_host_command_logged cp -pv defconfig "${kernel_config_source_filename}.defconfig"
	fi
}
