# @description Builds a `linux-source-${BRANCH}-${LINUXFAMILY}` package holding the patched kernel sources and the final `.config`

# Pre-install the source package into the image by setting INSTALL_KSRC=yes additionally.

declare -g INSTALL_KSRC="${INSTALL_KSRC:-no}"

# dtb-only and this extension are mutual exclusive.
function linux_source_package_is_active() {
	[[ "${KERNEL_DTB_ONLY:-"no"}" != "yes" ]]
}

function extension_prepare_config__linux_source_package() {
	case "${INSTALL_KSRC}" in
		yes | no) ;;
		*) exit_with_error "${EXTENSION}: INSTALL_KSRC must be 'yes' or 'no'" "got '${INSTALL_KSRC}'" ;;
	esac

	if ! linux_source_package_is_active; then
		display_alert "${EXTENSION}: no kernel sources package" "KERNEL_DTB_ONLY=yes" "warn"
		return 0
	fi

	display_alert "${EXTENSION}: packaging kernel sources" "linux-source-${BRANCH}-${LINUXFAMILY}; INSTALL_KSRC=${INSTALL_KSRC}" "info"
}

# A different set of packages needs a different artifact version, or it would clash with stock kernels in
# the caches; the pre_package_kernel_image hook below takes care of that.
function artifact_kernel_extra_packages__linux_source_package() {
	linux_source_package_is_active || return 0

	# Plain +=, not declare -g: during image builds this is a local of the caller.
	# shellcheck disable=SC2034 # artifact_map_packages is obtain_complete_artifact()'s
	artifact_map_packages+=(["linux-source"]="linux-source-${BRANCH}-${LINUXFAMILY}")

	return 0
}

# Print the NUL-separated source files of a git worktree: everything tracked, plus what patches added.
# <tree> <prefix for the printed paths>
function linux_source_package_list_tree() {
	declare tree="${1}" prefix="${2}"
	declare -a tracked=() untracked=()
	declare entry

	mapfile -d '' -t tracked < <(git -C "${tree}" ls-files -z --cached)
	wait $! || exit_with_error "linux-source-package: git ls-files failed" "${tree}"

	# core.excludesFile: a global gitignore of the build host has no say in what is source.
	mapfile -d '' -t untracked < <(git -C "${tree}" -c core.excludesFile=/dev/null ls-files -z --others --exclude-standard)
	wait $! || exit_with_error "linux-source-package: git ls-files --others failed" "${tree}"

	for entry in "${tracked[@]}"; do
		# patches delete files, too
		[[ -e "${tree}/${entry}" || -L "${tree}/${entry}" ]] || continue
		printf '%s\0' "${prefix}${entry}"
	done

	for entry in "${untracked[@]}"; do
		case "${entry}" in
			*/)
				# A directory is only listed if it is a git repository of its own (sources fetched into the tree).
				linux_source_package_list_tree "${tree}/${entry%/}" "${prefix}${entry}"
				;;
			*.orig | *.rej | .config | .config.*)
				# leftovers of patch(1); kernel configs, for trees that do not ignore them
				;;
			*)
				printf '%s\0' "${prefix}${entry}"
				;;
		esac
	done

	return 0
}

# Runs last of the custom_kernel_config hooks (999), to also catch sources other extensions copy in there.
function custom_kernel_config__999_linux_source_package_file_list() {
	linux_source_package_is_active || return 0

	# Called twice; only compile_kernel() has a tree, and kernel_work_dir is one of its variables.
	[[ -n "${kernel_work_dir:-}" && -f "${kernel_work_dir}/.config" ]] || return 0

	declare -g LINUX_SOURCE_PACKAGE_FILE_LIST="${WORKDIR}/linux-source-package.files"

	display_alert "${EXTENSION}: listing kernel source files" "${kernel_work_dir}" "info"
	linux_source_package_list_tree "${kernel_work_dir}" "" > "${LINUX_SOURCE_PACKAGE_FILE_LIST}.unsorted"
	LC_ALL=C sort -z -u -o "${LINUX_SOURCE_PACKAGE_FILE_LIST}" "${LINUX_SOURCE_PACKAGE_FILE_LIST}.unsorted"
	rm -f "${LINUX_SOURCE_PACKAGE_FILE_LIST}.unsorted"

	if ! grep -z -q -x -F "Makefile" "${LINUX_SOURCE_PACKAGE_FILE_LIST}"; then
		exit_with_error "${EXTENSION}: no Makefile among the kernel source files" "${kernel_work_dir}"
	fi

	declare file_count
	file_count="$(tr -d -c '\0' < "${LINUX_SOURCE_PACKAGE_FILE_LIST}" | wc -c)"
	display_alert "${EXTENSION}: kernel source files" "${file_count}" "info"

	return 0
}

