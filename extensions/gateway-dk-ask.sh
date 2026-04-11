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
declare -g ASK_BRANCH="commit:8ba7807b15834ae6c0d5a82dddc71dcc367c1f4e"
declare -g FMLIB_REPO="https://github.com/nxp-qoriq/fmlib.git"
declare -g FMLIB_COMMIT="7a58ecaf0d90d71d6b78d3ac7998282a472c4394"
declare -g FMC_REPO="https://github.com/nxp-qoriq/fmc.git"
declare -g FMC_COMMIT="5b9f4b16a864e9dfa58cdcc860be278a7f66ac18"
declare -g LIBCLI_REPO="https://github.com/dparrish/libcli.git"
declare -g LIBCLI_COMMIT="6a3b2f96c4f0916e2603a96bf24d704f6a904e7a"

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
	[[ "${CONFIG_DEFS_ONLY}" == "yes" ]] && { declare -g ASK_CACHE_DIR="${SRC}/cache/sources/ask-repo"; return 0; }
	# For local file:// repos in Docker, safe.directory is needed (container runs as root)
	# Use env vars instead of git config --global to avoid persistent side effects
	if [[ "${ASK_REPO}" == file://* ]]; then
		local local_path="${ASK_REPO#file://}"
		export GIT_CONFIG_COUNT=2
		export GIT_CONFIG_KEY_0="safe.directory" GIT_CONFIG_VALUE_0="${local_path}"
		export GIT_CONFIG_KEY_1="safe.directory" GIT_CONFIG_VALUE_1="${local_path}/.git"
	fi
	fetch_from_repo "${ASK_REPO}" "ask-repo" "${ASK_BRANCH}"
	unset GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0 GIT_CONFIG_KEY_1 GIT_CONFIG_VALUE_1 2>/dev/null
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

	# Copy module sources and Kbuild files from ASK cache
	# (Kbuild files coexist with old Makefiles — kbuild prefers Kbuild when both exist)
	mkdir -p "${ask_drv}"
	cp -a "${ASK_CACHE_DIR}/${ASK_CDX_DIR}" "${ask_drv}/cdx"
	cp -a "${ASK_CACHE_DIR}/${ASK_FCI_DIR}" "${ask_drv}/fci"
	cp -a "${ASK_CACHE_DIR}/${ASK_AUTOBRIDGE_DIR}" "${ask_drv}/auto_bridge"

	# Parent Kconfig and Makefile from ASK repo
	cp "${ASK_CACHE_DIR}/Kconfig" "${ask_drv}/Kconfig"
	cp "${ASK_CACHE_DIR}/Kbuild.mk" "${ask_drv}/Makefile"

	# Board-specific modules (not part of ASK repo — from Armbian BSP)
	if [[ "${BOARD}" == "gateway-dk" ]]; then
		mkdir -p "${ask_drv}/sfp_led" "${ask_drv}/leds_lp5812"
		cp "${bsp_dir}/sfp-led.c" "${ask_drv}/sfp_led/"
		cp "${bsp_dir}/sfp-led.Kbuild" "${ask_drv}/sfp_led/Kbuild"
		cp "${bsp_dir}/leds-lp5812.c" "${ask_drv}/leds_lp5812/"
		cp "${bsp_dir}/leds-lp5812.h" "${ask_drv}/leds_lp5812/"
		cp "${bsp_dir}/leds-lp5812.Kbuild" "${ask_drv}/leds_lp5812/Kbuild"

		# Add board-specific entries to ASK Kconfig and Makefile
		patch -p1 -d "${ask_drv}" < "${bsp_dir}/ask-kconfig-board-modules.patch"
		echo 'obj-$(CONFIG_ASK_SFP_LED)	+= sfp_led/' >> "${ask_drv}/Makefile"
		echo 'obj-$(CONFIG_ASK_LEDS_LP5812)	+= leds_lp5812/' >> "${ask_drv}/Makefile"
	fi

	# Wire into parent freescale Kconfig and Makefile
	local fsl_dir="${kernel_work_dir}/drivers/net/ethernet/freescale"
	if ! grep -q 'source.*ask/Kconfig' "${fsl_dir}/Kconfig" 2>/dev/null; then
		sed -i '/endif.*NET_VENDOR_FREESCALE/i source "drivers/net/ethernet/freescale/ask/Kconfig"' "${fsl_dir}/Kconfig"
	fi
	if ! grep -q 'ask/' "${fsl_dir}/Makefile" 2>/dev/null; then
		echo 'obj-y += ask/' >> "${fsl_dir}/Makefile"
	fi

	display_alert "ASK extension" "ASK module sources and Kbuild files placed in kernel tree" "info"

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

# Copy ASK kernel patch to userpatches (gitignored) so it's applied during kernel build.
# userpatches/ is the Armbian-standard location for extension-provided patches — the build
# framework merges them with patches from patch/kernel/ at build time. The directory is
# gitignored and ephemeral; it does not persist across clean builds.
function post_family_config__ask_kernel_patch() {
	[[ "${CONFIG_DEFS_ONLY}" == "yes" ]] && return 0 # cache wasn't populated during config-dump-json
	local patch_src="${ASK_CACHE_DIR}/patches/kernel/002-mono-gateway-ask-kernel_linux_6_12.patch"
	[[ -f "${patch_src}" ]] || exit_with_error "ASK kernel patch not found" "${patch_src}"
	local patch_dst="${SRC}/userpatches/kernel/${KERNELPATCHDIR}"
	mkdir -p "${patch_dst}"
	# Renamed to 003- to apply after 001-ina234 and 002-device-tree in the Armbian patch dir
	cp "${patch_src}" "${patch_dst}/003-mono-gateway-ask-kernel_linux_6_12.patch"
	display_alert "ASK extension" "ASK kernel patch staged in userpatches" "info"
}


# Install module autoload config (modules are in the kernel .deb, just need the load list)
function post_install_kernel_debs__ask_module_autoload() {
	cp "${ASK_CACHE_DIR}/config/ask-modules.conf" "${SDCARD}/etc/modules-load.d/"
}

# Copy patches into chroot before patched library builds (runs before build_ask_userspace)
function pre_customize_image__000_prepare_ask_patches() {
	mkdir -p "${SDCARD}/tmp/ask-patches"
	local patch_dirs=("libnetfilter-conntrack" "libnfnetlink")
	for pdir in "${patch_dirs[@]}"; do
		[[ -d "${ASK_CACHE_DIR}/patches/${pdir}" ]] || exit_with_error "ASK patch directory missing" "${ASK_CACHE_DIR}/patches/${pdir}"
		cp "${ASK_CACHE_DIR}/patches/${pdir}/"*.patch "${SDCARD}/tmp/ask-patches/"
	done

	# Enable deb-src for apt-get source
	chroot_sdcard "if [ -f /etc/apt/sources.list.d/debian.sources ]; then \
		sed -i 's/^Types: deb\$/Types: deb deb-src/' /etc/apt/sources.list.d/debian.sources; \
	elif [ -f /etc/apt/sources.list ]; then \
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
		make DESTDIR=/ PREFIX=/usr LIB_DEST_DIR=/usr/lib/${ASK_HOST_TRIPLET} install-libfm-arm" \
		|| exit_with_error "fmlib build failed"

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
		install -m 644 etc/fmc/config/* /etc/fmc/config/" \
		|| exit_with_error "fmc build failed"

	# --- libcli ---
	display_alert "ASK extension" "building libcli" "info"
	fetch_from_repo "${LIBCLI_REPO}" "libcli" "commit:${LIBCLI_COMMIT}"
	cp -a "${SRC}/cache/sources/libcli" "${SDCARD}/tmp/ask-userspace/libcli"

	chroot_sdcard "cd /tmp/ask-userspace/libcli && \
		make CFLAGS='-Wno-calloc-transposed-args' && \
		make PREFIX=/usr DESTDIR=/ install" \
		|| exit_with_error "libcli build failed"

	# --- libfci ---
	display_alert "ASK extension" "building libfci" "info"
	cp -a "${ASK_CACHE_DIR}/${ASK_FCI_DIR}/lib" "${SDCARD}/tmp/ask-userspace/libfci"

	chroot_sdcard "cd /tmp/ask-userspace/libfci && \
		make && \
		install -m 644 libfci.a /usr/lib/${ASK_HOST_TRIPLET}/ && \
		install -m 644 include/libfci.h /usr/include/" \
		|| exit_with_error "libfci build failed"

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
		install -m 755 dpa_app /usr/bin/" \
		|| exit_with_error "dpa-app build failed"

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
				-D_init=\${name}_init \
				-I./include \
				-o \"\${name}.so\" \"\${name}.c\" || exit 1; \
		done && \
		install -d /usr/lib/${ASK_HOST_TRIPLET}/xtables && \
		for name in ${ask_xtables_modules[*]}; do \
			install -m 644 \"\${name}.so\" /usr/lib/${ASK_HOST_TRIPLET}/xtables/ || exit 1; \
		done" \
		|| exit_with_error "xtables extensions build failed"

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
		install -m 755 src/cmm /usr/bin/" \
		|| exit_with_error "cmm build failed"

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
		[[ -f "${SDCARD}/usr/lib/${ASK_HOST_TRIPLET}/${lib}" ]] && \
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
Maintainer: Mono Technologies <support@mono.si>
Depends: linux-image-${BRANCH}-${LINUXFAMILY} (>= ${kernel_ver}), libxml2, libpcap0.8, iptables
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
/etc/sysctl.d/99-ls1046a-conntrack.conf
CONFFILES

	# Build .deb once, install in chroot and save to output
	local debfile="${pkgname}_${ask_version}_arm64.deb"
	mkdir -p "${SRC}/output/debs"
	run_host_command_logged dpkg-deb -b "${pkgdir}" "${SRC}/output/debs/${debfile}" \
		|| exit_with_error "dpkg-deb failed for ${debfile}"
	cp "${SRC}/output/debs/${debfile}" "${SDCARD}/root/"
	chroot_sdcard "dpkg -i /root/${debfile}" || exit_with_error "dpkg -i failed for ${debfile}"
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
	cp "${SDCARD}"/tmp/ask-patched-debs/*.deb "${SRC}/output/debs/" 2>/dev/null || true
	rm -rf "${SDCARD}/tmp/ask-patched-debs"
}

# Helper: rebuild a Debian package with an ASK patch in an isolated chroot directory
# Usage: rebuild_patched_deb <pkg_name> <patch_file> <deb_globs>
function rebuild_patched_deb() {
	local pkg="$1" patch="$2" debs="$3"
	local workdir="/tmp/ask-rebuild-${pkg}"

	display_alert "ASK extension" "rebuilding ${pkg}" "info"
	# Note: ${debs} is intentionally unquoted — it contains globs that must expand in the chroot
	chroot_sdcard "set -e && \
		rm -rf '${workdir}' && mkdir -p '${workdir}' && cd '${workdir}' && \
		apt-get source '${pkg}' && \
		cd \$(ls -d ${pkg}-*/ | head -1) && \
		patch -p1 < '/tmp/ask-patches/${patch}' && \
		DEB_BUILD_OPTIONS=nocheck dpkg-buildpackage -b -uc -us && \
		cd '${workdir}' && dpkg -i ${debs} && \
		cp ${debs} /tmp/ask-patched-debs/ && \
		rm -rf '${workdir}'" \
		|| exit_with_error "${pkg} rebuild failed"
}
