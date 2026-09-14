#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2026 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function artifact_armbian-bsp-cli_config_dump() {
	artifact_input_variables[BOARD]="${BOARD}"
	artifact_input_variables[BRANCH]="${BRANCH}"
	artifact_input_variables[EXTRA_BSP_NAME]="${EXTRA_BSP_NAME}"
}

function artifact_armbian-bsp-cli_prepare_version() {
	: "${BRANCH:?BRANCH is not set}"
	: "${BOARD:?BOARD is not set}"

	artifact_version="undetermined"        # outer scope
	artifact_version_reason="undetermined" # outer scope

	declare short_hash_size=4

	declare fake_unchanging_base_version="1"

	# hash the contents of "post_family_tweaks_bsp" extension hooks (always) - use framework helper
	# hash the contents of family_tweaks_bsp old-style hooks (if it exists)
	declare -a hooks_to_hash=("$(dump_extension_method_sources_functions "post_family_tweaks_bsp")")
	if [[ $(type -t family_tweaks_bsp) == function ]]; then
		hooks_to_hash+=("$(declare -f "family_tweaks_bsp")")
	fi
	declare hash_hooks="undetermined"
	hash_hooks="$(echo "${hooks_to_hash[@]}" | sha256sum | cut -d' ' -f1)"
	declare hash_hooks_short="${hash_hooks:0:${short_hash_size}}"

	# get the bootscript info...
	declare -A bootscript_info=()
	get_bootscript_info # fills in bootscript_info array

	# Hash variables/bootscripts that affect the contents of bsp-cli package.
	# Those contain /armbian a lot, so don't normalize them.
	declare -a vars_to_hash_no_normalize=(
		"bootscript_file_contents: ${bootscript_info[bootscript_file_contents]}"
		"bootenv_file_contents: ${bootscript_info[bootenv_file_contents]}"
	)
	declare hash_variables="undetermined"                                                     # will be set by calculate_hash_for_variables(), but without normalization
	do_normalize_src_path="no" calculate_hash_for_variables "${vars_to_hash_no_normalize[@]}" # don't normalize
	declare hash_vars_no_normalize="${hash_variables}"

	declare -a vars_to_hash=(
		"has_bootscript: ${bootscript_info[has_bootscript]}"
		"has_extlinux: ${bootscript_info[has_extlinux]}"
		"UBOOT_FW_ENV: ${UBOOT_FW_ENV}"                               # not included in bootscript
		"KEEP_ORIGINAL_OS_RELEASE: ${KEEP_ORIGINAL_OS_RELEASE:-"no"}" # /etc/os-release
		"BOARDFAMILY: ${BOARDFAMILY}"                                 # /etc/armbian-release
		"LINUXFAMILY: ${LINUXFAMILY}"                                 # /etc/armbian-release
		"IMAGE_TYPE: ${IMAGE_TYPE}"                                   # /etc/armbian-release
		"BOARD_TYPE: ${BOARD_TYPE}"                                   # /etc/armbian-release
		"INITRD_ARCH: ${INITRD_ARCH}"                                 # /etc/armbian-release
		"KERNEL_IMAGE_TYPE: ${KERNEL_IMAGE_TYPE}"                     # /etc/armbian-release
		"VENDOR: ${VENDOR}"                                           # /etc/armbian-release
		"VENDORCOLOR: ${VENDORCOLOR}"                                 # /etc/armbian-release
		"OVERLAY_DIR: ${OVERLAY_DIR}"                                 # /etc/armbian-release
		"KERNEL_TARGET: ${KERNEL_TARGET}"                             # /etc/armbian-release
		"KERNEL_TEST_TARGET: ${KERNEL_TEST_TARGET}"                   # /etc/armbian-release
		"BOOT_SOC: ${BOOT_SOC}"                                       # /etc/armbian-release # See https://github.com/armbian/build/pull/6411
		"hash_vars_no_normalize: ${hash_vars_no_normalize}"           # The non-normalized part, above
	)
	declare hash_variables="undetermined" # will be set by calculate_hash_for_variables(), which normalizes the input
	calculate_hash_for_variables "${vars_to_hash[@]}"
	declare vars_config_hash="${hash_variables}"
	declare var_config_hash_short="${vars_config_hash:0:${short_hash_size}}"

	declare -a dirs_to_hash=(
		"${SRC}/packages/bsp/common" # common stuff
		"${SRC}/packages/bsp/${BOARD}" # board-specific stuff
		"${SRC}/config/optional/_any_board/_packages/bsp-cli"
		"${SRC}/config/optional/architectures/${ARCH}/_packages/bsp-cli"
		"${SRC}/config/optional/families/${LINUXFAMILY}/_packages/bsp-cli"
		"${SRC}/config/optional/boards/${BOARD}/_packages/bsp-cli"
	)

	# The hooks are hashed above only as source text: `install ${SRC}/packages/bsp/foo/bar` reads the
	# same whether bar changed or not. So also hash the directory of every packages/ path they name,
	# shared ones like packages/bsp/rk3399 or packages/blobs/riscv64/spacemit included.
	declare hooks_text="${hooks_to_hash[*]}" hook_match hook_path hook_var hook_value
	# Resolve the variables hooks build packages/ paths from. \b keeps $BOARD off $BOARDFAMILY. An empty or
	# unusual value stays unresolved, and is warned about below rather than put into a path.
	for hook_var in BOARD BOARDFAMILY LINUXFAMILY ARCH; do
		hook_value="${!hook_var:-}"
		[[ "${hook_value}" =~ ^[A-Za-z0-9._-]+$ ]] || continue
		hooks_text="$(LC_ALL=C sed -E 's/\$(\{'"${hook_var}"'\}|'"${hook_var}"'\b)/'"${hook_value}"'/g' <<< "${hooks_text}")"
	done
	declare -A hook_dirs=() hook_paths_unhashed=()
	# packages/ must follow ${SRC}/ or start a word: not dist-packages/foo/bar or /var/lib/packages/foo/bar.
	# Not ${SRC}/ alone, so a relative packages/bsp/foo or ./packages/bsp/foo after a cd "${SRC}" is still seen.
	declare hook_path_start='((^|[^A-Za-z0-9._/-])(\./)?|\$\{?SRC\}?"?/)'
	while read -r hook_match; do
		hook_match="packages/${hook_match#*packages/}" # drop what matched hook_path_start
		hook_path="${hook_match%/}"
		[[ -d "${SRC}/${hook_path}" ]] || hook_path="${hook_path%/*}" # a file, or a name cut short by a variable
		if [[ "${hook_path}" != packages/[!/]*/[!/]* ]]; then         # never all of packages/bsp
			hook_paths_unhashed["${hook_match}"]=1
			continue
		fi
		hook_dirs["${SRC}/${hook_path}"]=1
	done < <(LC_ALL=C grep -oE "${hook_path_start}"'packages/[A-Za-z0-9._-]+/[A-Za-z0-9._/-]+' <<< "${hooks_text}" || true)
	# A variable right after packages/ or packages/<x>/ stops the grep above before it matches at all.
	while read -r hook_match; do
		hook_paths_unhashed["packages/${hook_match#*packages/}"]=1
	done < <(LC_ALL=C grep -oE "${hook_path_start}"'packages/([A-Za-z0-9._-]+/)?\$\{?[A-Za-z_][A-Za-z0-9_]*\}?' <<< "${hooks_text}" || true)
	for hook_match in "${!hook_paths_unhashed[@]}"; do
		display_alert "bsp-cli: a hook installs from a path that does not version the package" "'${hook_match}': changes there will not rebuild it; spell the directory out, or use \${BOARD}, \${BOARDFAMILY}, \${LINUXFAMILY} or \${ARCH}" "wrn"
	done

	# Skip a dir that is, or is inside, one already listed (packages/bsp/${BOARD}/rtl_bt, jethub/jethubj100
	# under jethub): its files would be hashed twice, and the version would depend on how hooks spell paths.
	# Sorted, so a parent is always listed before its children.
	declare -a hook_dirs_sorted=()
	declare hook_dir listed_dir
	mapfile -t hook_dirs_sorted < <(printf '%s\n' "${!hook_dirs[@]}" | LC_ALL=C sort)
	for hook_dir in "${hook_dirs_sorted[@]}"; do
		[[ -n "${hook_dir}" ]] || continue # printf prints an empty line when there are no hook dirs
		for listed_dir in "${dirs_to_hash[@]}"; do
			[[ "${hook_dir}" == "${listed_dir}" || "${hook_dir}" == "${listed_dir}/"* ]] && continue 2
		done
		dirs_to_hash+=("${hook_dir}")
	done

	declare hash_files="undetermined"
	calculate_hash_for_all_files_in_dirs "${dirs_to_hash[@]}"
	packages_config_hash="${hash_files}"
	declare packages_config_hash_short="${packages_config_hash:0:${short_hash_size}}"

	# get the hashes of the lib/ bash sources involved...
	declare hash_files="undetermined"
	calculate_hash_for_bash_deb_artifact "bsp/armbian-bsp-cli-deb.sh" "bsp/utils-bsp.sh"
	declare bash_hash="${hash_files}"
	declare bash_hash_short="${bash_hash:0:${short_hash_size}}"

	# outer scope
	artifact_version="${fake_unchanging_base_version}-PC${packages_config_hash_short}-V${var_config_hash_short}-H${hash_hooks_short}-B${bash_hash_short}"

	declare -a reasons=(
		"Armbian package armbian-bsp-cli"
		"BOARD \"${BOARD}\""
		"BRANCH \"${BRANCH}\""
		"EXTRA_BSP_NAME \"${EXTRA_BSP_NAME}\""
		"Packages and config files hash \"${packages_config_hash}\""
		"Hooks hash \"${hash_hooks}\""
		"Variables/bootscripts hash \"${vars_config_hash}\""
		"framework bash hash \"${bash_hash}\""
	)

	artifact_version_reason="${reasons[*]}" # outer scope

	artifact_deb_repo="global"  # "global" meaning: release-independent repo. could be '${RELEASE}' for a release-specific package.
	artifact_deb_arch="${ARCH}" # arch-specific package, or 'all' for arch-independent package.
	artifact_name="armbian-bsp-cli-${BOARD}-${BRANCH}${EXTRA_BSP_NAME}"
	artifact_type="deb-tar"

	artifact_map_packages=(["armbian-bsp-cli"]="${artifact_name}")

	# Register the function used to re-version the _contents_ of the bsp-cli deb file (non-transitional)
	artifact_debs_reversion_functions+=("reversion_armbian-bsp-cli_deb_contents")

	if artifact_armbian-bsp-cli_needs_transitional_package; then
		artifact_map_packages+=(["armbian-bsp-cli-transitional"]="armbian-bsp-cli-${BOARD}${EXTRA_BSP_NAME}")
		# Register the function used to re-version the _contents_ of the bsp-cli deb file (transitional)
		artifact_debs_reversion_functions+=("reversion_armbian-bsp-cli-transitional_deb_contents")
	fi

	return 0
}

