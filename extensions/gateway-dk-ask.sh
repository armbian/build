#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Mono Technologies Inc.
#
# NXP ASK (Application Solutions Kit) extension for LS1046A
# Integrates kernel modules (CDX, FCI, auto-bridge, sfp-led, lp5812) in-tree
# and builds userspace tools (fmlib, fmc, libfci, libcli, dpa-app, cmm),
# patched system libraries, and configuration files.
#
# All ASK sources, patches, and configs come from the ASK repo.
#

# Source repos and refs (pinned to match Yocto)
# For local testing: set ASK_REPO="file:///path/to/ASK" — the Docker mount hook below handles it
declare -g ASK_REPO="https://github.com/we-are-mono/ASK.git"
declare -g ASK_BRANCH="commit:05aaf4ff0830de45b26fcc1a9bc75749c08b8bf3" # mono-1.0.0 (peeled commit)
declare -g FMLIB_REPO="https://github.com/nxp-qoriq/fmlib.git"
declare -g FMLIB_COMMIT="7a58ecaf0d90d71d6b78d3ac7998282a472c4394"
declare -g FMC_REPO="https://github.com/nxp-qoriq/fmc.git"
declare -g FMC_COMMIT="5b9f4b16a864e9dfa58cdcc860be278a7f66ac18"
declare -g LIBCLI_REPO="https://github.com/dparrish/libcli.git"
declare -g LIBCLI_COMMIT="6a3b2f96c4f0916e2603a96bf24d704f6a904e7a"

# NXP DPAA/FMan/QBMan SDK source. Mainline does not carry these drivers, so the
# kernel base (kernel.org stable, set in the ls1046a family config) is overlaid with
# this SDK before the ASK hook patches apply. The SDK ref is NOT hand-maintained here:
# it is read at build time from ASK's format-neutral pin (pins/nxp-sdk-srcrev.inc), so
# ASK_BRANCH stays the single pin and the SDK can never drift from what ASK targets.
declare -g NXP_SDK_REPO="https://github.com/nxp-qoriq/linux.git"

# ASK component directories
declare -g ASK_CDX_DIR="cdx"
declare -g ASK_FCI_DIR="fci"
declare -g ASK_AUTOBRIDGE_DIR="auto_bridge"
declare -g ASK_DPA_APP_DIR="dpa_app"
declare -g ASK_CMM_DIR="cmm"

