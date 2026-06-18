#!/bin/bash
#
# enable-powervr-gpu.sh — opt-in PowerVR (BXM) GPU acceleration for Armbian
# sun60iw2 (Allwinner A733: Orange Pi 4 Pro, Radxa Cubie A7Z, ...).
#
# Run as root ON A BOOTED sun60iw2 board. It:
#   1. builds the GPU kernel module (pvrsrvkm.ko) FROM SOURCE via DKMS, and
#   2. installs Imagination's proprietary PowerVR userspace (a DDK-version-MATCHED
#      set) from Radxa's Debian packages — NOT carved out of a disk image.
#
# The userspace blobs are non-redistributable, so they are NOT shipped in the
# Armbian image; this script fetches them on demand. GPU acceleration is optional
# (headless servers don't need it), hence opt-in.
#
# STATUS: FIRST DRAFT — not yet verified end-to-end on hardware. The approach is
# derived from the proven transplant in Incipiens/OrangePiZero3W-GPU-VPU (which
# does the same DKMS build + userspace graft against a 6.6.x-sun60iw2 kernel) and
# from dok2d's Cubie A7Z work. Repo/package details below are confirmed against
# Radxa's published a733-bullseye repo (June 2026). The main remaining unknown is
# the suite mismatch: these packages target Debian 11 (bullseye) and we install
# them on Trixie — see README.md ("Suite mismatch").
#
# SPDX-License-Identifier: GPL-2.0
#

set -euo pipefail

# ----------------------------------------------------------------------------
# Configuration
# ----------------------------------------------------------------------------
# The PowerVR DDK is Imagination proprietary; Radxa redistributes it as .debs
# built by rsdk (https://github.com/RadxaOS-SDK/rsdk) and published to the
# a733-bullseye apt repo. We pull from there rather than carving a disk image.
RADXA_APT_LIST="/etc/apt/sources.list.d/radxa-a733-gpu.list"
RADXA_APT_URL="https://radxa-repo.github.io/a733-bullseye"
RADXA_APT_SUITE="a733-bullseye"
RADXA_APT_COMPONENTS="main"
RADXA_APT_KEYRING="/usr/share/keyrings/radxa-archive-keyring.gpg"
# The keyring is distributed as a .deb that installs ${RADXA_APT_KEYRING}.
RADXA_KEYRING_RELEASE="https://github.com/radxa-pkg/radxa-archive-keyring/releases/latest/download"

# Package names as they appear in the index. NOTE: the userspace/VPU packages
# have MALFORMED names — the version and ".deb" are baked into the Package: field.
# apt still installs them by that exact literal name (it only treats a name as a
# local file when a matching file exists in the cwd). They form a matched DDK pair
# with the module, all from the same a733-bullseye suite.
PKG_GPU_DKMS="img-bxm-dkms"                            # 0.1.0-3: builds pvrsrvkm.ko from source
PKG_GPU_USERSPACE="xserver-xorg-img-bxm-1.21.1-2.deb"  # PowerVR DDK userspace (GLES/EGL/Vulkan/fw)
PKG_VPU=("libcedarc-dev-2.0.0-arm64" "libgstreamer-openmax-allwinner")  # optional VPU

# ----------------------------------------------------------------------------
WITH_VPU="no"
DEB_DIR=""

usage() {
	cat <<EOF
Usage: $(basename "$0") [options]

  --debs DIR   Install the GPU/VPU .deb files found in DIR instead of adding
               Radxa's apt repo. Use this if you have pulled the packages
               manually (e.g. from Radxa's pool) — avoids the repo-URL VERIFY.
  --with-vpu   Also install the Allwinner Cedar VPU userspace (libcedarc +
               gstreamer-omx) and wire up the cedar device nodes.
  -h, --help   Show this help.

Default (no --debs): add Radxa's apt repo and apt-install the packages.
EOF
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--with-vpu) WITH_VPU="yes"; shift ;;
		--debs) DEB_DIR="${2:?--debs needs a directory}"; shift 2 ;;
		-h|--help) usage; exit 0 ;;
		*) echo "Unknown option: $1" >&2; usage; exit 1 ;;
	esac
done

log() { echo ">> $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run as root."

KVER="$(uname -r)"
case "${KVER}" in
	*sun60iw2*) ;;
	*) die "This is for sun60iw2 (A733) kernels; running kernel is '${KVER}'." ;;
esac
log "Target kernel: ${KVER}"

