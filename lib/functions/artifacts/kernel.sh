function artifact_kernel_cli_adapter_pre_run() {
	declare -g ARMBIAN_COMMAND_REQUIRE_BASIC_DEPS="yes" # Require prepare_host_basic to run before the command.

	# "gimme root on a Linux machine"
	cli_standard_relaunch_docker_or_sudo
}

function artifact_kernel_cli_adapter_config_prep() {
	use_board="yes" prep_conf_main_minimal_ni < /dev/null # no stdin for this, so it bombs if tries to be interactive.

}

function artifact_kernel_prepare_version() {
	display_alert "artifact_kernel_XXXXXX" "artifact_kernel_XXXXXX" "warn"
	# Prepare the version, "sans-repos": just the armbian/build repo contents are available.
	# It is OK to reach out to the internet for a curl or ls-remote, but not for a git clone.

	# - Given KERNELSOURCE and KERNELBRANCH, get:
	#    - SHA1 of the commit (this is generic... and used for other pkgs)
	#    - The first 10 lines of the root Makefile at that commit (cached lookup, same SHA1=same Makefile)
	#      - This gives us the full version plus codename.
	#    - Make sure this is sane, ref KERNEL_MAJOR_MINOR.
	# - Get the drivers patch hash (given LINUXFAMILY and the vX.Z.Y version)
	# - Get the kernel patches hash. (could just hash the KERNELPATCHDIR non-disabled contents, or use Python patching proper?)
	# - Get the kernel .config hash, composed of
	#    - KERNELCONFIG? .config hash
	#    - extensions mechanism, have an array of hashes that is then hashed together.
	# - Hash of the relevant lib/ bash sources involved, say compilation-kernel*.sh etc
	# All those produce a version string like:
	# v6.1.8-<4-digit-SHA1>_<4_digit_drivers>-<4_digit_patches>-<4_digit_config>-<4_digit_libs>
	# v6.2-rc5-a0b1-c2d3-e4f5-g6h7-i8j9

	debug_var KERNELSOURCE
	debug_var KERNELBRANCH
	debug_var LINUXFAMILY
	debug_var BOARDFAMILY
	debug_var KERNEL_MAJOR_MINOR
	debug_var KERNELPATCHDIR

	# This has... everything: https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/commit/?h=linux-6.1.y
	# This has... everything: https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/commit/?h=v6.2-rc5

	# get the sha1 of the commit on tag or branch
	# git ls-remote --exit-code --symref git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git v6.2-rc5
	# git ls-remote --exit-code --symref git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git v6.2-rc5

	# 93f875a8526a291005e7f38478079526c843cbec	refs/heads/linux-6.1.y
	# 4cc398054ac8efe0ff832c82c7caacbdd992312a	refs/tags/v6.2-rc5

	# https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/tree/Makefile?h=linux-6.1.y
	# plaintext: https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain/Makefile?h=4cc398054ac8efe0ff832c82c7caacbdd992312a

	function git_ref_to_info_memoized() {
		declare ref_type ref_name
		git_parse_ref "${KERNEL[GIT_REF]}"
		KERNEL+=(["REF_TYPE"]="${ref_type}")
		KERNEL+=(["REF_NAME"]="${ref_name}")

		# Get the SHA1 of the commit
		#declare sha1
		#sha1="$(git ls-remote --exit-code "${KERNELSOURCE}" "${ref_name}" | cut -f1)"
		#KERNEL+=(["SHA1"]="${sha1}")
	}

	function git_ref_input_hash() {
		KERNEL+=(["MEMO_TYPE"]="git2sha1")
		KERNEL+=(["MEMO_INPUT"]="${KERNEL[GIT_SOURCE]} ${KERNEL[GIT_REF]}")
	}

	function run_memoized() {
		declare var_n="${1}"
		declare hasher_func="${2}"
		declare memoized_func="${3}"

		${hasher_func} "${@}" # sets KERNEL["MEMO_INPUT"] and KERNEL["MEMO_TYPE"]
		KERNEL+=(["MEMO_INPUT_HASH"]="$(echo "${var_n}-${KERNEL[MEMO_INPUT_HASH]}-$(declare -f "${hasher_func}")-$(declare -f "${memoized_func}")" | sha256sum | cut -f1 -d' ')")

		declare disk_cache_dir="${SRC}/cache/memoize/${KERNEL[MEMO_TYPE]}"
		mkdir -p "${disk_cache_dir}"
		declare disk_cache_file="${disk_cache_dir}/${KERNEL[MEMO_INPUT_HASH]}"
		if [[ -f "${disk_cache_file}" ]]; then
			display_alert "Using memoized ${var_n} from ${disk_cache_file}" "${KERNEL[MEMO_INPUT]}" "info"
			cat "${disk_cache_file}"
			# shellcheck disable=SC1090 # yep, I'm sourcing the cache here. produced below.
			source "${disk_cache_file}"
			return 0
		fi

		display_alert "Memoizing ${var_n} to ${disk_cache_file}" "${KERNEL[MEMO_INPUT]}" "info"
		# if cache miss, run the memoized_func...
		${memoized_func} "${@}"

		# ... and save the output to the cache
		declare -p KERNEL > "${disk_cache_file}"
	}

	declare -A KERNEL=(
		[GIT_SOURCE]="${KERNELSOURCE}"
		[GIT_REF]="${KERNELBRANCH}"
	)

	display_alert "before"
	debug_dict KERNEL

	run_memoized KERNEL git_ref_input_hash git_ref_to_info_memoized

	display_alert "after"
	debug_dict KERNEL
}

function debug_dict() {
	local dict_name="$1"
	declare -n dict="${dict_name}"
	for key in "${!dict[@]}"; do
		debug_var "${dict_name}[${key}]"
	done
}

function debug_var() {
	local varname="$1"
	local var_val="${!varname}"
	display_alert "${varname}" "${var_val}" "warn"
}

function artifact_kernel_is_available_in_local_cache() {
	display_alert "artifact_kernel_XXXXXX" "artifact_kernel_XXXXXX" "warn"
	# Check if the exact DEB exists on disk (output/debs), nothing else.
	# This is more about composing the .deb filename than checking if it exists.
}

function artifact_kernel_is_available_in_remote_cache() {
	display_alert "artifact_kernel_XXXXXX" "artifact_kernel_XXXXXX" "warn"
	# Check if the DEB can be obtained remotely, eg:
	# - in ghcr.io (via ORAS)
	# - in an apt repo (via apt-get), eg, Armbian's repo.
	# this is only about availability, not download. use HEAD requests / metadata-only pulls
	# what about multiple possible OCI endpoints / URLs? try them all?
}

function artifact_kernel_obtain_from_remote_cache() {
	display_alert "artifact_kernel_XXXXXX" "artifact_kernel_XXXXXX" "warn"
	# Having confirmed it is available remotely, go download it into the local cache.
	# is_available_in_local_cache() must return =yes after this.
	# could be a good idea to transfer some SHA256 id from "is_available" to "obtain" to avoid overhead? or just do it together?
}

function artifact_kernel_build_from_sources() {
	display_alert "artifact_kernel_XXXXXX" "artifact_kernel_XXXXXX" "warn"
	# having failed all the cache obtaining, build it from sources.
}

function artifact_kernel_deploy_to_remote_cache() {
	display_alert "artifact_kernel_XXXXXX" "artifact_kernel_XXXXXX" "warn"
	# having built a new artifact, deploy it to the remote cache.
	# consider multiple targets, retries, etc.
}
