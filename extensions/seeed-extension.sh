# Thin wrapper that enables Seeed Studio's external Armbian extension
# (currently used by the reComputer RK35xx boards).
#
# The actual extension lives in an external repository:
#   https://github.com/Seeed-Studio/seeed_armbian_extension
# This wrapper fetches it at the pinned ref below and enables its
# entrypoint, which cascades into the sub-extensions (OTA support, disk
# encryption, security hardening, U-Boot postprocess) based on the
# OTA_ENABLE / CRYPTROOT_ENABLE / RK_* build variables.
#
# Two ways to enable it:
#   - Armbian CI and generic users: ENABLE_EXTENSIONS=seeed-extension
#     (registered in armbian.github.io release-targets/targets-extensions.map)
#   - Legacy switch kept for Seeed's own builds and documentation:
#     ENABLE_SEEED_RK_EXTENSION=yes; the board family config bridges to
#     this wrapper.
#
# Tracks main; the resolved revision is recorded in /etc/armbian-release
# (SEEED_EXTENSION_COMMIT). Override with SEEED_EXTENSION_REF=tag:vN to pin.
# declare -g: this wrapper is sourced inside enable_extension(), where plain
# assignments are function-local and would not reach the rootfs hooks.
SEEED_EXTENSION_REPO="https://github.com/Seeed-Studio/seeed_armbian_extension"
declare -g SEEED_EXTENSION_REF="${SEEED_EXTENSION_REF:-branch:main}"

# Board-family hooks (post_family_config__recomputer_stage_kernel_patches
# and friends) check this variable to gate Seeed-specific behavior; export
# it before anything else.
export ENABLE_SEEED_RK_EXTENSION="yes"

# GITHUB_SOURCE is only set (readonly) by do_main_configuration, which runs
# after board config sourcing: under the legacy ENABLE_SEEED_RK_EXTENSION
# bridge this wrapper is sourced while GITHUB_SOURCE is still empty, and
# fetch_from_repo's URL rewriting would strip the URL to '/Seeed-Studio/...'.
# Default it only when empty; when already set (readonly, extension-manager
# path) the assignment is skipped so it can't fail.
if [[ -z "${GITHUB_SOURCE:-}" ]]; then
	GITHUB_SOURCE="https://github.com"
fi

# Don't fetch during config-dump-json (CONFIG_DEFS_ONLY=yes). The board×branch
# inventory runs many config dumps in parallel; a real git fetch here has no tree
# to feed yet and races on the global git config (`git config --global --add
# safe.directory ...` -> exit 128), which then breaks the whole inventory -- the
# same reason other extensions (e.g. sophgo-sg200x-aic8800, gateway-dk-ask) skip
# fetching in this mode. Reuse the cached clone if one is present so the config
# dump still sees the extension; with no cache yet, skip it for the dump. The
# repo is fetched for real on an actual build.
seeed_ext_enable="yes"
if [[ "${CONFIG_DEFS_ONLY}" == "yes" ]]; then
	if [[ -e "${SRC}/cache/sources/seeed_armbian_extension/.git" ]]; then
		display_alert "seeed-extension" "config-dump-json: reusing cached clone, skipping fetch" "debug"
	else
		display_alert "seeed-extension" "config-dump-json: no cached clone, skipping fetch and enable" "debug"
		seeed_ext_enable="no"
	fi
else
	fetch_from_repo "${SEEED_EXTENSION_REPO}" "seeed_armbian_extension" "${SEEED_EXTENSION_REF}"
fi

# Resolved revision of the checkout; written into /etc/armbian-release.
declare -g SEEED_EXTENSION_COMMIT
SEEED_EXTENSION_COMMIT="$(git -C "${SRC}/cache/sources/seeed_armbian_extension" rev-parse HEAD 2>/dev/null || echo unknown)"

if [[ "${seeed_ext_enable}" == "yes" ]]; then
	SEEED_EXT_DIR="${SRC}/cache/sources/seeed_armbian_extension"
	mkdir -p "${SRC}/extensions"
	ln -sf "${SEEED_EXT_DIR}" "${SRC}/extensions/seeed_armbian_extension"
	enable_extension "seeed_armbian_extension"
fi
unset seeed_ext_enable
