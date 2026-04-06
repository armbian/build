#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Mono Technologies Inc.
#
# NXP ASK (Application Solutions Kit) extension for LS1046A
# Builds and installs: kernel modules (CDX, FCI, auto-bridge),
# userspace tools (fmlib, fmc, libfci, libcli, dpa-app, cmm),
# patched system libraries, and configuration files.
#
# All ASK sources, patches, and configs come from the ASK repo.
#

# Source repos and refs (pinned to match Yocto)
# For local testing: set ASK_REPO="file:///path/to/ASK" — the Docker mount hook below handles it
declare -g ASK_REPO="https://github.com/we-are-mono/ASK.git"
declare -g ASK_BRANCH="branch:mt-6.12.y"
declare -g FMLIB_REPO="https://github.com/nxp-qoriq/fmlib.git"
declare -g FMLIB_COMMIT="7a58ecaf0d90d71d6b78d3ac7998282a472c4394"
declare -g FMC_REPO="https://github.com/nxp-qoriq/fmc.git"
declare -g FMC_COMMIT="5b9f4b16a864e9dfa58cdcc860be278a7f66ac18"
declare -g LIBCLI_REPO="https://github.com/dparrish/libcli.git"
declare -g LIBCLI_COMMIT="6a3b2f96c4f0916e2603a96bf24d704f6a904e7a"

# Target architecture triplet (Debian multiarch)
declare -g ASK_HOST_TRIPLET="aarch64-linux-gnu"

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

