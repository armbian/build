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
# from dok2d's Cubie A7Z work. Lines marked "VERIFY:" need confirmation against
# Radxa's published packages before this can be relied on. See README.md.
#
# SPDX-License-Identifier: GPL-2.0
#

set -euo pipefail

# ----------------------------------------------------------------------------
# Configuration (VERIFY against Radxa's package repo)
# ----------------------------------------------------------------------------
# The PowerVR DDK is Imagination proprietary; Radxa redistributes it as .debs
# built by rsdk (https://github.com/RadxaOS-SDK/rsdk). Pull from the package
# repo rather than extracting from a Radxa disk image.
#
# VERIFY: exact apt repo URL / suite / signing key. Radxa's package repo layout
# has changed across releases; confirm before trusting these defaults.
RADXA_APT_LIST="/etc/apt/sources.list.d/radxa-a733-gpu.list"
RADXA_APT_URL="https://radxa-repo.github.io/bookworm"   # VERIFY
RADXA_APT_SUITE="bookworm"                              # VERIFY
RADXA_APT_COMPONENTS="main"                             # VERIFY
RADXA_APT_KEYRING="/usr/share/keyrings/radxa-archive-keyring.gpg"
RADXA_APT_KEY_URL="https://radxa-repo.github.io/radxa-archive-keyring.gpg"  # VERIFY

# Package names (VERIFY exact names + that the versions match each other; the
# kernel module DDK version and the userspace DDK version MUST be the same).
PKG_GPU_DKMS="img-bxm-dkms"            # DKMS source -> builds pvrsrvkm.ko from source
PKG_GPU_USERSPACE="xserver-xorg-img-bxm"  # GLES/EGL/Vulkan ICD/DRI/rgx firmware
PKG_VPU=("libcedarc" "libcedarc-dev" "gstreamer1.0-omx-allwinner")  # optional, VERIFY

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
log "Installing build prerequisites (dkms, kernel headers)"
apt-get update
apt-get install -y --no-install-recommends dkms || die "could not install dkms"

# The DKMS build needs this kernel's headers. Armbian ships them as
# linux-headers-<branch>; INSTALL_HEADERS=yes in the family puts them on disk.
if [[ ! -d "/usr/src/linux-headers-${KVER}" && ! -d "/lib/modules/${KVER}/build" ]]; then
	apt-get install -y "linux-headers-${KVER}" 2>/dev/null \
		|| die "kernel headers for ${KVER} not found; install the matching linux-headers package first"
fi

# img-bxm-dkms references the BSP header sunxi-sid.h. Orange Pi's 6.6 source tree
# carries it under bsp/include, so the Armbian headers package SHOULD already
# provide it. VERIFY; if the DKMS build later fails on a missing sunxi-sid.h,
# copy it from the kernel source into:
#   /usr/src/linux-headers-${KVER}/bsp/include/sunxi-sid.h
if ! find "/usr/src/linux-headers-${KVER}" -name sunxi-sid.h 2>/dev/null | grep -q .; then
	log "WARNING: sunxi-sid.h not found in the headers package."
	log "         If the DKMS build fails, stage it under bsp/include (see README)."
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
	# dpkg first, then apt to settle any dependencies pulled from the base repos.
	dpkg -i "${debs[@]}" || true
	apt-get install -y -f
else
	log "Adding Radxa package repo (VERIFY url/key in this script before trusting it)"
	if [[ ! -f "${RADXA_APT_KEYRING}" ]]; then
		tmpkey="$(mktemp)"
		if command -v curl >/dev/null 2>&1; then
			curl -fsSL "${RADXA_APT_KEY_URL}" -o "${tmpkey}" \
				|| die "could not fetch Radxa signing key (VERIFY RADXA_APT_KEY_URL)"
		else
			wget -qO "${tmpkey}" "${RADXA_APT_KEY_URL}" \
				|| die "could not fetch Radxa signing key (VERIFY RADXA_APT_KEY_URL)"
		fi
		install -m644 "${tmpkey}" "${RADXA_APT_KEYRING}"
		rm -f "${tmpkey}"
	fi
	echo "deb [signed-by=${RADXA_APT_KEYRING}] ${RADXA_APT_URL} ${RADXA_APT_SUITE} ${RADXA_APT_COMPONENTS}" \
		> "${RADXA_APT_LIST}"
	apt-get update
	log "Installing: ${PKGS[*]}"
	apt-get install -y "${PKGS[@]}" || die "package install failed (VERIFY package names/repo)"
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
log "Verify afterwards with: vulkaninfo | head, or glmark2-es2 / chrome://gpu on a desktop image."
