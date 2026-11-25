#!/usr/bin/env bash
# @description Integrates NXP's ASK data-plane acceleration for the Mono Gateway DK (LS1046A). Overlays ASK's copy of the NXP DPAA/FMan/QBMan SDK and its kernel patch series onto the mainline kernel, builds the ASK kernel modules (`cdx`, `ask_flowtable`, sfp-led, lp5812) in-tree, and packages the `ask-flowtable` offload daemon as `gateway-dk-ask` `.deb`. Also ships the NXP 88W9098 WiFi driver and firmware as `gateway-dk-wifi` `.deb`.

#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Mono Technologies Inc.
#
# NXP ASK (Application Solutions Kit) extension for LS1046A
#
# ASK 1.6.0 (flowtable model): the data plane is an nftables flowtable driven
# into CDX hardware. Two kernel modules (cdx, ask_flowtable) build IN-TREE from
# the ASK repo's consolidated cdx/ dir (the SDK source they #include is only
# present during the kernel's own `make modules`, so an out-of-tree build
# against the trimmed linux-headers .deb cannot see it) and ship in the
# linux-image .deb. Userspace is a single libc-only daemon, ask-flowtable, built
# from the repo's flowtable/ dir; it shells out to nft/ip at runtime and ships
# in gateway-dk-ask with its systemd unit and config.
#
# The pre-1.1.0 userspace stack (fmlib, fmc, libfci, libcli, dpa-app, cmm), the
# patched system libraries (libnetfilter-conntrack, libnfnetlink), the QOSMARK/
# QOSCONNMARK xtables extensions and the FMan-PCD XMLs are all gone: the PCD is
# now built in-kernel (cdx/cdx_pcd.c) and offload is nftables-native.
#
# Board-specific LED modules (sfp-led, lp5812) remain in-tree BSP. All ASK
# sources, patches, and configs come from the ASK repo.
#

# Source repos and refs (pinned to match Yocto)
# For local testing: set ASK_REPO="file:///path/to/ASK" — the Docker mount hook below handles it
declare -g ASK_REPO="https://github.com/we-are-mono/ASK.git"
declare -g ASK_BRANCH="commit:27eed72e926bf54b41cb055c51a0487630f797f9" # mono-1.6.1 (peeled commit)

# NXP DPAA/FMan/QBMan SDK source. Mainline does not carry these drivers, so the
# kernel base (kernel.org stable, set in the ls1046a family config) is overlaid with
# them before the ASK hook patches apply. Since ASK 1.6.0 the SDK is ASK's own copy
# (sdk/linux in the ASK repo: NXP's drivers with ASK's fixes made in place, one copy
# for every kernel line), so ASK_BRANCH is the single pin and nothing is fetched from NXP.

# NXP 88W9098 (u-blox JODY-W3) WiFi+BT combo — an optional PCIe card. The mlan/moal
# fullmac WiFi driver and the combo firmware are baked into every gateway image (inert
# with no card present, and the firmware also quiets the DTS-declared BT node's
# btnxpuart probe). Built as a standalone kernel-module .deb (gateway-dk-wifi), NOT
# in-tree, so it tracks the kernel .deb loosely. Driver pin matches ASK's meta-ask
# nxp-mwifiex recipe for this kernel line.
declare -g NXP_MWIFIEX_REPO="https://github.com/nxp-imx/mwifiex.git"
declare -g NXP_MWIFIEX_COMMIT="09f41e1423e4806a127507d5fa284cd02c46772f" # branch hotfix/lf-6.12.49_2.2.0_hotfix
declare -g NXP_WIFI_FW_REPO="https://github.com/nxp-imx/imx-firmware.git"
declare -g NXP_WIFI_FW_COMMIT="8c9b278016c97527b285f2fcbe53c2d428eb171d" # tag lf-6.12.49_2.2.0 (FwImage_9098_PCIE)

# ASK component directories
declare -g ASK_CDX_DIR="cdx"             # out-of-tree kernel modules: cdx.ko + ask_flowtable.ko
declare -g ASK_FLOWTABLE_DIR="flowtable" # libc-only userspace daemon: ask-flowtable

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

# Post-config setup: ship the linux-headers .deb in the image. The WiFi driver
# (__002) builds mlan/moal out-of-tree against them; ask-flowtable is libc-only
# and the in-tree ASK modules build with the kernel, so neither needs headers.
function extension_finish_config__ask_setup() {
	declare -g INSTALL_HEADERS="yes"
}