# ----------------------------------------------------------------------------
# 1. Build prerequisites
# ----------------------------------------------------------------------------
log "Installing build prerequisites (dkms, kernel headers, curl)"
apt-get update
apt-get install -y --no-install-recommends dkms curl ca-certificates || die "could not install build prerequisites"

# The DKMS build needs this kernel's headers. Armbian ships them as
# linux-headers-<branch>; INSTALL_HEADERS=yes in the family puts them on disk.
if [[ ! -d "/usr/src/linux-headers-${KVER}" && ! -d "/lib/modules/${KVER}/build" ]]; then
	apt-get install -y "linux-headers-${KVER}" 2>/dev/null \
		|| die "kernel headers for ${KVER} not found; install the matching linux-headers package first"
fi

# The GPU DKMS build does '#include <sunxi-sid.h>' (angle brackets), which the
# kernel Makefile resolves via '-I$(srctree)/bsp/include' in LINUXINCLUDE. Our
# family's pre_package_kernel_headers hook ships bsp/include in the linux-headers
# package, so the header is already on the -I path here — nothing to stage.
if ! find "/usr/src/linux-headers-${KVER}" -name sunxi-sid.h 2>/dev/null | grep -q .; then
	die "sunxi-sid.h not found under the linux-headers tree; the headers package is missing bsp/include (rebuild the image with the pre_package_kernel_headers hook)"
fi

# ----------------------------------------------------------------------------
# 2. Install the GPU packages (kernel module source + userspace)
# ----------------------------------------------------------------------------
PKGS=("${PKG_GPU_DKMS}" "${PKG_GPU_USERSPACE}")
[[ "${WITH_VPU}" == "yes" ]] && PKGS+=("${PKG_VPU[@]}")

