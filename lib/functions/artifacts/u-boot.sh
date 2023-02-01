function artifact_uboot_cli_adapter_pre_run() {
	declare -g ARMBIAN_COMMAND_REQUIRE_BASIC_DEPS="yes" # Require prepare_host_basic to run before the command.

	# "gimme root on a Linux machine"
	cli_standard_relaunch_docker_or_sudo
}

function artifact_uboot_cli_adapter_config_prep() {
	declare KERNEL_ONLY="yes"                             # @TODO: this is a hack, for the board/family code's benefit...
	use_board="yes" prep_conf_main_minimal_ni < /dev/null # no stdin for this, so it bombs if tries to be interactive.
}

function artifact_uboot_prepare_version() {
	display_alert "artifact_uboot_XXXXXX" "artifact_uboot_XXXXXX" "warn"
	artifact_version="undetermined"        # outer scope
	artifact_version_reason="undetermined" # outer scope

	# Prepare the version, "sans-repos": just the armbian/build repo contents are available.
	# It is OK to reach out to the internet for a curl or ls-remote, but not for a git clone/fetch.

	# - Given BOOTSOURCE and BOOTBRANCH, get:
	#    - SHA1 of the commit (this is generic... and used for other pkgs)
	#    - The first 10 lines of the root Makefile at that commit (cached lookup, same SHA1=same Makefile)
	#      - This gives us the full version plus codename.
	# - Get the u-boot patches hash. (could just hash the BOOTPATCHDIR non-disabled contents, or use Python patching proper?)
	# - Hash of the relevant lib/ bash sources involved, say compilation/uboot*.sh etc
	# All those produce a version string like:
	# 2023.11-<4-digit-SHA1>_<4_digit_patches>

	debug_var BOOTSOURCE
	debug_var BOOTBRANCH
	debug_var BOOTPATCHDIR
	debug_var BOARD

	declare short_hash_size=4

	declare -A GIT_INFO=([GIT_SOURCE]="${BOOTSOURCE}" [GIT_REF]="${BOOTBRANCH}")
	run_memoized GIT_INFO "git2info" memoized_git_ref_to_info "include_makefile_body"
	debug_dict GIT_INFO

	declare short_sha1="${GIT_INFO[SHA1]:0:${short_hash_size}}"

	# get the uboot patches hash...
	# @TODO: why not just delegate this to the python patching, with some "dry-run" / hash-only option?
	# @TODO: this is even more grave in case of u-boot: v2022.10 has patches for many boards inside, gotta resolve.
	declare patches_hash="undetermined"
	declare hash_files="undetermined"
	calculate_hash_for_all_files_in_dirs "${SRC}/patch/u-boot/${BOOTPATCHDIR}" "${USERPATCHES_PATH}/u-boot/${BOOTPATCHDIR}"
	patches_hash="${hash_files}"
	declare uboot_patches_hash_short="${patches_hash:0:${short_hash_size}}"

	# get the hashes of the lib/ bash sources involved...
	declare hash_files="undetermined"
	calculate_hash_for_files "${SRC}"/lib/functions/compilation/uboot*.sh # maybe also this file, "${SRC}"/lib/functions/artifacts/u-boot.sh
	declare bash_hash="${hash_files}"
	declare bash_hash_short="${bash_hash:0:${short_hash_size}}"

	# outer scope
	artifact_version="${GIT_INFO[MAKEFILE_VERSION]}-S${short_sha1}-P${uboot_patches_hash_short}-B${bash_hash_short}"
	# @TODO: validate it begins with a digit, and is at max X chars long.

	declare -a reasons=(
		"version \"${GIT_INFO[MAKEFILE_FULL_VERSION]}\""
		"git revision \"${GIT_INFO[SHA1]}\""
		"patches hash \"${patches_hash}\""
		"framework bash hash \"${bash_hash}\""
	)

	artifact_version_reason="${reasons[*]}" # outer scope # @TODO better

	# now, one for each file in the artifact...
	artifact_map_versions=(
		["u-boot"]="${artifact_version}"
	)

	# map what "compile_uboot()" will produce - legacy deb names and versions
	artifact_map_versions_legacy=(
		["linux-u-boot-${BRANCH}-${BOARD}"]="${REVISION}"
	)

	# now, one for each file in the artifact... single package, so just one entry
	artifact_map_versions=(
		["linux-u-boot-${BRANCH}-${BOARD}"]="${artifact_version}"
	)

	return 0
}

function artifact_uboot_is_available_in_local_cache() {
	display_alert "artifact_uboot_XXXXXX" "artifact_uboot_XXXXXX" "warn"
	# Check if the exact DEB exists on disk (output/debs), nothing else.
	# This is more about composing the .deb filename than checking if it exists.
}

function artifact_uboot_is_available_in_remote_cache() {
	display_alert "artifact_uboot_XXXXXX" "artifact_uboot_XXXXXX" "warn"
	# Check if the DEB can be obtained remotely, eg:
	# - in ghcr.io (via ORAS)
	# - in an apt repo (via apt-get), eg, Armbian's repo.
	# this is only about availability, not download. use HEAD requests / metadata-only pulls
	# what about multiple possible OCI endpoints / URLs? try them all?
}

function artifact_uboot_obtain_from_remote_cache() {
	display_alert "artifact_uboot_XXXXXX" "artifact_uboot_XXXXXX" "warn"
	# Having confirmed it is available remotely, go download it into the local cache.
	# is_available_in_local_cache() must return =yes after this.
	# could be a good idea to transfer some SHA256 id from "is_available" to "obtain" to avoid overhead? or just do it together?
}

function artifact_uboot_build_from_sources() {
	display_alert "artifact_uboot_XXXXXX" "artifact_uboot_XXXXXX" "warn"
	# having failed all the cache obtaining, build it from sources.

	if [[ -n "${ATFSOURCE}" && "${ATFSOURCE}" != "none" ]]; then
		LOG_SECTION="compile_atf" do_with_logging compile_atf
	fi

	declare uboot_git_revision="not_determined_yet"
	LOG_SECTION="uboot_prepare_git" do_with_logging_unless_user_terminal uboot_prepare_git
	LOG_SECTION="compile_uboot" do_with_logging compile_uboot

	capture_rename_legacy_debs_into_artifacts # has its own logging section
}

function artifact_uboot_deploy_to_remote_cache() {
	display_alert "artifact_uboot_XXXXXX" "artifact_uboot_XXXXXX" "warn"
	# having built a new artifact, deploy it to the remote cache.
	# consider multiple targets, retries, etc.
}