# Copy ASK kernel module sources into the kernel tree and enable them in Kconfig.
# Runs during custom_kernel_config — AFTER patching (which does git reset + git clean),
# but BEFORE olddefconfig parses Kconfig. kernel_copy_extra_sources runs too early
# (files get wiped by git clean from CLEAN_LEVEL=make-kernel).
function custom_kernel_config__ask_modules() {
	# Invalidate kernel cache when ASK source changes (same pattern as Khadas meson-s4t7)
	kernel_config_modifying_hashes+=("ask_modules=${ASK_BRANCH}")
	# This function is not in artifact-kernel.sh's extension_hooks_to_hash, so its non-opts wiring
	# below (module-source copy, Kconfig/Makefile stitching) would not invalidate the cached kernel
	# on its own — the opts_* are auto-folded into kernel_config_modifying_hashes, but this logic is
	# not. Fold the function's own parsed source in; declare -f is comment/whitespace-insensitive, so
	# only real code changes here force a rebuild, not comment edits.
	kernel_config_modifying_hashes+=("ask_config_logic=$(declare -f custom_kernel_config__ask_modules | sha256sum | cut -d' ' -f1)")
	# declare -f covers this function's code but not the content of the board BSP files it copies
	# into the kernel tree; fold those in too — via calculate_hash_for_files, which hashes each
	# file's SRC-relative path and content (sorted, order-independent) — so editing e.g. sfp-led.c
	# or the board module Kconfig/Makefile rebuilds the kernel. (The ASK repo cdx/ sources come
	# from the ASK repo, already covered by the ASK pin above.)
	declare hash_files="undetermined"
	calculate_hash_for_files \
		"${SRC}"/packages/bsp/gateway-dk/ask-modules.Kconfig \
		"${SRC}"/packages/bsp/gateway-dk/ask-modules.Makefile \
		"${SRC}"/packages/bsp/gateway-dk/sfp-led.c \
		"${SRC}"/packages/bsp/gateway-dk/sfp-led.Kbuild \
		"${SRC}"/packages/bsp/gateway-dk/leds-lp5812.c \
		"${SRC}"/packages/bsp/gateway-dk/leds-lp5812.h \
		"${SRC}"/packages/bsp/gateway-dk/leds-lp5812.Kbuild
	kernel_config_modifying_hashes+=("ask_bsp_files=${hash_files}")

	# Skip file operations during config-dump-json and version calculation
	[[ ! -f .config ]] && return 0

	# The ASK data-plane is built IN-TREE: the consolidated cdx/ dir is copied into the kernel
	# tree and built with `make modules`, so the SDK source it #includes (sdk_fman, ncsw_config.mk,
	# crypto/caam) is present — an out-of-tree build against the trimmed linux-headers .deb cannot
	# see those. cdx/Kbuild emits both cdx.ko and ask_flowtable.ko from CONFIG_ASK_CDX=m; the
	# modules ship in the linux-image .deb. The board LED/SFP drivers build the same in-tree way.
	display_alert "ASK extension" "copying ASK module sources into kernel tree" "info"

	local ask_drv="${kernel_work_dir}/drivers/net/ethernet/freescale/ask"
	local bsp_dir="${SRC}/packages/bsp/gateway-dk"

	# Cleanup previous tree if it exists (otherwise copying again creates 1-deep duplicates)
	if [[ -d "${ask_drv}" ]]; then
		display_alert "ASK extension" "removing previous ASK module tree in kernel" "info"
		run_host_command_logged rm -rf "${ask_drv}"
	fi

	# Parent Kconfig + Makefile that wire the ASK modules into the in-tree build (from the BSP;
	# ASK's repo root carries no in-tree parent — its other integrations build out-of-tree).
	run_host_command_logged mkdir -pv "${ask_drv}"
	run_host_command_logged cp -v "${bsp_dir}/ask-modules.Kconfig" "${ask_drv}/Kconfig"
	run_host_command_logged cp -v "${bsp_dir}/ask-modules.Makefile" "${ask_drv}/Makefile"

	# ASK (since 1.1.0) consolidates the data plane into a single cdx/ dir whose Kbuild emits both
	# cdx.ko and ask_flowtable.ko (the old separate fci/ and auto_bridge/ dirs are gone).
	run_host_command_logged cp -av "${ASK_CACHE_DIR}/${ASK_CDX_DIR}" "${ask_drv}/cdx"

	# Board-specific LED modules (not part of ASK repo — from Armbian BSP). Their Kconfig
	# entries are baked into ask-modules.Kconfig; wire their obj dirs into the Makefile here.
	if [[ "${BOARD}" == "gateway-dk" ]]; then
		display_alert "ASK extension" "copying board LED module sources into kernel tree" "info"
		run_host_command_logged mkdir -pv "${ask_drv}/sfp_led" "${ask_drv}/leds_lp5812"
		run_host_command_logged cp -v "${bsp_dir}/sfp-led.c" "${ask_drv}/sfp_led/"
		run_host_command_logged cp -v "${bsp_dir}/sfp-led.Kbuild" "${ask_drv}/sfp_led/Kbuild"
		run_host_command_logged cp -v "${bsp_dir}/leds-lp5812.c" "${ask_drv}/leds_lp5812/"
		run_host_command_logged cp -v "${bsp_dir}/leds-lp5812.h" "${ask_drv}/leds_lp5812/"
		run_host_command_logged cp -v "${bsp_dir}/leds-lp5812.Kbuild" "${ask_drv}/leds_lp5812/Kbuild"
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
		display_alert "ASK extension" "adding ASK dir to freescale Makefile" "info"
		echo 'obj-y += ask/' >> "${fsl_dir}/Makefile"
	else
		display_alert "ASK extension" "ASK dir already present in freescale Makefile"
	fi

	display_alert "ASK extension" "ASK + board module sources placed in kernel tree" "info"

	# Wire the SDK's fsl_qbman staging driver (provided by the 005 overlay) into
	# drivers/staging the same append way Armbian's own out-of-tree drivers do — post-patch
	# and idempotent, so it is immune to ordering. ASK patch 110's staging/{Makefile,Kconfig}
	# hunks were stripped at stage time because Armbian's driver harness echo-appends to those
	# files (rtl8723cs, ...) before the ASK series and breaks the patch context.
	local staging_dir="${kernel_work_dir}/drivers/staging"
	# fsl_qbman is provided by the 005 SDK overlay; if it is missing the overlay did not apply,
	# and this wiring is the only registration path left after 110's staging hunks are stripped
	# — a silent skip would ship a kernel with no SDK QBMan driver. Fail loud instead.
	[[ -d "${staging_dir}/fsl_qbman" ]] ||
		exit_with_error "SDK staging driver missing; the 005 overlay did not apply" "${staging_dir}/fsl_qbman"
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

	# Force the full NXP SDK DPAA/FMan/QBMan stack explicitly on, and the competing mainline
	# drivers off. These live here, not in linux-ls1046a-current.config, on purpose: that config
	# is family-level and shared by any future non-ASK LS1046A board running plain mainline, and
	# the SDK/offload symbols only exist once this extension stages the SDK overlay. Relying on
	# Kconfig defaults is not safe either — FSL_DPAA_1588 defaults n, FSL_DPAA_ETH_MAX_BUF_COUNT
	# defaults 128 (we need 640), and FSL_SDK_DPA defaults n. ASK_CDX depends on FSL_SDK_FMAN,
	# which requires !FSL_FMAN; if a future mainline enabled FSL_FMAN by default, FSL_SDK_FMAN
	# would drop, olddefconfig would silently remove ASK_CDX, and a non-offloading kernel would
	# ship green. Mainline FSL_DPAA_ETH depends on FSL_FMAN, so disabling FSL_FMAN keeps it off too.
	opts_y+=("CONFIG_FSL_SDK_FMAN" "CONFIG_FSL_SDK_BMAN" "CONFIG_FSL_SDK_QMAN")
	opts_y+=("CONFIG_FSL_SDK_DPA" "CONFIG_FSL_SDK_DPAA_ETH" "CONFIG_FSL_DPAA_1588")
	opts_val["CONFIG_FSL_DPAA_ETH_MAX_BUF_COUNT"]="640"
	# Jumbo frames, as ASK's defconfig sets them: FMan accepts 9.6K frames
	# and DPAA sizes its Rx buffers to take one whole, so the offload paths that re-inject or
	# transform a frame (SEC, fragmenter, Wi-Fi) get it in one buffer. JUMBO_FRAME requires
	# MAX_FRAME_SIZE=9600 (sdk_dpaa/Kconfig); the default is 1522.
	opts_val["CONFIG_FSL_FM_MAX_FRAME_SIZE"]="9600"
	opts_y+=("CONFIG_FSL_DPAA_ETH_JUMBO_FRAME")
	opts_n+=("CONFIG_FSL_FMAN")

	# Enable the ASK modules in kernel config. CONFIG_ASK_CDX=m builds both cdx.ko and
	# ask_flowtable.ko (cdx/Kbuild: obj-$(CONFIG_ASK_CDX) += cdx.o ask_flowtable.o).
	opts_y+=("CONFIG_NXP_ASK")
	opts_m+=("CONFIG_ASK_CDX")
	# ask-flowtable keeps its flowtable in an `inet` (mixed IPv4/IPv6) nftables table; without
	# the inet flowtable type, `nft add flowtable inet ...` fails and nothing is offloaded.
	opts_m+=("CONFIG_NF_FLOW_TABLE_INET")
	if [[ "${BOARD}" == "gateway-dk" ]]; then
		opts_m+=("CONFIG_ASK_SFP_LED")
		opts_m+=("CONFIG_ASK_LEDS_LP5812")
	fi
}