if [[ -n "${DEB_DIR}" ]]; then
	log "Installing packages from local directory: ${DEB_DIR}"
	[[ -d "${DEB_DIR}" ]] || die "--debs directory not found: ${DEB_DIR}"
	shopt -s nullglob
	debs=("${DEB_DIR}"/*.deb)
	shopt -u nullglob
	[[ ${#debs[@]} -gt 0 ]] || die "no .deb files in ${DEB_DIR}"
	apt-get install -y "${debs[@]}"   # apt resolves deps; paths force file mode
else
	log "Installing Radxa archive keyring"
	if [[ ! -f "${RADXA_APT_KEYRING}" ]]; then
		tmpd="$(mktemp -d)"
		ver="$(curl -fsSL "${RADXA_KEYRING_RELEASE}/VERSION")" \
			|| die "could not query radxa-archive-keyring version"
		curl -fsSL -o "${tmpd}/keyring.deb" \
			"${RADXA_KEYRING_RELEASE}/radxa-archive-keyring_${ver}_all.deb" \
			|| die "could not download radxa-archive-keyring"
		dpkg -i "${tmpd}/keyring.deb" || die "radxa-archive-keyring install failed"
		rm -rf "${tmpd}"
	fi
	log "Adding Radxa a733-bullseye package repo"
	echo "deb [signed-by=${RADXA_APT_KEYRING}] ${RADXA_APT_URL}/ ${RADXA_APT_SUITE} ${RADXA_APT_COMPONENTS}" \
		> "${RADXA_APT_LIST}"
	apt-get update

	# apt installs all of these by name (even the malformed ones). This is also
	# where a bullseye-on-Trixie dependency clash would surface, though in testing
	# the userspace pulled no heavy deps — see README ("Suite mismatch").
	log "Installing: ${PKGS[*]}"
	apt-get install -y "${PKGS[@]}" || die "package install failed — see README (names / suite mismatch)"
fi

# ----------------------------------------------------------------------------
# 3. Ensure the kernel module built (DKMS compiles pvrsrvkm.ko from source)
# ----------------------------------------------------------------------------
log "Checking DKMS build of the GPU module"
dkms status 2>/dev/null | grep -i img-bxm || true
if ! find "/lib/modules/${KVER}" -name 'pvrsrvkm.ko*' 2>/dev/null | grep -q .; then
	log "pvrsrvkm.ko not present yet; running dkms autoinstall for ${KVER}"
	dkms autoinstall -k "${KVER}" || true
fi
find "/lib/modules/${KVER}" -name 'pvrsrvkm.ko*' 2>/dev/null | grep -q . \
	|| die "pvrsrvkm.ko was not built for ${KVER}; inspect /var/lib/dkms/*/make.log"
depmod "${KVER}"

# ----------------------------------------------------------------------------
# 4. Runtime wiring
# ----------------------------------------------------------------------------
log "Autoloading pvrsrvkm at boot"
echo "pvrsrvkm" > /etc/modules-load.d/pvr.conf

# The userspace package ships the Vulkan ICD, DRI driver, rgx firmware and an
# ld.so.conf.d entry. Refresh the linker cache so libsrv_um & friends resolve.
ldconfig
ldconfig -p | grep -E "libsrv_um|libGLESv2_PVR|libEGL_PVR" | head || \
	log "WARNING: PowerVR userspace libs not visible to ldconfig — check the userspace package."

# The desktop-built userspace links X/Wayland client libraries; without them the
# Vulkan/GLES drivers fail to even load (e.g. "libX11-xcb.so.1: cannot open ...").
# Install the runtime deps so the drivers load. NOTE: Vulkan/GLES still need a
# display/compositor to actually run — on a headless box OpenCL is the usable path.
log "Installing PowerVR userspace runtime deps (X/Wayland client libs)"
apt-get install -y --no-install-recommends \
	libx11-xcb1 libxcb-dri3-0 libxcb-present0 libxcb-sync1 libxshmfence1 libwayland-client0 || \
	log "WARNING: could not install some X/Wayland client libs; Vulkan/GLES may not load."

# Standardise on Debian's ocl-icd loader, then hide Radxa's bundled libOpenCL.
# The userspace package ships its own /usr/lib/libOpenCL.so{,.1} loader, which
# competes with ocl-icd (two libOpenCL.so.1 on the system). Install ocl-icd FIRST
# (else diverting would leave no libOpenCL at all), then dpkg-divert Radxa's aside
# — upgrade-safe and reversible, unlike rm'ing a file owned by another package.
log "Standardising on the ocl-icd OpenCL loader"
apt-get install -y --no-install-recommends ocl-icd-libopencl1 || \
	log "WARNING: could not install ocl-icd-libopencl1; leaving Radxa's bundled loader in place."
if dpkg -s ocl-icd-libopencl1 > /dev/null 2>&1; then
	for f in /usr/lib/libOpenCL.so /usr/lib/libOpenCL.so.1; do
		if [[ -e "${f}" ]] && ! dpkg-divert --list "${f}" | grep -q .; then
			dpkg-divert --add --rename --divert "${f}.radxa-disabled" "${f}"
		fi
	done
	ldconfig
fi

# Register the PowerVR OpenCL ICD. The package ships libPVROCL but not the vendor
# registration file the OpenCL loader needs, so clinfo finds 0 platforms without
# it. This is the headless-friendly compute path (no display required).
ocl_lib="$(ldconfig -p | awk '/libPVROCL\.so\.1/{print $NF; exit}')"
if [[ -n "${ocl_lib}" ]]; then
	log "Registering PowerVR OpenCL ICD (${ocl_lib})"
	install -d /etc/OpenCL/vendors
	echo "${ocl_lib}" > /etc/OpenCL/vendors/imgtec.icd
else
	log "WARNING: libPVROCL.so.1 not found; skipping OpenCL ICD registration."
fi

if [[ "${WITH_VPU}" == "yes" ]]; then
	log "Wiring up Cedar VPU device nodes"
	cat > /etc/udev/rules.d/99-cedar-ve.rules <<'EOF'
KERNEL=="cedar_dev*", MODE="0666"
SUBSYSTEM=="cedar_ve",  TAG+="uaccess", MODE="0666"
SUBSYSTEM=="cedar_ve2", TAG+="uaccess", MODE="0666"
EOF
	# gst-omx needs extra workaround flags on this SoC or decode/encode stalls in
	# the OMX Loaded->Idle transition (see Incipiens build.sh for the analysis).
	GSTOMX="/etc/xdg/gstomx.conf"
	if [[ -f "${GSTOMX}" ]]; then
		HACKS="event-port-settings-changed-ndata-parameter-swap;event-port-settings-changed-port-0-to-1;no-disable-outport;no-component-reconfigure;no-component-role;no-empty-eos-buffer;pass-color-format-to-decoder;pass-profile-to-decoder;signals-premature-eos;height-multiple-16"
		sed -i "s|^hacks=.*|hacks=${HACKS}|" "${GSTOMX}"
	fi
fi

log "Done. Reboot (or 'modprobe pvrsrvkm') to load the GPU module."
log "Validate (headless): 'apt-get install clinfo && clinfo' should list the"
log "  'PowerVR B-Series' GPU with Driver Version matching the kernel's pvr build."
log "  Vulkan/GLES (vulkaninfo, glmark2) additionally need a display/compositor, so"
log "  they are expected to fail on a bare headless server."
