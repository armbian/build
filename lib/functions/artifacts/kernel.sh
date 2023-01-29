function artifact_kernel_cli_adapter_pre_run() {
	declare -g ARMBIAN_COMMAND_REQUIRE_BASIC_DEPS="yes" # Require prepare_host_basic to run before the command.

	# "gimme root on a Linux machine"
	cli_standard_relaunch_docker_or_sudo
}

function artifact_kernel_cli_adapter_config_prep() {
	declare KERNEL_ONLY="yes"                             # @TODO: this is a hack, for the board/family code's benefit...
	use_board="yes" prep_conf_main_minimal_ni < /dev/null # no stdin for this, so it bombs if tries to be interactive.
}

function artifact_kernel_prepare_version() {
	display_alert "artifact_kernel_XXXXXX" "artifact_kernel_XXXXXX" "warn"
	artifact_version="undetermined"        # outer scope
	artifact_version_reason="undetermined" # outer scope

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

	declare -A GIT_INFO=([GIT_SOURCE]="${KERNELSOURCE}" [GIT_REF]="${KERNELBRANCH}")
	run_memoized GIT_INFO "git2info" memoized_git_ref_to_info "include_makefile_body"
	debug_dict GIT_INFO

	declare short_sha1="${GIT_INFO[SHA1]:0:4}"

	# get the drivers hash...
	declare kernel_drivers_patch_hash
	LOG_SECTION="kernel_drivers_create_patches_hash_only" do_with_logging do_with_hooks kernel_drivers_create_patches_hash_only
	declare kernel_drivers_hash_short="${kernel_drivers_patch_hash:0:4}"

	# get the kernel patches hash...
	# @TODO: why not just delegate this to the python patching, with some "dry-run" / hash-only option?
	declare patches_hash="undetermined"
	declare hash_files="undetermined"
	calculate_hash_for_all_files_in_dirs "${SRC}/patch/kernel/${KERNELPATCHDIR}" "${USERPATCHES_PATH}/kernel/${KERNELPATCHDIR}"
	patches_hash="${hash_files}"
	declare kernel_patches_hash_short="${patches_hash:0:4}"

	# get the .config hash... also userpatches...
	declare kernel_config_source_filename="" # which actual .config was used?
	prepare_kernel_config_core_or_userpatches
	declare hash_files="undetermined"
	calculate_hash_for_files "${kernel_config_source_filename}"
	config_hash="${hash_files}"
	declare config_hash_short="${config_hash:0:4}"

	# @TODO: get the extensions' .config modyfing hashes...

	artifact_version="v${GIT_INFO[MAKEFILE_VERSION]}-${short_sha1}-${kernel_drivers_hash_short}-${kernel_patches_hash_short}-${config_hash_short}" # outer scope

	declare -a reasons=(
		"v${GIT_INFO[MAKEFILE_FULL_VERSION]}"
		"git revision \"${GIT_INFO[SHA1]}\""
		"codename \"${GIT_INFO[MAKEFILE_CODENAME]}\""
		"drivers hash \"${kernel_drivers_patch_hash}\""
		"patches hash \"${patches_hash}\""
		".config hash \"${config_hash}\""
	)

	artifact_version_reason="${reasons[*]}" # outer scope # @TODO better

	return 0
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
	compile_kernel
}

function artifact_kernel_deploy_to_remote_cache() {
	display_alert "artifact_kernel_XXXXXX" "artifact_kernel_XXXXXX" "warn"
	# having built a new artifact, deploy it to the remote cache.
	# consider multiple targets, retries, etc.
}