# Mount local ASK repo into Docker container when using file:// URL
function host_pre_docker_launch__mount_local_ask() {
	if [[ "${ASK_REPO}" == file://* ]]; then
		local local_path="${ASK_REPO#file://}"
		DOCKER_EXTRA_ARGS+=("--mount" "type=bind,source=${local_path},target=${local_path},readonly")
		display_alert "ASK extension" "mounting local ASK repo into Docker: ${local_path}" "info"
	fi
}

# Override LINUXFAMILY so ASK-enabled kernels get distinct .deb names.
# Without this, ASK and non-ASK kernels both produce linux-image-current-ls1046a,
# colliding in the apt repo despite having different content (the ASK kernel patch).
function post_family_config__000_ask_override_family() {
	declare -g LINUXFAMILY="${LINUXFAMILY}-ask"
	declare -g LINUXCONFIG="linux-${LINUXFAMILY}-${BRANCH}"
	display_alert "ASK extension" "LINUXFAMILY=${LINUXFAMILY}, LINUXCONFIG=${LINUXCONFIG}" "info"
}

# Fetch ASK repo (sets ASK_CACHE_DIR for all later build phases)
# Uses post_family_config because the kernel patch staging hook needs it before fetch_sources_tools runs
function post_family_config__ask_fetch_repo() {
	# Skip during config-dump-json: no $HOME is set, fetch_from_repo would fail in git_ensure_safe_directory
	[[ "${CONFIG_DEFS_ONLY}" == "yes" || "${ARMBIAN_COMMAND}" == "download-artifact" ]] && {
		declare -g ASK_CACHE_DIR="${SRC}/cache/sources/ask-repo"
		return 0
	}
	# For local file:// repos in Docker, safe.directory is needed (container runs as root)
	# Use env vars instead of git config --global to avoid persistent side effects
	if [[ "${ASK_REPO}" == file://* ]]; then
		local local_path="${ASK_REPO#file://}"
		export GIT_CONFIG_COUNT=2
		export GIT_CONFIG_KEY_0="safe.directory" GIT_CONFIG_VALUE_0="${local_path}"
		export GIT_CONFIG_KEY_1="safe.directory" GIT_CONFIG_VALUE_1="${local_path}/.git"
	fi
	fetch_from_repo "${ASK_REPO}" "ask-repo" "${ASK_BRANCH}"
	unset GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0 GIT_CONFIG_KEY_1 GIT_CONFIG_VALUE_1 2> /dev/null
	declare -g ASK_CACHE_DIR="${SRC}/cache/sources/ask-repo"
}

# Post-config setup: enable kernel headers (userspace builds need FMAN UAPI headers)
# and derive multiarch triplet from KERNEL_COMPILER (set by arch config)
function extension_finish_config__ask_setup() {
	declare -g INSTALL_HEADERS="yes"
	[[ -z "${KERNEL_COMPILER}" ]] && exit_with_error "ASK extension: KERNEL_COMPILER is not set, cannot derive host triplet"
	declare -g ASK_HOST_TRIPLET="${KERNEL_COMPILER%-}"
}

# Copy ASK kernel module sources into the kernel tree and enable them in Kconfig.
# Runs during custom_kernel_config — AFTER patching (which does git reset + git clean),
# but BEFORE olddefconfig parses Kconfig. kernel_copy_extra_sources runs too early
# (files get wiped by git clean from CLEAN_LEVEL=make-kernel).
function custom_kernel_config__ask_modules() {
	# Invalidate kernel cache when ASK source changes (same pattern as Khadas meson-s4t7)
	kernel_config_modifying_hashes+=("ask_modules=${ASK_BRANCH}")

	# Skip file operations during config-dump-json and version calculation
	[[ ! -f .config ]] && return 0

	display_alert "ASK extension" "copying ASK module sources into kernel tree" "info"

	local ask_drv="${kernel_work_dir}/drivers/net/ethernet/freescale/ask"
	local bsp_dir="${SRC}/packages/bsp/gateway-dk"

	# Cleanup previous tree if it exists (otherwise copying again creates 1-deep duplicates)
	if [[ -d "${ask_drv}" ]]; then
		display_alert "ASK extension" "removing previous ASK module tree in kernel" "info"
		run_host_command_logged rm -rf "${ask_drv}"
	fi

	# Copy module sources and Kbuild files from ASK cache
	# (Kbuild files coexist with old Makefiles — kbuild prefers Kbuild when both exist)
	run_host_command_logged mkdir -pv "${ask_drv}"
	run_host_command_logged cp -av "${ASK_CACHE_DIR}/${ASK_CDX_DIR}" "${ask_drv}/cdx"
	run_host_command_logged cp -av "${ASK_CACHE_DIR}/${ASK_FCI_DIR}" "${ask_drv}/fci"
	run_host_command_logged cp -av "${ASK_CACHE_DIR}/${ASK_AUTOBRIDGE_DIR}" "${ask_drv}/auto_bridge"

	# Parent Kconfig + Makefile that wire the ASK modules into the in-tree build. ASK 1.0.0
	# dropped these from its repo root (Yocto/OpenWrt build the modules out-of-tree), so Armbian
	# carries them in the BSP; the per-module Kbuilds still gate on their CONFIG_ASK_* symbols.
	run_host_command_logged cp -v "${bsp_dir}/ask-modules.Kconfig" "${ask_drv}/Kconfig"
	run_host_command_logged cp -v "${bsp_dir}/ask-modules.Makefile" "${ask_drv}/Makefile"

	# Board-specific modules (not part of ASK repo — from Armbian BSP)
	if [[ "${BOARD}" == "gateway-dk" ]]; then
		run_host_command_logged mkdir -pv "${ask_drv}/sfp_led" "${ask_drv}/leds_lp5812"
		run_host_command_logged cp -v "${bsp_dir}/sfp-led.c" "${ask_drv}/sfp_led/"
		run_host_command_logged cp -v "${bsp_dir}/sfp-led.Kbuild" "${ask_drv}/sfp_led/Kbuild"
		run_host_command_logged cp -v "${bsp_dir}/leds-lp5812.c" "${ask_drv}/leds_lp5812/"
		run_host_command_logged cp -v "${bsp_dir}/leds-lp5812.h" "${ask_drv}/leds_lp5812/"
		run_host_command_logged cp -v "${bsp_dir}/leds-lp5812.Kbuild" "${ask_drv}/leds_lp5812/Kbuild"

		# Add board-specific entries to ASK Kconfig and Makefile
		patch -p1 -d "${ask_drv}" < "${bsp_dir}/ask-kconfig-board-modules.patch"
		echo 'obj-$(CONFIG_ASK_SFP_LED)	+= sfp_led/' >> "${ask_drv}/Makefile"
		echo 'obj-$(CONFIG_ASK_LEDS_LP5812)	+= leds_lp5812/' >> "${ask_drv}/Makefile"
	fi

	# Wire into parent freescale Kconfig and Makefile
	local fsl_dir="${kernel_work_dir}/drivers/net/ethernet/freescale"
	if ! grep -q 'source.*ask/Kconfig' "${fsl_dir}/Kconfig"; then
		display_alert "ASK extension" "adding ASK Kconfig to freescale Kconfig" "info"
		sed -i '/endif.*NET_VENDOR_FREESCALE/i source "drivers/net/ethernet/freescale/ask/Kconfig"' "${fsl_dir}/Kconfig"
		grep -q 'source.*ask/Kconfig' "${fsl_dir}/Kconfig" ||
			exit_with_error "ASK Kconfig source insert missed its anchor in freescale/Kconfig (mainline layout changed?)"
	else
		display_alert "ASK extension" "ASK Kconfig already present in freescale Kconfig" "info"
	fi

	if ! grep -q 'ask/' "${fsl_dir}/Makefile"; then
		display_alert "ASK extension" "adding ASK modules to freescale Makefile" "info"
		echo 'obj-y += ask/' >> "${fsl_dir}/Makefile"
	else
		display_alert "ASK extension" "ASK modules already present in freescale Makefile"
	fi

	display_alert "ASK extension" "ASK module sources and Kbuild files placed in kernel tree" "info"

	# Wire the SDK's fsl_qbman staging driver (provided by the 005 overlay) into
	# drivers/staging the same append way Armbian's own out-of-tree drivers do — post-patch
	# and idempotent, so it is immune to ordering. ASK patch 110's staging/{Makefile,Kconfig}
	# hunks were stripped at stage time because Armbian's driver harness echo-appends to those
	# files (rtl8723cs, ...) before the ASK series and breaks the patch context.
	local staging_dir="${kernel_work_dir}/drivers/staging"
	if [[ -d "${staging_dir}/fsl_qbman" ]]; then
		if ! grep -q 'fsl_qbman/' "${staging_dir}/Makefile"; then
			display_alert "ASK extension" "wiring fsl_qbman into staging Makefile" "info"
			echo 'obj-$(CONFIG_FSL_SDK_DPA) += fsl_qbman/' >> "${staging_dir}/Makefile"
		fi
		if ! grep -q 'fsl_qbman/Kconfig' "${staging_dir}/Kconfig"; then
			display_alert "ASK extension" "wiring fsl_qbman into staging Kconfig" "info"
			sed -i '/^endif # STAGING/i source "drivers/staging/fsl_qbman/Kconfig"\n' "${staging_dir}/Kconfig"
			grep -q 'fsl_qbman/Kconfig' "${staging_dir}/Kconfig" ||
				exit_with_error "fsl_qbman Kconfig source insert missed its anchor in staging/Kconfig (mainline layout changed?)"
		fi
	fi

	# Enable ASK modules in kernel config (opts_m array, same pattern as meson64_common.inc)
	opts_y+=("CONFIG_NXP_ASK")
	opts_m+=("CONFIG_ASK_CDX")
	opts_m+=("CONFIG_ASK_FCI")
	opts_m+=("CONFIG_ASK_AUTO_BRIDGE")
	if [[ "${BOARD}" == "gateway-dk" ]]; then
		opts_m+=("CONFIG_ASK_SFP_LED")
		opts_m+=("CONFIG_ASK_LEDS_LP5812")
	fi
}

# NXP SDK driver source absent from mainline — copied verbatim into its normal mainline
# locations. The path set is from the OpenWrt-first reference (scripts/mono-sync-ask-kernel.sh)
# and the Yocto meta-ask recipe, so all three consumers vendor the exact same tree. ASK-added
# files (e.g. include/linux/fsl_oh_port.h) arrive with the patch series, not here.
declare -ga ASK_SDK_PATHS=(
	"drivers/net/ethernet/freescale/sdk_dpaa"
	"drivers/net/ethernet/freescale/sdk_fman"
	"drivers/staging/fsl_qbman"
	"include/uapi/linux/fmd"
	"include/linux/fsl_bman.h"
	"include/linux/fsl_qman.h"
	"include/linux/fsl_usdpaa.h"
)

# SDK-flavour DPAA device tree. Mainline ships same-named files under freescale/ with mainline
# FMan/DPAA bindings the SDK drivers cannot probe. Rather than OVERWRITE mainline's copies —
# which the sibling ls1046a/QorIQ boards #include, so overwriting would silently rebuild THEIR
# dtbs with SDK bindings — these are dropped into a private freescale-sdk/ dir that only the
# Mono board's .dts pulls from (ASK_SDK_DTS_DIR below). The #include closure is self-contained
# within this set, so keeping the original filenames in a separate dir resolves correctly with
# ZERO changes to mainline's freescale/ tree. Filenames only (all live under freescale/ in the
# NXP source and freescale-sdk/ in ours).
declare -g ASK_SDK_DTS_DIR="arch/arm64/boot/dts/freescale-sdk"
declare -ga ASK_SDK_DTSI=(
	"qoriq-qman-portals-sdk.dtsi"
	"qoriq-bman-portals-sdk.dtsi"
	"qoriq-dpaa-eth.dtsi"
	"fsl-ls1046a.dtsi"
	"fsl-ls1046-post.dtsi"
	"qoriq-qman-portals.dtsi"
	"qoriq-bman-portals.dtsi"
	"qoriq-fman3-0.dtsi"
	"qoriq-fman3-0-1g-0.dtsi"
	"qoriq-fman3-0-1g-1.dtsi"
	"qoriq-fman3-0-1g-2.dtsi"
	"qoriq-fman3-0-1g-3.dtsi"
	"qoriq-fman3-0-1g-4.dtsi"
	"qoriq-fman3-0-1g-5.dtsi"
	"qoriq-fman3-0-10g-0.dtsi"
	"qoriq-fman3-0-10g-1.dtsi"
)

# Synthesize the kernel-side overlay patches from pinned upstream sources ($1 = dest dir):
#   005-nxp-sdk-overlay.patch            — NXP DPAA/FMan/QBMan SDK, fetched from NXP at the
#                                          ref ASK pins (the single source of truth)
#   006-mono-gateway-dk-devicetree.patch — the ASK-owned board device tree + its dtb-y entry
#
# Mainline carries neither, and Armbian's patcher git-resets the kernel tree and deletes
# every untracked file immediately before applying patches — so both must ARRIVE AS patches,
# not copied-in files. We overlay both onto a pristine mainline tree and capture the deltas as
# path-scoped unified diffs (one concern per patch). Armbian applies with `patch -p1` (not
# `git apply`), so these must be plain `git diff` (no --binary); all inputs are text. Diffing
# against the real mainline tree keeps the Makefile hunk context always correct — no stale
# vendor/usdpaa context to mismatch.
function ask_synthesize_kernel_overlay_patches() {
	declare patch_dst="$1"
	declare fsl_dts_dir="arch/arm64/boot/dts/freescale"

	# Single pin: read the NXP SDK ref from ASK's format-neutral pin file.
	declare pin_file="${ASK_CACHE_DIR}/pins/nxp-sdk-srcrev.inc"
	[[ -f "${pin_file}" ]] || exit_with_error "ASK NXP SDK pin file not found" "${pin_file}"
	declare sdk_ref
	sdk_ref="$(sed -n 's/^NXP_SDK_SRCREV *= *"\([0-9a-fA-F]\{40\}\)".*/\1/p' "${pin_file}" | head -1)"
	[[ -n "${sdk_ref}" ]] || exit_with_error "Could not read NXP_SDK_SRCREV from" "${pin_file}"
	declare dts_src="${ASK_CACHE_DIR}/dts/mono-gateway-dk.dts"
	[[ -f "${dts_src}" ]] || exit_with_error "ASK board DTS not found" "${dts_src}"
	display_alert "ASK extension" "NXP SDK overlay pinned @ ${sdk_ref}" "info"

	# Fetch the SDK via Armbian's helper: cached under cache/sources, mirror-aware. First fetch
	# of the NXP tree is large; subsequent builds reuse the cache. fetch_from_repo changes cwd.
	fetch_from_repo "${NXP_SDK_REPO}" "nxp-sdk-linux" "commit:${sdk_ref}"
	declare sdk_src="${SRC}/cache/sources/nxp-sdk-linux"
	cd "${kernel_work_dir}" || exit_with_error "Cannot cd back to kernel_work_dir" "${kernel_work_dir}"

	# Deterministic pristine-mainline diff base. kernel_drivers_create_patches ran before us,
	# and patching.py resets again after, so reset here to be certain.
	run_host_command_logged git -C "${kernel_work_dir}" reset --hard "${kernel_git_revision}"
	run_host_command_logged git -C "${kernel_work_dir}" clean -fdxq

	# Overlay 1 — NXP SDK driver source into its normal mainline locations (all absent on
	# mainline, so pure additions). Directories replace fully (rm+cp, no stale files).
	declare pth src dst
	for pth in "${ASK_SDK_PATHS[@]}"; do
		src="${sdk_src}/${pth}"
		dst="${kernel_work_dir}/${pth}"
		[[ -e "${src}" ]] || exit_with_error "NXP SDK path missing (ASK-added files come from the patch series)" "${pth} @ ${sdk_ref}"
		if [[ -d "${src}" ]]; then
			run_host_command_logged rm -rf "${dst}"
			run_host_command_logged mkdir -pv "${dst}"
			run_host_command_logged cp -a "${src}/." "${dst}/"
		else
			run_host_command_logged mkdir -pv "$(dirname "${dst}")"
			run_host_command_logged cp -a "${src}" "${dst}"
		fi
	done

	# Overlay 1b — SDK-flavour dtsi into the PRIVATE freescale-sdk/ dir (never touching mainline's
	# freescale/, so sibling ls1046a/QorIQ boards are unaffected). Original filenames; the
	# #include closure is self-contained within this set.
	run_host_command_logged mkdir -pv "${kernel_work_dir}/${ASK_SDK_DTS_DIR}"
	declare dtsi
	for dtsi in "${ASK_SDK_DTSI[@]}"; do
		src="${sdk_src}/${fsl_dts_dir}/${dtsi}"
		[[ -f "${src}" ]] || exit_with_error "NXP SDK dtsi missing" "${dtsi} @ ${sdk_ref}"
		run_host_command_logged cp -a "${src}" "${kernel_work_dir}/${ASK_SDK_DTS_DIR}/${dtsi}"
	done

	# Overlay 2 — ASK-owned board dts + a private Makefile in freescale-sdk/, and wire that dir
	# into the arm64 dts build. We own the whole dir, so there is no anchor into a shared file.
	run_host_command_logged cp -a "${dts_src}" "${kernel_work_dir}/${ASK_SDK_DTS_DIR}/mono-gateway-dk.dts"
	echo 'dtb-$(CONFIG_ARCH_LAYERSCAPE) += mono-gateway-dk.dtb' > "${kernel_work_dir}/${ASK_SDK_DTS_DIR}/Makefile"
	declare top_mk="${kernel_work_dir}/arch/arm64/boot/dts/Makefile"
	if ! grep -q 'subdir-y += freescale-sdk' "${top_mk}"; then
		# subdir-y order is irrelevant, so append — no anchor to drift against.
		echo 'subdir-y += freescale-sdk' >> "${top_mk}"
	fi

	# Capture path-scoped diffs. git diff exits 1 when there are changes, so guard against
	# errexit; the non-empty checks catch a genuine failure.
	declare -a sdk_dtsi_paths=()
	for dtsi in "${ASK_SDK_DTSI[@]}"; do sdk_dtsi_paths+=("${ASK_SDK_DTS_DIR}/${dtsi}"); done
	run_host_command_logged git -C "${kernel_work_dir}" add -A
	git -C "${kernel_work_dir}" diff --cached --no-color --no-ext-diff -- "${ASK_SDK_PATHS[@]}" "${sdk_dtsi_paths[@]}" \
		> "${patch_dst}/005-nxp-sdk-overlay.patch" || true
	git -C "${kernel_work_dir}" diff --cached --no-color --no-ext-diff -- \
		"${ASK_SDK_DTS_DIR}/mono-gateway-dk.dts" "${ASK_SDK_DTS_DIR}/Makefile" "arch/arm64/boot/dts/Makefile" \
		> "${patch_dst}/006-mono-gateway-dk-devicetree.patch" || true
	[[ -s "${patch_dst}/005-nxp-sdk-overlay.patch" ]] || exit_with_error "Synthesized SDK overlay diff is empty" "005"
	[[ -s "${patch_dst}/006-mono-gateway-dk-devicetree.patch" ]] || exit_with_error "Synthesized board DTS diff is empty" "006"
	# Armbian applies with patch(1), which cannot carry git binary hunks. Without --binary,
	# `git diff` emits a payload-less "Binary files … differ" marker → the file would be
	# SILENTLY dropped from the overlay. Fail loud if a future SDK/DTS ref introduces one.
	declare synth
	for synth in "${patch_dst}/005-nxp-sdk-overlay.patch" "${patch_dst}/006-mono-gateway-dk-devicetree.patch"; do
		! grep -q "^Binary files " "${synth}" ||
			exit_with_error "Synthesized overlay contains a binary file patch(1) cannot apply" "${synth##*/}"
	done

	# Restore pristine mainline; patching.py resets again and re-applies 005/006 + 010-110.
	run_host_command_logged git -C "${kernel_work_dir}" reset --hard "${kernel_git_revision}"
	run_host_command_logged git -C "${kernel_work_dir}" clean -fdxq
	display_alert "ASK extension" "synthesized SDK overlay (005) + board device tree (006)" "info"
}

# Copy a kernel patch ($1 -> $2), dropping any file-section that targets
# drivers/staging/Makefile or drivers/staging/Kconfig. Armbian's driver harness
# echo-appends out-of-tree drivers to those files before the ASK series, so the SDK's
# fsl_qbman wiring (ASK patch 110) cannot apply by patch context; it is re-added
# post-patch in custom_kernel_config__ask_modules. Every other hunk is preserved.
function ask_strip_staging_wiring_hunks() {
	local src="$1" dst="$2"

	# We re-add only the fsl_qbman wiring post-patch, so a staging section that wires a
	# DIFFERENT driver would be silently lost. Collect any offending added line (ignoring the
	# +++ header and blank '+' lines); if there are none, the assumption still holds.
	local stray
	stray=$(awk '
		/^diff --git / { in_staging = ($0 ~ /b\/drivers\/staging\/(Makefile|Kconfig)$/) }
		in_staging && /^\+[^+]/ && /[^+[:space:]]/ && !/fsl_qbman/ { print }
	' "$src")
	[[ -z "$stray" ]] ||
		exit_with_error "ASK patch $(basename "$src") wires a non-fsl_qbman staging driver; strip would lose it" "$stray"

	# Copy the patch, dropping the drivers/staging/{Makefile,Kconfig} file-sections.
	awk '
		/^diff --git / { drop = ($0 ~ /b\/drivers\/staging\/(Makefile|Kconfig)$/) }
		!drop
	' "$src" > "$dst"
}

# Stage the kernel-side ASK inputs into userpatches so Armbian's patcher applies them. Under
# the ASK-is-single-source-of-truth model the ls1046a patch/kernel/ dir carries no ASK/board
# patches — everything here comes from the pinned ASK tree (or NXP at ASK's pin):
#   005-nxp-sdk-overlay.patch            — synthesized NXP SDK overlay (see above)
#   006-mono-gateway-dk-devicetree.patch — synthesized ASK board device tree (see above)
#   010-110                              — ASK hook series + SDK-on-mainline build/fix patches
# userpatches/ is the Armbian-standard location for extension-provided patches; the build
# framework merges them with the committed patches in patch/kernel/ at build time. Runs
# immediately before patching, after hashing (staging here does not perturb the kernel hash).
function kernel_extra_create_patches__ask_kernel_patches() {
	[[ "${CONFIG_DEFS_ONLY}" == "yes" ]] && return 0 # cache not populated during config-dump-json
	declare patch_dst="${SRC}/userpatches/kernel/${KERNELPATCHDIR}"
	declare manifest="${patch_dst}/.ask-staged"
	run_host_command_logged mkdir -pv "${patch_dst}"

	# Record exactly what we stage into this (user-owned) dir, so the pre-hash cleanup removes
	# only our files and never blanket-rm's a user's own patches.
	: > "${manifest}"

	# 1. NXP SDK overlay (005) + ASK board device tree (006); both sort before the 010-110
	#    hooks (005 provides the SDK sources those hooks edit).
	ask_synthesize_kernel_overlay_patches "${patch_dst}"
	printf '%s\n' "005-nxp-sdk-overlay.patch" "006-mono-gateway-dk-devicetree.patch" >> "${manifest}"

	# 2. ASK hook + fix series 010-110, straight from the pinned ASK tree. Skip the legacy
	#    5.4 reference monolith (999-*); match every numeric-prefixed patch so nothing (e.g.
	#    100+) is silently dropped. Each patch is filtered to drop drivers/staging/{Makefile,
	#    Kconfig} hunks — Armbian's driver harness echo-appends out-of-tree drivers
	#    (rtl8723cs, ...) to those files BEFORE the ASK series, breaking patch context for the
	#    SDK's fsl_qbman wiring; that wiring is re-added collision-proof post-patch in
	#    custom_kernel_config__ask_modules. Non-staging hunks are preserved verbatim.
	declare ask_patch b staged=0
	shopt -s nullglob
	for ask_patch in "${ASK_CACHE_DIR}"/patches/kernel/[0-9]*.patch; do
		b="$(basename "${ask_patch}")"
		[[ "${b}" == 999-* ]] && continue
		ask_strip_staging_wiring_hunks "${ask_patch}" "${patch_dst}/${b}"
		echo "${b}" >> "${manifest}"
		staged=$((staged + 1))
	done
	shopt -u nullglob
	[[ "${staged}" -gt 0 ]] || exit_with_error "No ASK kernel patches found" "${ASK_CACHE_DIR}/patches/kernel/[0-9]*.patch"
	display_alert "ASK extension" "staged SDK overlay + ${staged} ASK kernel patches in userpatches" "info"
}

# Remove ONLY the patches this extension staged in a previous build (tracked in .ask-staged),
# then the manifest. userpatches/kernel/ is a user-owned drop location, so we must never
# blanket-rm *.patch there. Runs in post_family_config (pre-hashing) so stale staged patches
# never perturb the patch-dir hash; the current build re-stages + re-writes the manifest later.
function post_family_config__cleanup_ask_kernel_patch() {
	declare patch_dst="${SRC}/userpatches/kernel/${KERNELPATCHDIR}"
	declare manifest="${patch_dst}/.ask-staged"
	[[ -f "${manifest}" ]] || {
		display_alert "ASK extension" "no ASK-staged patch manifest, nothing to remove" "info"
		return 0
	}
	display_alert "ASK extension" "clearing previously ASK-staged kernel patches (manifest-tracked)" "info"
	declare f
	while IFS= read -r f; do
		[[ -n "${f}" ]] && run_host_command_logged rm -fv "${patch_dst}/${f}"
	done < "${manifest}"
	run_host_command_logged rm -f "${manifest}"
	return 0
}

# Install module autoload config (modules are in the kernel .deb, just need the load list)
function post_install_kernel_debs__ask_module_autoload() {
	cp "${ASK_CACHE_DIR}/config/ask-modules.conf" "${SDCARD}/etc/modules-load.d/"
}

# Copy patches into chroot before patched library builds (runs before build_ask_userspace)
function pre_customize_image__000_prepare_ask_patches() {
	# Stage per-package trees (version subdirs preserved) so rebuild_patched_deb
	# can pick the patch matching the upstream source version.
	local patch_dirs=("libnetfilter-conntrack" "libnfnetlink")
	for pdir in "${patch_dirs[@]}"; do
		[[ -d "${ASK_CACHE_DIR}/patches/${pdir}" ]] || exit_with_error "ASK patch directory missing" "${ASK_CACHE_DIR}/patches/${pdir}"
		mkdir -p "${SDCARD}/tmp/ask-patches/${pdir}"
		cp -a "${ASK_CACHE_DIR}/patches/${pdir}/." "${SDCARD}/tmp/ask-patches/${pdir}/"
	done

	# Enable deb-src for apt-get source (handles both Debian and Ubuntu)
	# deb822 format: *.sources files (Debian bookworm+, Ubuntu noble+)
	# Legacy format: sources.list (older Debian/Ubuntu)
	chroot_sdcard "shopt -s nullglob; \
		for f in /etc/apt/sources.list.d/*.sources; do \
			sed -i 's/^Types: deb\$/Types: deb deb-src/' \"\$f\"; \
		done; \
		if [ -f /etc/apt/sources.list ]; then \
			sed -i 's/^#\\s*deb-src/deb-src/' /etc/apt/sources.list; \
		fi && apt-get update -qq"
	chroot_sdcard_apt_get_install dpkg-dev devscripts
}

# Build and install all ASK userspace components
function pre_customize_image__001_build_ask_userspace() {
	display_alert "ASK extension" "building userspace components" "info"

	local kernel_ver
	kernel_ver=$(ls -1v "${SDCARD}/lib/modules/" | tail -1)
	[[ -z "${kernel_ver}" ]] && exit_with_error "No kernel version found in ${SDCARD}/lib/modules/"
	local kdir="/usr/src/linux-headers-${kernel_ver}"

	# Install build dependencies and runtime packages in chroot
	# iptables is a runtime dep — CMM uses QOSMARK rules via our xtables extensions
	display_alert "ASK extension" "installing build dependencies" "info"
	chroot_sdcard_apt_get_install build-essential \
		pkg-config libxml2-dev libpcap-dev libcrypt-dev libtclap-dev libxtables-dev \
		iptables

	# Copy sources into chroot
	mkdir -p "${SDCARD}/tmp/ask-userspace"

	# --- fmlib ---
	display_alert "ASK extension" "building fmlib" "info"
	fetch_from_repo "${FMLIB_REPO}" "fmlib" "commit:${FMLIB_COMMIT}"
	cp -a "${SRC}/cache/sources/fmlib" "${SDCARD}/tmp/ask-userspace/fmlib"
	cp "${ASK_CACHE_DIR}/patches/fmlib/"*.patch "${SDCARD}/tmp/ask-userspace/"

	chroot_sdcard "cd /tmp/ask-userspace/fmlib && \
		patch -p1 < /tmp/ask-userspace/01-mono-ask-extensions.patch && \
		make KERNEL_SRC=${kdir} libfm-arm.a && \
		make DESTDIR=/ PREFIX=/usr LIB_DEST_DIR=/usr/lib/${ASK_HOST_TRIPLET} install-libfm-arm" ||
		exit_with_error "fmlib build failed"

	# --- fmc ---
	display_alert "ASK extension" "building fmc" "info"
	fetch_from_repo "${FMC_REPO}" "fmc" "commit:${FMC_COMMIT}"
	cp -a "${SRC}/cache/sources/fmc" "${SDCARD}/tmp/ask-userspace/fmc"
	cp "${ASK_CACHE_DIR}/patches/fmc/"*.patch "${SDCARD}/tmp/ask-userspace/"

	chroot_sdcard "cd /tmp/ask-userspace/fmc && \
		patch -p1 < /tmp/ask-userspace/01-mono-ask-extensions.patch && \
		make MACHINE=ls1043 \
			FMD_USPACE_HEADER_PATH=/usr/include/fmd \
			FMD_USPACE_LIB_PATH=/usr/lib/${ASK_HOST_TRIPLET} \
			LIBXML2_HEADER_PATH=/usr/include/libxml2 \
			TCLAP_HEADER_PATH=/usr/include \
			-C source && \
		install -m 755 source/fmc /usr/bin/ && \
		install -d /usr/include/fmc && \
		install -m 644 source/fmc.h /usr/include/fmc/ && \
		install -m 644 source/libfmc.a /usr/lib/${ASK_HOST_TRIPLET}/ && \
		install -d /etc/fmc/config && \
		install -m 644 etc/fmc/config/* /etc/fmc/config/" ||
		exit_with_error "fmc build failed"

	# --- libcli ---
	display_alert "ASK extension" "building libcli" "info"
	fetch_from_repo "${LIBCLI_REPO}" "libcli" "commit:${LIBCLI_COMMIT}"
	cp -a "${SRC}/cache/sources/libcli" "${SDCARD}/tmp/ask-userspace/libcli"

	chroot_sdcard "cd /tmp/ask-userspace/libcli && \
		make CFLAGS='-Wno-calloc-transposed-args' && \
		make PREFIX=/usr DESTDIR=/ install" ||
		exit_with_error "libcli build failed"

	# --- libfci ---
	display_alert "ASK extension" "building libfci" "info"
	cp -a "${ASK_CACHE_DIR}/${ASK_FCI_DIR}/lib" "${SDCARD}/tmp/ask-userspace/libfci"

	chroot_sdcard "cd /tmp/ask-userspace/libfci && \
		make && \
		install -m 644 libfci.a /usr/lib/${ASK_HOST_TRIPLET}/ && \
		install -m 644 include/libfci.h /usr/include/" ||
		exit_with_error "libfci build failed"

	# --- dpa-app ---
	display_alert "ASK extension" "building dpa-app" "info"
	cp -a "${ASK_CACHE_DIR}/${ASK_DPA_APP_DIR}" "${SDCARD}/tmp/ask-userspace/dpa-app"
	# Copy CDX header
	mkdir -p "${SDCARD}/usr/include/cdx"
	cp "${ASK_CACHE_DIR}/${ASK_CDX_DIR}/cdx_ioctl.h" "${SDCARD}/usr/include/cdx/"

	chroot_sdcard "cd /tmp/ask-userspace/dpa-app && \
		make CC=gcc \
			CFLAGS='-DENDIAN_LITTLE -DLS1043 -DNCSW_LINUX -DDPAA_DEBUG_ENABLE -DSEC_PROFILE_SUPPORT -DVLAN_FILTER \
				-I/usr/include/fmc -I/usr/include/fmd -I/usr/include/fmd/integrations \
				-I/usr/include/fmd/Peripherals -I/usr/include/fmd/Peripherals/common -I/usr/include/cdx' \
			LDFLAGS='-lfmc -lfm-arm -lstdc++ -lxml2 -lpthread -lcli' && \
		install -m 755 dpa_app /usr/bin/" ||
		exit_with_error "dpa-app build failed"

	# Install DPA-App config files (from ASK repo)
	cp "${ASK_CACHE_DIR}/config/gateway-dk/cdx_cfg.xml" "${SDCARD}/etc/"
	cp "${ASK_CACHE_DIR}/${ASK_DPA_APP_DIR}/files/etc/cdx_pcd.xml" "${SDCARD}/etc/"
	cp "${ASK_CACHE_DIR}/${ASK_DPA_APP_DIR}/files/etc/cdx_sp.xml" "${SDCARD}/etc/"

	# --- xtables extensions (standalone .so files, not patching iptables) ---
	# Note: we don't use pkg-config for libxtables here. These are dlopen()-loaded
	# extensions — they don't link against libxtables.so, they use symbols resolved
	# from the iptables process that loads them. The -I./include picks up our local
	# xt_QOSMARK.h etc. UAPI headers which aren't in libxtables-dev (they're our
	# additions). Adding -lxtables would cause duplicate symbol issues at load time.
	local ask_xtables_modules=(libxt_qosmark libxt_QOSMARK libxt_qosconnmark libxt_QOSCONNMARK)
	display_alert "ASK extension" "building xtables extensions" "info"
	cp -a "${ASK_CACHE_DIR}/iptables-extensions" "${SDCARD}/tmp/ask-userspace/iptables-extensions"
	chroot_sdcard "cd /tmp/ask-userspace/iptables-extensions && \
		for name in ${ask_xtables_modules[*]}; do \
			gcc -shared -fPIC -O2 \
				-I./include \
				-o \"\${name}.so\" \"\${name}.c\" || exit 1; \
		done && \
		install -d /usr/lib/${ASK_HOST_TRIPLET}/xtables && \
		for name in ${ask_xtables_modules[*]}; do \
			install -m 644 \"\${name}.so\" /usr/lib/${ASK_HOST_TRIPLET}/xtables/ || exit 1; \
		done" ||
		exit_with_error "xtables extensions build failed"

	# --- Patched system libraries (must be before CMM which depends on patched libnetfilter-conntrack) ---
	build_ask_patched_libraries

	# --- cmm ---
	display_alert "ASK extension" "building cmm" "info"
	cp -a "${ASK_CACHE_DIR}/${ASK_CMM_DIR}" "${SDCARD}/tmp/ask-userspace/cmm"
	# Copy auto-bridge header for CMM
	cp "${ASK_CACHE_DIR}/${ASK_AUTOBRIDGE_DIR}/include/auto_bridge.h" "${SDCARD}/usr/include/"

	# CMM's Makefile sets base CFLAGS (with +=) internally and uses pkg-config for
	# libnetfilter_conntrack. auto_bridge.h already at /usr/include, libfci built in-tree.
	# Extra defines passed as env var so Makefile's += appends to them (not overrides).
	chroot_sdcard "cd /tmp/ask-userspace/cmm && \
		make clean || true && \
		CFLAGS='-DFLOW_STATS -DSEC_PROFILE_SUPPORT -DUSE_QOSCONNMARK \
			-DENABLE_INGRESS_QOS -DIPSEC_NO_FLOW_CACHE -DVLAN_FILTER' \
		make \
			LIBFCI_DIR=/tmp/ask-userspace/libfci \
			ABM_DIR=/usr \
			SYSROOT=/ && \
		install -m 755 src/cmm /usr/bin/" ||
		exit_with_error "cmm build failed"

	# Install and enable CMM service (from ASK repo)
	# Guarded by ConditionPathExists=/dev/cdx_ctrl — won't start without ASK FMAN ucode on NOR
	cp "${ASK_CACHE_DIR}/config/cmm.service" "${SDCARD}/etc/systemd/system/"
	mkdir -p "${SDCARD}/etc/config"
	cp "${ASK_CACHE_DIR}/config/fastforward" "${SDCARD}/etc/config/"
	chroot_sdcard systemctl enable cmm.service

	# Pin patched packages — ASK patches add kernel offloading hooks (comcerto-fp,
	# QOSMARK/QOSCONNMARK) that don't exist upstream.  An apt upgrade would replace
	# them with vanilla Debian builds and break CMM/CDX data-plane acceleration.
	# These are shipped as separate .debs (not bundled into gateway-dk-ask) because
	# they replace system packages and must be managed by dpkg as proper overrides.
	# The postinst re-applies holds on every upgrade. Security updates must be
	# tracked and re-patched manually.
	display_alert "ASK extension" "pinning patched packages" "info"
	chroot_sdcard "apt-mark hold libnetfilter-conntrack3 libnfnetlink0"

	# Install sysctl tuning for conntrack
	install -Dm 644 "${SRC}/packages/bsp/gateway-dk/99-ls1046a-conntrack.conf" \
		"${SDCARD}/etc/sysctl.d/99-ls1046a-conntrack.conf"

	# Cleanup build sources
	rm -rf "${SDCARD}/tmp/ask-userspace" "${SDCARD}/tmp/ask-patches"

	# --- Package ASK userspace as a .deb (kernel modules are in linux-image .deb) ---
	display_alert "ASK extension" "packaging ASK userspace .deb" "info"
	local pkgname="gateway-dk-ask"
	local pkgdir
	pkgdir=$(mktemp -d)
	mkdir -p "${pkgdir}/DEBIAN"

	# Snapshot userspace files into package tree
	local -a ask_files=(
		usr/bin/fmc
		usr/bin/dpa_app
		usr/bin/cmm
		etc/fmc
		etc/cdx_cfg.xml
		etc/cdx_pcd.xml
		etc/cdx_sp.xml
		etc/systemd/system/cmm.service
		etc/config/fastforward
		etc/sysctl.d/99-ls1046a-conntrack.conf
		usr/include/fmc
		usr/include/fmd
		usr/include/libfci.h
		usr/include/cdx
		usr/include/auto_bridge.h
	)
	for f in "${ask_files[@]}"; do
		if [[ -e "${SDCARD}/${f}" ]]; then
			mkdir -p "$(dirname "${pkgdir}/${f}")"
			cp -a "${SDCARD}/${f}" "${pkgdir}/${f}"
		fi
	done
	# Libraries — snapshot all ASK-installed libs from chroot
	mkdir -p "${pkgdir}/usr/lib/${ASK_HOST_TRIPLET}"
	for lib in libfm-arm.a libfmc.a; do
		[[ -f "${SDCARD}/usr/lib/${ASK_HOST_TRIPLET}/${lib}" ]] &&
			cp -a "${SDCARD}/usr/lib/${ASK_HOST_TRIPLET}/${lib}" "${pkgdir}/usr/lib/${ASK_HOST_TRIPLET}/"
	done
	for pattern in libcli libfci; do
		for f in "${SDCARD}/usr/lib/${ASK_HOST_TRIPLET}/"${pattern}*; do
			[[ -f "$f" ]] && cp -a "$f" "${pkgdir}/usr/lib/${ASK_HOST_TRIPLET}/"
		done
	done

	# xtables extensions — use the same explicit list as the build step
	local ask_xtables_modules=(libxt_qosmark libxt_QOSMARK libxt_qosconnmark libxt_QOSCONNMARK)
	mkdir -p "${pkgdir}/usr/lib/${ASK_HOST_TRIPLET}/xtables"
	for name in "${ask_xtables_modules[@]}"; do
		local src="${SDCARD}/usr/lib/${ASK_HOST_TRIPLET}/xtables/${name}.so"
		[[ -f "${src}" ]] || exit_with_error "xtables extension missing" "${name}.so"
		cp -a "${src}" "${pkgdir}/usr/lib/${ASK_HOST_TRIPLET}/xtables/"
	done

	# Version: kernel version + build date — allows bugfix rebuilds without kernel change
	local ask_version="${kernel_ver}+$(date +%Y%m%d)"

	# Depends uses >= (not =): this is intentional. The kernel may receive minor version bumps
	# without ASK changes. Using = would require rebuilding ASK for every kernel point release
	# even when the modules are unchanged. The modules are ABI-compatible within the same
	# LINUXFAMILY and BRANCH. DKMS is not used — this is a controlled appliance where both
	# packages are built and validated together.
	cat > "${pkgdir}/DEBIAN/control" << EOF
Package: ${pkgname}
Version: ${ask_version}
Architecture: arm64
Section: net
Priority: optional
Maintainer: ${MAINTAINER} <${MAINTAINERMAIL}>
Depends: linux-image-${BRANCH}-${LINUXFAMILY} (>= ${kernel_ver}), libxml2 | libxml2-16, libpcap0.8, iptables
Description: NXP ASK hardware offloading userspace for Mono Gateway DK
 Userspace tools (fmlib, fmc, libfci, libcli, dpa-app, cmm) and configuration
 for NXP ASK data-plane acceleration on the LS1046A Gateway DK.
 Kernel modules (CDX, FCI, auto-bridge, sfp-led, leds-lp5812) are in the
 linux-image package.
EOF

	cat > "${pkgdir}/DEBIAN/postinst" << EOF
#!/bin/bash
systemctl daemon-reload || true
ldconfig || true
# Enable CMM service on OTA install (guarded by ConditionPathExists=/dev/cdx_ctrl at runtime)
if command -v systemctl >/dev/null 2>&1; then
    systemctl enable cmm.service 2>/dev/null || true
fi
# Re-pin patched ASK libraries — vanilla Debian versions break CMM/CDX offloading
apt-mark hold libnetfilter-conntrack3 libnfnetlink0 2>/dev/null || true
EOF
	chmod 755 "${pkgdir}/DEBIAN/postinst"

	cat > "${pkgdir}/DEBIAN/prerm" << 'EOF'
#!/bin/bash
systemctl stop cmm.service 2>/dev/null || true
EOF
	chmod 755 "${pkgdir}/DEBIAN/prerm"

	cat > "${pkgdir}/DEBIAN/postrm" << EOF
#!/bin/bash
ldconfig || true
systemctl daemon-reload || true
if [ "\$1" = "remove" ] || [ "\$1" = "purge" ]; then
    apt-mark unhold libnetfilter-conntrack3 libnfnetlink0 2>/dev/null || true
fi
EOF
	chmod 755 "${pkgdir}/DEBIAN/postrm"

	cat > "${pkgdir}/DEBIAN/conffiles" << 'CONFFILES'
/etc/cdx_cfg.xml
/etc/cdx_pcd.xml
/etc/cdx_sp.xml
/etc/config/fastforward
/etc/fmc/config/cfgdata.xsd
/etc/fmc/config/hxs_pdl_v3.xml
/etc/fmc/config/netpcd.xsd
/etc/sysctl.d/99-ls1046a-conntrack.conf
CONFFILES

	# Build .deb once, install in chroot and save to output
	local debfile="${pkgname}_${ask_version}_arm64.deb"
	mkdir -p "${SRC}/output/debs"
	run_host_command_logged dpkg-deb -b "${pkgdir}" "${SRC}/output/debs/${debfile}" ||
		exit_with_error "dpkg-deb failed for ${debfile}"
	cp "${SRC}/output/debs/${debfile}" "${SDCARD}/root/"
	chroot_sdcard "DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends /root/${debfile}" ||
		exit_with_error "apt install failed for ${debfile}"
	rm -f "${SDCARD}/root/${debfile}"

	rm -rf "${pkgdir}"

	display_alert "ASK extension" "ASK packaged and installed: ${debfile}" "info"
}

# Build patched versions of system libraries
function build_ask_patched_libraries() {
	# Install all build dependencies upfront
	display_alert "ASK extension" "installing build deps for patched libraries" "info"
	chroot_sdcard "DEBIAN_FRONTEND=noninteractive apt-get -y build-dep \
		libnetfilter-conntrack libnfnetlink"

	# Staging dir for patched .debs (saved to output later)
	mkdir -p "${SDCARD}/tmp/ask-patched-debs"

	# Rebuild each patched library in an isolated directory
	rebuild_patched_deb "libnetfilter-conntrack" \
		"01-nxp-ask-comcerto-fp-extensions.patch" \
		"libnetfilter-conntrack3_*.deb libnetfilter-conntrack-dev_*.deb"

	rebuild_patched_deb "libnfnetlink" \
		"01-nxp-ask-nonblocking-heap-buffer.patch" \
		"libnfnetlink0_*.deb libnfnetlink-dev_*.deb"

	# Copy patched .debs to output for distribution
	mkdir -p "${SRC}/output/debs"
	cp "${SDCARD}"/tmp/ask-patched-debs/*.deb "${SRC}/output/debs/" 2> /dev/null || true
	rm -rf "${SDCARD}/tmp/ask-patched-debs"
}

# Helper: rebuild a Debian package with an ASK patch in an isolated chroot directory.
# Usage: rebuild_patched_deb <pkg_name> <patch_file> <deb_globs>
# The patch is resolved under /tmp/ask-patches/<pkg>/<upstream_version>/<patch_file>,
# where <upstream_version> is parsed from the source tree's debian/changelog after
# apt-get source. This lets a single ASK repo cover multiple target distros whose
# upstream library versions differ (e.g. Trixie/Noble 1.1.0 vs Resolute 1.1.1).
function rebuild_patched_deb() {
	local pkg="$1" patch="$2" debs="$3"
	local workdir="/tmp/ask-rebuild-${pkg}"

	display_alert "ASK extension" "rebuilding ${pkg}" "info"
	# Note: ${debs} is intentionally unquoted — it contains globs that must expand in the chroot
	chroot_sdcard "set -e && \
		rm -rf '${workdir}' && mkdir -p '${workdir}' && cd '${workdir}' && \
		apt-get source '${pkg}' && \
		cd \$(ls -d ${pkg}-*/ | head -1) && \
		upstream_ver=\$(dpkg-parsechangelog -l debian/changelog -S Version \
			| sed -E 's/^[0-9]+://; s/-[^-]+\$//; s/^([0-9]+\\.[0-9]+\\.[0-9]+).*/\\1/') && \
		patch_path=\"/tmp/ask-patches/${pkg}/\${upstream_ver}/${patch}\" && \
		if [ ! -f \"\${patch_path}\" ]; then \
			echo \"ERROR: no ASK patch for ${pkg} upstream \${upstream_ver} (looked for \${patch_path})\" >&2; \
			exit 1; \
		fi && \
		patch -p1 < \"\${patch_path}\" && \
		DEB_BUILD_OPTIONS=nocheck dpkg-buildpackage -b -uc -us && \
		cd '${workdir}' && dpkg -i ${debs} && \
		cp ${debs} /tmp/ask-patched-debs/ && \
		rm -rf '${workdir}'" || exit_with_error "${pkg} rebuild failed"
}