# The one hook that fires for every kernel being packaged; its implementations are part of the artifact version.
# Builds a whole package of its own, the linux-image one being prepared around it is left alone.
function pre_package_kernel_image__linux_source_package() {
	linux_source_package_is_active || return 0

	declare saved_cwd="${PWD}" # create_kernel_deb() ends up in ${SRC}

	display_alert "Packaging linux-source" "${LINUXFAMILY} ${LINUXCONFIG}" "info"
	# shellcheck disable=SC2154 # debs_target_dir is prepare_kernel_packaging_debs()'s
	DEB_COMPRESS="none" create_kernel_deb "linux-source-${BRANCH}-${LINUXFAMILY}" "${debs_target_dir}" linux_source_package_deb_callback "linux-source"

	cd "${saved_cwd}" || exit_with_error "${EXTENSION}: can't cd back" "${saved_cwd}"

	return 0
}

# create_kernel_deb() callback. From the callers: package_directory, package_DEBIAN_dir, package_name,
# kernel_work_dir, kernel_version, kernel_version_family, kernel_base_revision_ts.
# shellcheck disable=SC2154
function linux_source_package_deb_callback() {
	declare file_list="${LINUX_SOURCE_PACKAGE_FILE_LIST:-}"
	if [[ ! -s "${file_list}" ]]; then
		exit_with_error "linux-source-package: list of kernel source files is missing" "${file_list:-"never created"}"
	fi
	if [[ ! -f "${kernel_work_dir}/.config" ]]; then
		exit_with_error "linux-source-package: kernel .config is missing" "${kernel_work_dir}"
	fi

	declare source_name="linux-source-${kernel_version_family}"
	declare usr_src_dir="${package_directory}/usr/src"
	mkdir -p "${usr_src_dir}"

	# Same tree, same tarball: fixed order (the list is sorted), owner, modes and timestamps.
	# The order of the options matters, --files-from comes last. "S" keeps the transform off symlink targets.
	declare -a tar_params=(
		"--create" "--file=${usr_src_dir}/${source_name}.tar.zst"
		"--use-compress-program=zstd -T0 -10"
		"--format=gnu" "--owner=0" "--group=0" "--numeric-owner" "--mode=a+r,u+w,go-w"
		"--transform=s,^,${source_name}/,S"
	)
	if [[ "${kernel_base_revision_ts:-}" =~ ^[0-9]+$ ]]; then
		tar_params+=("--mtime=@${kernel_base_revision_ts}") # date of the kernel git revision
	fi
	tar_params+=(
		"--directory=${kernel_work_dir}"
		"--null" "--verbatim-files-from" "--no-recursion" "--files-from=${file_list}"
	)

	display_alert "Compressing kernel sources" "${source_name}.tar.zst" "info"
	run_host_command_logged tar "${tar_params[@]@Q}"

	run_host_command_logged cp -v "${kernel_work_dir}/.config" "${usr_src_dir}/${source_name}.config"

	cat <<- CONTROL_FILE > "${package_DEBIAN_dir}/control"
		Version: ${artifact_version}
		Maintainer: ${MAINTAINER} <${MAINTAINERMAIL}>
		Section: kernel
		Package: ${package_name}
		Architecture: ${ARCH}
		Priority: optional
		Provides: linux-source (= ${kernel_version}), linux-source-armbian, armbian-$BRANCH
		Depends: zstd
		Recommends: make, gcc, libc6-dev, bc, bison, flex, libssl-dev, libelf-dev
		Description: Armbian Linux $BRANCH kernel sources ${kernel_version_family}
		 This package provides the patched kernel source code for ${kernel_version_family}
		 as /usr/src/${source_name}.tar.zst, and next to it, as
		 ${source_name}.config, the configuration the kernel was built with.
		 .
		 ${artifact_version_reason:-"${kernel_version_family}"}
	CONTROL_FILE

	return 0
}

function post_install_kernel_debs__linux_source_package() {
	[[ "${INSTALL_KSRC}" == "yes" ]] || return 0
	linux_source_package_is_active || return 0

	if [[ "${KERNELSOURCE}" == "none" ]]; then
		display_alert "${EXTENSION}: not installing kernel sources" "KERNELSOURCE=none" "warn"
		return 0
	fi

	display_alert "${EXTENSION}: installing kernel sources into image" "linux-source-${BRANCH}-${LINUXFAMILY}" "info"
	install_artifact_deb_chroot "linux-source"
}
