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
# The external repo is pinned to a fixed tag (not a moving branch) so build
# hashing stays deterministic: a given armbian/build revision always resolves
# to the same extension content. Bump the pin via a regular PR when Seeed
# cuts a new release tag.
SEEED_EXTENSION_REPO="https://github.com/Seeed-Studio/seeed_armbian_extension"
SEEED_EXTENSION_REF="tag:v1.1"

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

fetch_from_repo "${SEEED_EXTENSION_REPO}" "seeed_armbian_extension" "${SEEED_EXTENSION_REF}"

SEEED_EXT_DIR="${SRC}/cache/sources/seeed_armbian_extension"
mkdir -p "${SRC}/extensions"
ln -sf "${SEEED_EXT_DIR}" "${SRC}/extensions/seeed_armbian_extension"
enable_extension "seeed_armbian_extension"