# Helper: ensure ASK repo is cloned and cached
function ask_ensure_cached() {
	local ask_cache="${SRC}/cache/sources/ask-repo/checkout"
	if [[ ! -d "${ask_cache}/.git" ]]; then
		display_alert "ASK extension" "cloning ASK repo" "info" >&2
		rm -rf "${ask_cache}"
		# For local file:// repos in Docker, safe.directory is needed (container runs as root)
		if [[ "${ASK_REPO}" == file://* ]]; then
			local local_path="${ASK_REPO#file://}"
			git config --global --add safe.directory "${local_path}" 2>/dev/null
			git config --global --add safe.directory "${local_path}/.git" 2>/dev/null
		fi
		git clone --depth 1 --branch "${ASK_BRANCH##*:}" "${ASK_REPO}" "${ask_cache}" >&2
	fi
	echo "${ask_cache}"
}

# Ensure kernel headers are available for module builds
function extension_finish_config__ask_enable_headers() {
	declare -g INSTALL_HEADERS="yes"
	display_alert "ASK extension" "enabling kernel headers for module builds" "info"
}

# Add host build dependencies
function add_host_dependencies__ask_deps() {
	display_alert "Adding ASK host dependencies" "${EXTENSION}" "debug"
	declare -g EXTRA_BUILD_DEPS="${EXTRA_BUILD_DEPS} libxml2-dev libtclap-dev libpcap-dev autoconf automake libtool pkg-config"
}

# Copy ASK kernel patch to userpatches (gitignored) so it's applied during kernel build
function post_family_config__ask_kernel_patch() {
	local ask_dir
	ask_dir=$(ask_ensure_cached)
	local patch_src="${ask_dir}/patches/kernel/002-mono-gateway-ask-kernel_linux_6_12.patch"
	[[ -f "${patch_src}" ]] || exit_with_error "ASK kernel patch not found" "${patch_src}"
	local patch_dst="${SRC}/userpatches/kernel/archive/ls1046a-${KERNEL_MAJOR_MINOR}"
	mkdir -p "${patch_dst}"
	cp "${patch_src}" "${patch_dst}/003-mono-gateway-ask-kernel_linux_6_12.patch"
	display_alert "ASK extension" "ASK kernel patch staged in userpatches" "info"
}

# Build kernel modules after kernel debs are installed in chroot
function post_install_kernel_debs__build_ask_modules() {
	[[ "${INSTALL_HEADERS}" != "yes" ]] && return 0

	display_alert "ASK extension" "building kernel modules (host cross-compile)" "info"

	local ask_dir
	ask_dir=$(ask_ensure_cached)

	local kernel_ver
	kernel_ver=$(ls -1v "${SDCARD}/lib/modules/" | tail -1)
	[[ -z "${kernel_ver}" ]] && exit_with_error "No kernel version found in ${SDCARD}/lib/modules/"

	# Full kernel source tree (needed for CDX — it includes ncsw_config.mk from the FMAN driver)
	local ksrc="${SRC}/cache/sources/linux-kernel-worktree/${KERNEL_MAJOR_MINOR}__${LINUXFAMILY}__${ARCH}"
	[[ -d "${ksrc}" ]] || exit_with_error "Kernel source tree not found at ${ksrc}"

	local cross="${KERNEL_COMPILER}"
	local bsp_dir="${SRC}/packages/bsp/gateway-dk"
	local builddir="/tmp/ask-build-$$"
	mkdir -p "${builddir}"
	trap "rm -rf '${builddir}'" EXIT

	# Copy ASK module sources to build dir
	cp -a "${ask_dir}/${ASK_CDX_DIR}" "${builddir}/cdx"
	cp -a "${ask_dir}/${ASK_FCI_DIR}" "${builddir}/fci"
	cp -a "${ask_dir}/${ASK_AUTOBRIDGE_DIR}" "${builddir}/auto-bridge"

	# Build CDX module (cross-compile on host against full kernel source)
	display_alert "ASK extension" "building CDX kernel module" "info"
	make -C "${builddir}/cdx" \
		KERNELDIR="${ksrc}" ARCH=arm64 CROSS_COMPILE="${cross}" PLATFORM=LS1043A \
		CFG_FLAGS="-DSEC_PROFILE_SUPPORT -DVLAN_FILTER -DWIFI_ENABLE -DENABLE_EGRESS_QOS" \
		|| exit_with_error "CDX module build failed"

	# Build FCI module (depends on CDX Module.symvers)
	display_alert "ASK extension" "building FCI kernel module" "info"
	make -C "${builddir}/fci" \
		KERNEL_SOURCE="${ksrc}" ARCH=arm64 CROSS_COMPILE="${cross}" BOARD_ARCH=arm64 \
		KBUILD_EXTRA_SYMBOLS="${builddir}/cdx/Module.symvers" \
		|| exit_with_error "FCI module build failed"

	# Build auto-bridge module (uses its own Makefile which adds -I for br_private.h)
	display_alert "ASK extension" "building auto-bridge kernel module" "info"
	make -C "${builddir}/auto-bridge" \
		KERNEL_SOURCE="${ksrc}" CROSS_COMPILE="${cross}" PLATFORM=LS1043A ENABLE_VLAN_FILTER=y \
		|| exit_with_error "auto-bridge module build failed"

	# Board-specific modules (gateway-dk only)
	if [[ "${BOARD}" == "gateway-dk" ]]; then
		# SFP-LED: GPIO-based SFP port LED control
		display_alert "ASK extension" "building SFP-LED kernel module" "info"
		mkdir -p "${builddir}/sfp-led"
		cp "${bsp_dir}/sfp-led.c" "${builddir}/sfp-led/"
		cp "${bsp_dir}/sfp-led.mk" "${builddir}/sfp-led/Makefile"
		make -C "${builddir}/sfp-led" KERNEL_SRC="${ksrc}" ARCH=arm64 CROSS_COMPILE="${cross}" \
			|| exit_with_error "SFP-LED module build failed"

		# LP5812: TI 4x3 LED matrix controller (not yet in mainline, targeting 6.19+)
		display_alert "ASK extension" "building LP5812 LED driver" "info"
		mkdir -p "${builddir}/lp5812"
		cp "${bsp_dir}/leds-lp5812.c" "${builddir}/lp5812/"
		cp "${bsp_dir}/leds-lp5812.h" "${builddir}/lp5812/"
		cp "${bsp_dir}/leds-lp5812.mk" "${builddir}/lp5812/Makefile"
		pushd "${builddir}/lp5812"
		make KERNEL_SRC="${ksrc}" ARCH=arm64 CROSS_COMPILE="${cross}" \
			|| exit_with_error "LP5812 module build failed"
		popd
	fi

	# Install modules into rootfs
	mkdir -p "${SDCARD}/lib/modules/${kernel_ver}/extra"
	cp "${builddir}/cdx/cdx.ko" "${SDCARD}/lib/modules/${kernel_ver}/extra/"
	cp "${builddir}/fci/fci.ko" "${SDCARD}/lib/modules/${kernel_ver}/extra/"
	cp "${builddir}/auto-bridge/auto_bridge.ko" "${SDCARD}/lib/modules/${kernel_ver}/extra/"
	[[ -f "${builddir}/sfp-led/sfp-led.ko" ]] && \
		cp "${builddir}/sfp-led/sfp-led.ko" "${SDCARD}/lib/modules/${kernel_ver}/extra/"
	[[ -f "${builddir}/lp5812/leds-lp5812.ko" ]] && \
		cp "${builddir}/lp5812/leds-lp5812.ko" "${SDCARD}/lib/modules/${kernel_ver}/extra/"

	# Update module dependencies
	chroot_sdcard "depmod -a ${kernel_ver}"

	# Install module load order config (from ASK repo)
	cp "${ask_dir}/config/ask-modules.conf" "${SDCARD}/etc/modules-load.d/"

	# Clean up build dir (also handled by EXIT trap on failure)
	rm -rf "${builddir}"
	trap - EXIT

	display_alert "ASK extension" "kernel modules built and installed" "info"
}

# Copy patches into chroot before patched library builds (runs before build_ask_userspace)
function pre_customize_image__000_prepare_ask_patches() {
	local ask_dir
	ask_dir=$(ask_ensure_cached)

	mkdir -p "${SDCARD}/tmp/ask-patches"
	local patch_dirs=("libnetfilter-conntrack" "libnfnetlink" "iptables")
	for pdir in "${patch_dirs[@]}"; do
		[[ -d "${ask_dir}/patches/${pdir}" ]] || exit_with_error "ASK patch directory missing" "${ask_dir}/patches/${pdir}"
		cp "${ask_dir}/patches/${pdir}/"*.patch "${SDCARD}/tmp/ask-patches/"
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

	local ask_dir
	ask_dir=$(ask_ensure_cached)
	local kernel_ver
	kernel_ver=$(ls -1v "${SDCARD}/lib/modules/" | tail -1)
	local kdir="/usr/src/linux-headers-${kernel_ver}"

	# Install build dependencies in chroot
	display_alert "ASK extension" "installing build dependencies" "info"
	chroot_sdcard_apt_get_install build-essential autoconf automake libtool \
		pkg-config libxml2-dev libpcap-dev libcrypt-dev libtclap-dev

	# Copy sources into chroot
	mkdir -p "${SDCARD}/tmp/ask-userspace"

	# --- fmlib ---
	display_alert "ASK extension" "building fmlib" "info"
	if [[ ! -d "${SRC}/cache/sources/fmlib" ]]; then
		run_host_command_logged git clone "${FMLIB_REPO}" "${SRC}/cache/sources/fmlib"
		pushd "${SRC}/cache/sources/fmlib" || exit_with_error "Cannot enter fmlib"
		run_host_command_logged git checkout "${FMLIB_COMMIT}"
		popd
	fi
	cp -a "${SRC}/cache/sources/fmlib" "${SDCARD}/tmp/ask-userspace/fmlib"
	cp "${ask_dir}/patches/fmlib/"*.patch "${SDCARD}/tmp/ask-userspace/"

	chroot_sdcard "cd /tmp/ask-userspace/fmlib && \
		patch -p1 < /tmp/ask-userspace/01-mono-ask-extensions.patch && \
		make KERNEL_SRC=${kdir} libfm-arm.a && \
		make DESTDIR=/ PREFIX=/usr LIB_DEST_DIR=/usr/lib/${ASK_HOST_TRIPLET} install-libfm-arm && \
		rm -rf /usr/src"

	# --- fmc ---
	display_alert "ASK extension" "building fmc" "info"
	if [[ ! -d "${SRC}/cache/sources/fmc" ]]; then
		run_host_command_logged git clone "${FMC_REPO}" "${SRC}/cache/sources/fmc"
		pushd "${SRC}/cache/sources/fmc" || exit_with_error "Cannot enter fmc"
		run_host_command_logged git checkout "${FMC_COMMIT}"
		popd
	fi
	cp -a "${SRC}/cache/sources/fmc" "${SDCARD}/tmp/ask-userspace/fmc"
	cp "${ask_dir}/patches/fmc/"*.patch "${SDCARD}/tmp/ask-userspace/"

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
		install -m 644 etc/fmc/config/* /etc/fmc/config/"

	# --- libcli ---
	display_alert "ASK extension" "building libcli" "info"
	if [[ ! -d "${SRC}/cache/sources/libcli" ]]; then
		run_host_command_logged git clone "${LIBCLI_REPO}" "${SRC}/cache/sources/libcli"
		pushd "${SRC}/cache/sources/libcli" || exit_with_error "Cannot enter libcli"
		run_host_command_logged git checkout "${LIBCLI_COMMIT}"
		popd
	fi
	cp -a "${SRC}/cache/sources/libcli" "${SDCARD}/tmp/ask-userspace/libcli"

	chroot_sdcard "cd /tmp/ask-userspace/libcli && \
		make CFLAGS='-Wno-calloc-transposed-args' && \
		make PREFIX=/usr DESTDIR=/ install"

	# --- libfci ---
	display_alert "ASK extension" "building libfci" "info"
	cp -a "${ask_dir}/${ASK_FCI_DIR}/lib" "${SDCARD}/tmp/ask-userspace/libfci"

	chroot_sdcard "cd /tmp/ask-userspace/libfci && \
		touch README && \
		autoreconf -fi && \
		./configure --prefix=/usr --host=${ASK_HOST_TRIPLET} && \
		make && make install && \
		install -m 644 include/libfci.h /usr/include/"

	# --- dpa-app ---
	display_alert "ASK extension" "building dpa-app" "info"
	cp -a "${ask_dir}/${ASK_DPA_APP_DIR}" "${SDCARD}/tmp/ask-userspace/dpa-app"
	# Copy CDX header
	mkdir -p "${SDCARD}/usr/include/cdx"
	cp "${ask_dir}/${ASK_CDX_DIR}/cdx_ioctl.h" "${SDCARD}/usr/include/cdx/"

	chroot_sdcard "cd /tmp/ask-userspace/dpa-app && \
		make CC=gcc \
			CFLAGS='-DENDIAN_LITTLE -DLS1043 -DNCSW_LINUX -DDPAA_DEBUG_ENABLE -DSEC_PROFILE_SUPPORT -DVLAN_FILTER \
				-I/usr/include/fmc -I/usr/include/fmd -I/usr/include/fmd/integrations \
				-I/usr/include/fmd/Peripherals -I/usr/include/fmd/Peripherals/common -I/usr/include/cdx' \
			LDFLAGS='-lfmc -lfm-arm -lstdc++ -lxml2 -lpthread -lcli' && \
		install -m 755 dpa_app /usr/bin/"

	# Install DPA-App config files (from ASK repo)
	cp "${ask_dir}/config/gateway-dk/cdx_cfg.xml" "${SDCARD}/etc/"
	cp "${ask_dir}/${ASK_DPA_APP_DIR}/files/etc/cdx_pcd.xml" "${SDCARD}/etc/"
	cp "${ask_dir}/${ASK_DPA_APP_DIR}/files/etc/cdx_sp.xml" "${SDCARD}/etc/" 2>/dev/null || true

	# --- Patched system libraries (must be before CMM which depends on patched libnetfilter-conntrack) ---
	build_ask_patched_libraries

	# --- cmm ---
	display_alert "ASK extension" "building cmm" "info"
	cp -a "${ask_dir}/${ASK_CMM_DIR}" "${SDCARD}/tmp/ask-userspace/cmm"
	# Copy auto-bridge header for CMM
	cp "${ask_dir}/${ASK_AUTOBRIDGE_DIR}/include/auto_bridge.h" "${SDCARD}/usr/include/"

	chroot_sdcard "cd /tmp/ask-userspace/cmm && \
		make distclean || true && \
		rm -f config.log config.status && \
		autoreconf -fi && \
		CFLAGS='-DLS1043 -DFLOW_STATS -DWIFI_ENABLE -DSEC_PROFILE_SUPPORT -DUSE_QOSCONNMARK \
			-DENABLE_INGRESS_QOS -DIPSEC_NO_FLOW_CACHE -DVLAN_FILTER -DAUTO_BRIDGE' \
		./configure --prefix=/usr --host=${ASK_HOST_TRIPLET} && \
		make && make install"

	# Install and enable CMM service (from ASK repo)
	# Guarded by ConditionPathExists=/dev/cdx_ctrl — won't start without ASK FMAN ucode on NOR
	cp "${ask_dir}/config/cmm.service" "${SDCARD}/etc/systemd/system/"
	mkdir -p "${SDCARD}/etc/config"
	cp "${ask_dir}/config/fastforward" "${SDCARD}/etc/config/"
	chroot_sdcard "systemctl enable cmm.service"

	# Pin patched packages to prevent apt upgrade from overwriting
	display_alert "ASK extension" "pinning patched packages" "info"
	chroot_sdcard "apt-mark hold libnetfilter-conntrack3 libnfnetlink0 iptables"

	# Install sysctl tuning for conntrack
	cat > "${SDCARD}/etc/sysctl.d/99-ls1046a-conntrack.conf" << 'EOF'
net.netfilter.nf_conntrack_acct=1
net.netfilter.nf_conntrack_checksum=0
net.netfilter.nf_conntrack_max=131072
net.netfilter.nf_conntrack_tcp_timeout_established=7440
net.netfilter.nf_conntrack_udp_timeout=60
net.netfilter.nf_conntrack_udp_timeout_stream=180
EOF

	# Cleanup
	rm -rf "${SDCARD}/tmp/ask-userspace" "${SDCARD}/tmp/ask-patches"

	display_alert "ASK extension" "all userspace components built and installed" "info"
}

# Build patched versions of system libraries
function build_ask_patched_libraries() {
	# Install all build dependencies upfront
	display_alert "ASK extension" "installing build deps for patched libraries" "info"
	chroot_sdcard "DEBIAN_FRONTEND=noninteractive apt-get -y build-dep \
		libnetfilter-conntrack libnfnetlink iptables"

	# Rebuild each patched library in an isolated directory
	rebuild_patched_deb "libnetfilter-conntrack" \
		"01-nxp-ask-comcerto-fp-extensions.patch" \
		"libnetfilter-conntrack3_*.deb libnetfilter-conntrack-dev_*.deb"

	rebuild_patched_deb "libnfnetlink" \
		"01-nxp-ask-nonblocking-heap-buffer.patch" \
		"libnfnetlink0_*.deb libnfnetlink-dev_*.deb"

	rebuild_patched_deb "iptables" \
		"001-qosmark-extensions.patch" \
		"libip4tc2_*.deb libip6tc2_*.deb libxtables12_*.deb iptables_*.deb"

}

# Helper: rebuild a Debian package with an ASK patch in an isolated chroot directory
# Usage: rebuild_patched_deb <pkg_name> <patch_file> <deb_globs>
function rebuild_patched_deb() {
	local pkg="$1" patch="$2" debs="$3"
	local workdir="/tmp/ask-rebuild-${pkg}"

	display_alert "ASK extension" "rebuilding ${pkg}" "info"
	chroot_sdcard "set -e && \
		rm -rf ${workdir} && mkdir -p ${workdir} && cd ${workdir} && \
		apt-get source ${pkg} && \
		cd \$(ls -d ${pkg}-*/ | head -1) && \
		patch -p1 < /tmp/ask-patches/${patch} && \
		DEB_BUILD_OPTIONS=nocheck dpkg-buildpackage -b -uc -us && \
		cd ${workdir} && dpkg -i ${debs} && \
		rm -rf ${workdir}"
}