# SDK driver source absent from mainline — copied from ASK's sdk/linux into its normal
# mainline locations. The path set is ASK's NXP_SDK_PATHS (meta-ask linux-ask.inc) minus the
# dtsi, which go to a private dir (below), so every ASK integration installs the exact same
# tree. ASK-added files outside these
# paths (e.g. include/linux/fsl_oh_port.h) arrive with the patch series, not here.
declare -ga ASK_SDK_PATHS=(
	"drivers/net/ethernet/freescale/sdk_dpaa"
	"drivers/net/ethernet/freescale/sdk_fman"
	"drivers/staging/fsl_qbman"
	"include/linux/fsl_bman.h"
	"include/linux/fsl_qman.h"
	"include/linux/fsl_usdpaa.h"
	"include/dt-bindings/soc/fsl,qoriq-rcpm.h"
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

# Synthesize the kernel-side overlay patches from the pinned ASK tree ($1 = dest dir):
#   005-nxp-sdk-overlay.patch            — NXP DPAA/FMan/QBMan SDK, ASK's copy (sdk/linux)
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

	# The SDK is ASK's own copy, laid out as a kernel tree; it comes with the ASK pin.
	declare sdk_src="${ASK_CACHE_DIR}/sdk/linux"
	declare sdk_ref="ASK sdk/linux @ ${ASK_BRANCH}"
	[[ -d "${sdk_src}/drivers/net/ethernet/freescale/sdk_dpaa" ]] || exit_with_error "ASK SDK copy not found" "${sdk_src}"
	declare dts_src="${ASK_CACHE_DIR}/dts/mono-gateway-dk.dts"
	[[ -f "${dts_src}" ]] || exit_with_error "ASK board DTS not found" "${dts_src}"
	display_alert "ASK extension" "NXP SDK overlay from ${sdk_ref}" "info"

	# Like ASK's own Yocto overlay (meta-ask do_overlay_sdk), refuse an SDK copy
	# holding a file this overlay would not install: it would be pinned yet in no kernel tree.
	declare f p listed
	while IFS= read -r f; do
		listed=0
		for p in "${ASK_SDK_PATHS[@]}"; do [[ "${f}" == "${p}" || "${f}" == "${p}/"* ]] && listed=1 && break; done
		for p in "${ASK_SDK_DTSI[@]}"; do [[ "${f}" == "${fsl_dts_dir}/${p}" ]] && listed=1 && break; done
		[[ "${listed}" == 1 ]] ||
			exit_with_error "ASK sdk/linux holds a file outside the SDK paths this overlay installs" "${f}"
	done < <(cd "${sdk_src}" && find . \( -type f -o -type l \) | sed 's|^\./||')

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
		[[ -e "${src}" ]] || exit_with_error "SDK path missing (ASK-added files come from the patch series)" "${pth} @ ${sdk_ref}"
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
		[[ -f "${src}" ]] || exit_with_error "SDK dtsi missing" "${dtsi} @ ${sdk_ref}"
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

	# Restore pristine mainline; patching.py resets again and re-applies 005/006 + the ASK series.
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
#   NNN-*.patch                          — ASK hook series for this kernel line (patches/kernel/<line>)
# userpatches/ is the Armbian-standard location for extension-provided patches; the build
# framework merges them with the committed patches in patch/kernel/ at build time. Runs
# immediately before patching, after hashing (staging here does not perturb the kernel hash).
function kernel_extra_create_patches__ask_kernel_patches() {
	[[ "${CONFIG_DEFS_ONLY}" == "yes" ]] && return 0 # cache not populated during config-dump-json
	declare patch_dst="${USERPATCHES_PATH}/kernel/${KERNELPATCHDIR}"
	declare manifest="${patch_dst}/.ask-staged"
	run_host_command_logged mkdir -pv "${patch_dst}"

	# Record exactly what we stage into this (user-owned) dir, so the pre-hash cleanup removes
	# only our files and never blanket-rm's a user's own patches.
	: > "${manifest}"

	# 1. NXP SDK overlay (005) + ASK board device tree (006); both sort before the ASK
	#    series (005 provides the SDK sources those patches edit).
	ask_synthesize_kernel_overlay_patches "${patch_dst}"
	printf '%s\n' "005-nxp-sdk-overlay.patch" "006-mono-gateway-dk-devicetree.patch" >> "${manifest}"

	# 2. ASK hook + fix series for this kernel line (patches/kernel/<major.minor>), straight
	#    from the pinned ASK tree; match every numeric-prefixed patch so nothing (e.g. 100+)
	#    is silently dropped. ASK lists the lines a release is qualified for in RELEASED_LINES;
	#    refuse a release that does not list ours. Each patch is filtered to drop drivers/staging/{Makefile,
	#    Kconfig} hunks — Armbian's driver harness echo-appends out-of-tree drivers
	#    (rtl8723cs, ...) to those files BEFORE the ASK series, breaking patch context for the
	#    SDK's fsl_qbman wiring; that wiring is re-added collision-proof post-patch in
	#    custom_kernel_config__ask_modules. Non-staging hunks are preserved verbatim.
	grep -qxF "${KERNEL_MAJOR_MINOR}" "${ASK_CACHE_DIR}/RELEASED_LINES" ||
		exit_with_error "ASK release is not qualified for this kernel line (RELEASED_LINES)" "${KERNEL_MAJOR_MINOR}"
	declare series_dir="${ASK_CACHE_DIR}/patches/kernel/${KERNEL_MAJOR_MINOR}"
	declare ask_patch b staged=0
	shopt -s nullglob
	for ask_patch in "${series_dir}"/[0-9]*.patch; do
		b="$(basename "${ask_patch}")"
		ask_strip_staging_wiring_hunks "${ask_patch}" "${patch_dst}/${b}"
		echo "${b}" >> "${manifest}"
		staged=$((staged + 1))
	done
	shopt -u nullglob
	[[ "${staged}" -gt 0 ]] || exit_with_error "No ASK kernel patches found" "${series_dir}/[0-9]*.patch"
	display_alert "ASK extension" "staged SDK overlay + ${staged} ASK kernel patches in userpatches" "info"
}

# Remove ONLY the patches this extension staged in a previous build (tracked in .ask-staged),
# then the manifest. userpatches/kernel/ is a user-owned drop location, so we must never
# blanket-rm *.patch there. Runs in post_family_config (pre-hashing) so stale staged patches
# never perturb the patch-dir hash; the current build re-stages + re-writes the manifest later.
function post_family_config__cleanup_ask_kernel_patch() {
	declare patch_dst="${USERPATCHES_PATH}/kernel/${KERNELPATCHDIR}"
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

# Print the installed linux-image package version in the image. A .deb Depends on linux-image
# must use this (Armbian's version string), not the module directory name ${kernel_ver} — the
# two are different namespaces, so a constraint against ${kernel_ver} always holds.
# chroot_sdcard_with_stdout execs its args directly (no shell): pass them separately, and
# single-quote the dpkg-query format so ${Version} reaches dpkg-query literally.
function ask_installed_kernel_deb_version() {
	local ver
	ver=$(chroot_sdcard_with_stdout dpkg-query -W -f='${Version}' "linux-image-${BRANCH}-${LINUXFAMILY}")
	[[ -n "${ver}" ]] || exit_with_error "Could not read the installed linux-image version" "linux-image-${BRANCH}-${LINUXFAMILY}"
	echo "${ver}"
}

# Build and install the ASK userspace.
#
# ASK is flowtable-native (since 1.1.0): the whole userspace is one libc-only daemon,
# ask-flowtable, built from the ASK repo's flowtable/ dir. It shells out to nft
# and ip at runtime (RDEPENDS nftables, iproute2) and reconciles the nftables
# flowtable that drives CDX hardware offload. The pre-1.1.0 stack (fmlib, fmc,
# libfci, libcli, dpa-app, cmm), the patched libnetfilter-conntrack/libnfnetlink,
# and the QOSMARK/QOSCONNMARK xtables extensions are all gone.
#
# The kernel modules (cdx, ask_flowtable) are built in-tree and ship in the
# linux-image .deb; this function owns only the userspace package.
function pre_customize_image__001_build_ask_userspace() {
	display_alert "ASK extension" "building ask-flowtable userspace" "info"

	local kernel_ver
	kernel_ver=$(ls -1v "${SDCARD}/lib/modules/" | tail -1)
	[[ -z "${kernel_ver}" ]] && exit_with_error "No kernel version found in ${SDCARD}/lib/modules/"

	# Build toolchain (native arm64 under qemu) + runtime deps. ask-flowtable itself links only
	# libc; nftables + iproute2 are the tools it shells out to at runtime.
	display_alert "ASK extension" "installing build + runtime dependencies" "info"
	chroot_sdcard_apt_get_install build-essential nftables iproute2

	# --- ask-flowtable (the entire userspace: one libc-only daemon) ---
	display_alert "ASK extension" "building ask-flowtable" "info"
	mkdir -p "${SDCARD}/tmp/ask-userspace"
	cp -a "${ASK_CACHE_DIR}/${ASK_FLOWTABLE_DIR}" "${SDCARD}/tmp/ask-userspace/flowtable"
	chroot_sdcard "cd /tmp/ask-userspace/flowtable && \
		make CC=gcc clean || true && \
		make CC=gcc all && \
		install -D -m 755 src/ask-flowtable /usr/sbin/ask-flowtable" ||
		exit_with_error "ask-flowtable build failed"

	# --- runtime config + units (staged into the rootfs, then snapshotted into the .deb) ---
	# Offload policy (the daemon falls back to identical built-in defaults if absent).
	install -D -m 644 "${ASK_CACHE_DIR}/config/offload.conf" "${SDCARD}/etc/ask/offload.conf"

	# Module autoload list. cdx + ask_flowtable are in-tree (linux-image); list them here so
	# systemd-modules-load brings the data plane up at boot, in order (ask_flowtable needs cdx).
	# mlan/moal are loaded by the gateway-dk-wifi package, not here.
	install -d "${SDCARD}/etc/modules-load.d"
	cat > "${SDCARD}/etc/modules-load.d/ask.conf" << 'ASKMOD'
# ASK fast-path kernel modules, loaded in order at boot.
# cdx brings up the DPAA/FMan offload hardware; ask_flowtable binds the
# nftables flowtable to it and must load after cdx.
cdx
ask_flowtable
# Connection tracking, which the Linux flowtable offloads from.
nf_conntrack
nf_conntrack_netlink
# iptables conntrack match - needed to activate connection tracking
xt_conntrack
ASKMOD

	# systemd service. ASK ships recovery units + an ask-flowtable.service.d/ drop-in but leaves
	# the base unit to the consumer (see the ASK repo's integration/README.md). This is the base
	# unit for the phase-1, no-auto-recovery integration: the daemon supervises its own worker,
	# and `service-start` double-forks it and waits on a readiness pipe (and no-ops cleanly if cdx
	# is not loaded) — so Type=forking, mirroring the upstream SysV S50ask-flowtable contract.
	install -d "${SDCARD}/etc/systemd/system"
	cat > "${SDCARD}/etc/systemd/system/ask-flowtable.service" << 'ASKSVC'
[Unit]
Description=ASK hardware flow-offload service
After=network-online.target systemd-modules-load.service
Wants=network-online.target

[Service]
Type=forking
ExecStart=/usr/sbin/ask-flowtable service-start
ExecStop=/usr/sbin/ask-flowtable service-stop
ExecReload=/usr/sbin/ask-flowtable service-restart

[Install]
WantedBy=multi-user.target
ASKSVC

	# Conntrack sysctl tuning for the offload path.
	install -D -m 644 "${SRC}/packages/bsp/gateway-dk/99-ls1046a-conntrack.conf" \
		"${SDCARD}/etc/sysctl.d/99-ls1046a-conntrack.conf"

	# Enable the service in the image (started at first boot; no-ops if cdx is absent).
	chroot_sdcard systemctl enable ask-flowtable.service

	# Cleanup build sources
	rm -rf "${SDCARD}/tmp/ask-userspace"

	# --- Package the userspace as a .deb (kernel modules ship in linux-image) ---
	display_alert "ASK extension" "packaging ASK userspace .deb" "info"
	local pkgname="gateway-dk-ask"
	local pkgdir
	pkgdir=$(mktemp -d)
	mkdir -p "${pkgdir}/DEBIAN"

	local -a ask_files=(
		usr/sbin/ask-flowtable
		etc/ask/offload.conf
		etc/modules-load.d/ask.conf
		etc/systemd/system/ask-flowtable.service
		etc/sysctl.d/99-ls1046a-conntrack.conf
	)
	local f
	for f in "${ask_files[@]}"; do
		[[ -e "${SDCARD}/${f}" ]] || exit_with_error "ASK userspace file missing" "${f}"
		mkdir -p "$(dirname "${pkgdir}/${f}")"
		cp -a "${SDCARD}/${f}" "${pkgdir}/${f}"
	done

	# Version: kernel version + build date — allows userspace bugfix rebuilds without a kernel
	# change. Depends uses >= on linux-image (not =): ask-flowtable shells out to nft/ip and does
	# not link the kernel modules, so a kernel point-release needs no ASK userspace rebuild. The
	# floor is the linux-image this was built with, which carries the flowtable-capable modules.
	local ask_version="${kernel_ver}+$(date +%Y%m%d)"
	local kernel_deb_ver
	kernel_deb_ver=$(ask_installed_kernel_deb_version)

	cat > "${pkgdir}/DEBIAN/control" << EOF
Package: ${pkgname}
Version: ${ask_version}
Architecture: arm64
Section: net
Priority: optional
Maintainer: ${MAINTAINER} <${MAINTAINERMAIL}>
Depends: linux-image-${BRANCH}-${LINUXFAMILY} (>= ${kernel_deb_ver}), nftables, iproute2
Description: NXP ASK hardware flow-offload userspace for Mono Gateway DK
 The ask-flowtable daemon maintains the nftables flowtable that drives NXP ASK
 CDX/FMan hardware offload on the LS1046A Gateway DK. The CDX and ask_flowtable
 kernel modules ship in the linux-image package.
EOF

	# Upgrading from the pre-flowtable package (ASK 1.0.0: cmm, fci, auto_bridge): disable cmm
	# while its unit file still exists — the upgrade removes the file, and an enablement link
	# left behind would dangle.
	cat > "${pkgdir}/DEBIAN/preinst" << 'EOF'
#!/bin/bash
if [ "$1" = upgrade ] && [ -e /etc/systemd/system/cmm.service ]; then
    systemctl disable --now cmm.service 2>/dev/null || true
fi
EOF
	chmod 755 "${pkgdir}/DEBIAN/preinst"

	# The pre-flowtable image also carried an unowned /etc/modules-load.d/ask-modules.conf naming
	# fci and auto_bridge, which no longer exist (systemd-modules-load would fail on every boot).
	# Drop those two entries; remove the file only when nothing but the stock list is left, which
	# /etc/modules-load.d/ask.conf now loads, so entries an administrator added survive.
	# prerm records a running service on upgrade; bring it back once the new daemon is in place.
	cat > "${pkgdir}/DEBIAN/postinst" << 'EOF'
#!/bin/bash
legacy=/etc/modules-load.d/ask-modules.conf
if grep -qsxE '(fci|auto_bridge)' "$legacy"; then
    sed -i -E '/^(fci|auto_bridge)$/d' "$legacy"
    if ! grep -vxE '[[:space:]]*(#.*)?|cdx|nf_conntrack|nf_conntrack_netlink|xt_conntrack' "$legacy" | grep -q .; then
        rm -f "$legacy"
    fi
fi
systemctl daemon-reload || true
if command -v systemctl >/dev/null 2>&1; then
    systemctl enable ask-flowtable.service 2>/dev/null || true
fi
if [ -e /run/gateway-dk-ask.restart ]; then
    rm -f /run/gateway-dk-ask.restart
    systemctl start ask-flowtable.service || true
fi
EOF
	chmod 755 "${pkgdir}/DEBIAN/postinst"

	cat > "${pkgdir}/DEBIAN/prerm" << 'EOF'
#!/bin/bash
if [ "$1" = upgrade ] && systemctl is-active --quiet ask-flowtable.service 2>/dev/null; then
    touch /run/gateway-dk-ask.restart
fi
systemctl stop ask-flowtable.service 2>/dev/null || true
EOF
	chmod 755 "${pkgdir}/DEBIAN/prerm"

	# An upgrade that fails after prerm can leave the restart marker behind; clear it on removal
	# so a later fresh install in the same boot only enables the service, as installs do.
	cat > "${pkgdir}/DEBIAN/postrm" << 'EOF'
#!/bin/bash
if [ "$1" = remove ] || [ "$1" = purge ]; then
    rm -f /run/gateway-dk-ask.restart
fi
systemctl daemon-reload || true
EOF
	chmod 755 "${pkgdir}/DEBIAN/postrm"

	cat > "${pkgdir}/DEBIAN/conffiles" << 'CONFFILES'
/etc/ask/offload.conf
/etc/modules-load.d/ask.conf
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

# Build the NXP 88W9098 (JODY-W3) WiFi driver (mlan/moal) as a standalone kernel-module .deb
# and ship the combo firmware — baked into every gateway image. Inert with no PCIe card
# present; the firmware also satisfies the DTS-declared UART Bluetooth node (btnxpuart), which
# otherwise spams -84/-110 with no firmware. The kernel config already carries CFG80211/
# MAC80211=m, so this needs no kernel change — the modules build against the linux-headers.
# Runs after __001 (which installed build-essential; the linux-headers are in the rootfs).
function pre_customize_image__002_build_wifi() {
	display_alert "gateway-dk WiFi" "building NXP mwifiex (mlan/moal) driver" "info"

	local kernel_ver kdir
	kernel_ver=$(ls -1v "${SDCARD}/lib/modules/" | tail -1)
	[[ -z "${kernel_ver}" ]] && exit_with_error "No kernel version found in ${SDCARD}/lib/modules/"
	kdir="/usr/src/linux-headers-${kernel_ver}"

	# Driver: small repo, fetch via Armbian's helper. Firmware: the NXP imx-firmware tree is
	# huge (all i.MX firmware), so pull ONLY the one image dir with a shallow sparse checkout
	# of FwImage_9098_PCIE. Re-fetch only when the pin moves.
	fetch_from_repo "${NXP_MWIFIEX_REPO}" "nxp-mwifiex" "commit:${NXP_MWIFIEX_COMMIT}"
	local fwcache="${SRC}/cache/sources/nxp-wifi-firmware"
	if [[ "$(cat "${fwcache}/.mono-fw-ref" 2> /dev/null)" != "${NXP_WIFI_FW_COMMIT}" ]]; then
		display_alert "gateway-dk WiFi" "sparse-fetching NXP 9098 firmware" "info"
		rm -rf "${fwcache}"
		mkdir -p "${fwcache}"
		run_host_command_logged git -C "${fwcache}" init -q
		run_host_command_logged git -C "${fwcache}" remote add origin "${NXP_WIFI_FW_REPO}"
		run_host_command_logged git -C "${fwcache}" sparse-checkout init --cone
		run_host_command_logged git -C "${fwcache}" sparse-checkout set FwImage_9098_PCIE
		run_host_command_logged git -C "${fwcache}" fetch -q --depth 1 origin "${NXP_WIFI_FW_COMMIT}"
		run_host_command_logged git -C "${fwcache}" checkout -q FETCH_HEAD
		echo "${NXP_WIFI_FW_COMMIT}" > "${fwcache}/.mono-fw-ref"
	fi
	mkdir -p "${SDCARD}/tmp/wifi"
	cp -a "${SRC}/cache/sources/nxp-mwifiex" "${SDCARD}/tmp/wifi/mwifiex"

	# ASK carries the driver's fixes for this kernel line (cfg80211 set_monitor_channel compat,
	# skb ownership, ralist locking, scan teardown, ...) next to its Yocto recipe; apply them
	# in order from the pinned ASK tree rather than keep a drifting copy here.
	local wifi_patch wifi_patches=0
	for wifi_patch in "${ASK_CACHE_DIR}/meta-ask/recipes-kernel/nxp-mwifiex/files/${KERNEL_MAJOR_MINOR}"/[0-9]*.patch; do
		[[ -f "${wifi_patch}" ]] || continue
		run_host_command_logged patch -p1 -d "${SDCARD}/tmp/wifi/mwifiex" < "${wifi_patch}"
		wifi_patches=$((wifi_patches + 1))
	done
	[[ "${wifi_patches}" -gt 0 ]] || exit_with_error "No mwifiex patches in the ASK tree for kernel line" "${KERNEL_MAJOR_MINOR}"

	# Build mlan.ko + moal.ko against the kernel headers. PCIe-9098 only (every other SDIO/USB/
	# PCIe variant off); cfg80211 fullmac, STA + uAP, no WEXT. Flags are passed as command-line
	# vars so they override the driver Makefile's own CPTCFG/CONFIG_CFG80211 autodetection.
	# Native arm64 build under qemu — slow.
	chroot_sdcard "cd /tmp/wifi/mwifiex && make -j\$(nproc) KERNELDIR=${kdir} ARCH=arm64 \
		CONFIG_PCIE9098=y CONFIG_SD8978=n CONFIG_SD8987=n CONFIG_SD9177=n CONFIG_SD9098=n \
		CONFIG_SDIW610=n CONFIG_USBIW610=n CONFIG_SDAW693=n CONFIG_PCIEAW693=n \
		CONFIG_PCIE9097=n CONFIG_PCIE8897=n \
		CONFIG_NXP_WLAN_DRIVER=m CONFIG_STA_SUPPORT=y CONFIG_UAP_SUPPORT=y \
		CONFIG_STA_CFG80211=y CONFIG_UAP_CFG80211=y CONFIG_STA_WEXT=n CONFIG_UAP_WEXT=n default" ||
		exit_with_error "mwifiex driver build failed"
	[[ -f "${SDCARD}/tmp/wifi/mwifiex/mlan.ko" && -f "${SDCARD}/tmp/wifi/mwifiex/moal.ko" ]] ||
		exit_with_error "mwifiex build produced no mlan.ko/moal.ko"

	# --- Package as gateway-dk-wifi .deb ---
	display_alert "gateway-dk WiFi" "packaging gateway-dk-wifi .deb" "info"
	local pkgname="gateway-dk-wifi"
	local pkgdir; pkgdir=$(mktemp -d)
	local moddir="lib/modules/${kernel_ver}/updates/nxp-mwifiex"
	mkdir -p "${pkgdir}/DEBIAN" "${pkgdir}/${moddir}" "${pkgdir}/lib/firmware/nxp" "${pkgdir}/etc/modules-load.d"

	# Modules shipped uncompressed — modprobe/depmod handle a mix of .ko and the kernel's .ko.zst.
	cp "${SDCARD}/tmp/wifi/mwifiex/mlan.ko" "${SDCARD}/tmp/wifi/mwifiex/moal.ko" "${pkgdir}/${moddir}/"

	# Firmware — the 88W9098 PCIe combo set (WiFi + BT). Verified on hardware: btnxpuart requests
	# nxp/uart9098_bt_v1.bin; moal requests pcie9098_wlan_v1.bin + the combo blob.
	local fwdir="${SRC}/cache/sources/nxp-wifi-firmware/FwImage_9098_PCIE"
	local fw
	for fw in pcieuart9098_combo_v1.bin pcie9098_wlan_v1.bin uart9098_bt_v1.bin ed_mac_ctrl_V3_909x.conf txpwrlimit_cfg_9098.conf; do
		[[ -f "${fwdir}/${fw}" ]] || exit_with_error "NXP WiFi firmware missing" "${fw} in ${fwdir}"
		cp "${fwdir}/${fw}" "${pkgdir}/lib/firmware/nxp/"
	done

	# Autoload moal (pulls in mlan via symbol dep). Harmless with no card; the PCIe device also
	# auto-probes via modalias once present.
	echo "moal" > "${pkgdir}/etc/modules-load.d/nxp-mwifiex.conf"

	# Prebuilt out-of-tree modules are vermagic-locked to the exact kernel build, so depend on
	# the EXACT installed linux-image version (query it — the .deb Version is Armbian's date
	# string, a different namespace from ${kernel_ver}). A kernel point-release then drags a
	# matching WiFi rebuild instead of leaving stale .ko that silently stop loading. Userspace
	# is Recommends (installed by default, removable on a headless unit). The package version
	# tracks the module dir + build date so a driver-only bugfix can ship without a kernel bump.
	local kernel_deb_ver
	kernel_deb_ver=$(ask_installed_kernel_deb_version)
	local wifi_version="${kernel_ver}+$(date +%Y%m%d)"
	cat > "${pkgdir}/DEBIAN/control" << EOF
Package: ${pkgname}
Version: ${wifi_version}
Architecture: arm64
Section: kernel
Priority: optional
Maintainer: ${MAINTAINER} <${MAINTAINERMAIL}>
Depends: linux-image-${BRANCH}-${LINUXFAMILY} (= ${kernel_deb_ver})
Recommends: hostapd, wpasupplicant, iw, wireless-regdb
Description: NXP 88W9098 (JODY-W3) WiFi+BT driver and firmware for Mono Gateway DK
 Out-of-tree mlan/moal cfg80211 fullmac WiFi driver for the optional PCIe
 88W9098 card, plus the 9098 combo firmware. Inert when no card is present;
 the firmware also satisfies the board's UART Bluetooth controller (btnxpuart).
EOF

	cat > "${pkgdir}/DEBIAN/postinst" << EOF
#!/bin/bash
depmod -a ${kernel_ver}
EOF
	chmod 755 "${pkgdir}/DEBIAN/postinst"

	cat > "${pkgdir}/DEBIAN/postrm" << EOF
#!/bin/bash
depmod -a ${kernel_ver} 2>/dev/null || true
EOF
	chmod 755 "${pkgdir}/DEBIAN/postrm"

	local debfile="${pkgname}_${wifi_version}_arm64.deb"
	mkdir -p "${SRC}/output/debs"
	run_host_command_logged dpkg-deb -b "${pkgdir}" "${SRC}/output/debs/${debfile}" ||
		exit_with_error "dpkg-deb failed for ${debfile}"
	rm -rf "${SDCARD}/tmp/wifi" "${pkgdir}"

	cp "${SRC}/output/debs/${debfile}" "${SDCARD}/root/"
	chroot_sdcard "DEBIAN_FRONTEND=noninteractive apt-get install -y /root/${debfile}" ||
		exit_with_error "gateway-dk-wifi install failed"
	rm -f "${SDCARD}/root/${debfile}"
}