function artifact_armbian-bsp-cli_build_from_sources() {
	# Generate transitional package when needed.
	if artifact_armbian-bsp-cli_needs_transitional_package; then
		LOG_SECTION="compile_armbian-bsp-cli" do_with_logging compile_armbian-bsp-cli-transitional
	fi

	LOG_SECTION="compile_armbian-bsp-cli" do_with_logging compile_armbian-bsp-cli
}

function artifact_armbian-bsp-cli_cli_adapter_pre_run() {
	declare -g ARMBIAN_COMMAND_REQUIRE_BASIC_DEPS="yes" # Require prepare_host_basic to run before the command.

	# "gimme root on a Linux machine"
	cli_standard_relaunch_docker_or_sudo
}

function artifact_armbian-bsp-cli_cli_adapter_config_prep() {
	# there is no need for aggregation here.
	use_board="yes" allow_no_family="no" skip_kernel="no" prep_conf_main_minimal_ni < /dev/null # no stdin for this, so it bombs if tries to be interactive.
}

function artifact_armbian-bsp-cli_get_default_oci_target() {
	artifact_oci_target_base="${GHCR_SOURCE}/armbian/os/"
}

function artifact_armbian-bsp-cli_is_available_in_local_cache() {
	is_artifact_available_in_local_cache
}

function artifact_armbian-bsp-cli_is_available_in_remote_cache() {
	is_artifact_available_in_remote_cache
}

function artifact_armbian-bsp-cli_obtain_from_remote_cache() {
	obtain_artifact_from_remote_cache
}

function artifact_armbian-bsp-cli_deploy_to_remote_cache() {
	upload_artifact_to_oci
}

function artifact_armbian-bsp-cli_needs_transitional_package() {
	if [[ "${KERNEL_TARGET}" == "${BRANCH}" ]]; then
		return 0
	elif [[ "${BRANCH}" == "current" ]]; then
		return 0
	elif [[ "${KERNEL_TARGET}" != *current* && "${BRANCH}" == "legacy" ]]; then
		return 0
	else
		return 1
	fi
}
