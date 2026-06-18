#!/bin/bash
#
# enable-powervr-gpu.sh — opt-in PowerVR (BXM) GPU + Cedar VPU acceleration for
# Armbian sun60iw2 (Allwinner A733). Builds the GPU kernel module from source
# (DKMS) and installs Radxa's non-redistributable userspace on demand. Validated
# on Orange Pi 4 Pro (headless Trixie): OpenCL + H.264 HW decode. See README.md.
#
# SPDX-License-Identifier: GPL-2.0
#

set -euo pipefail

# Radxa's a733-bullseye apt repo (built by rsdk); pulled from, not carved from an image.
RADXA_APT_LIST="/etc/apt/sources.list.d/radxa-a733-gpu.list"
RADXA_APT_URL="https://radxa-repo.github.io/a733-bullseye"
RADXA_APT_SUITE="a733-bullseye"
RADXA_APT_COMPONENTS="main"
RADXA_APT_KEYRING="/usr/share/keyrings/radxa-archive-keyring.gpg"
RADXA_KEYRING_RELEASE="https://github.com/radxa-pkg/radxa-archive-keyring/releases/latest/download"

# Userspace/VPU Package: names are malformed (version + ".deb" baked in), but apt
# still installs them by that literal name.
PKG_GPU_DKMS="img-bxm-dkms"
PKG_GPU_USERSPACE="xserver-xorg-img-bxm-1.21.1-2.deb"
PKG_VPU=("libcedarc-dev-2.0.0-arm64" "libgstreamer-openmax-allwinner")

log() { echo ">> $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

# Needs root (apt, dpkg, modprobe, /etc writes); re-exec under sudo if we aren't.
if [[ ${EUID} -ne 0 ]]; then
	command -v sudo > /dev/null 2>&1 || die "must run as root (sudo not found)"
	log "Not root — re-running under sudo"
	exec sudo -- "$0" "$@"
fi

KVER="$(uname -r)"
case "${KVER}" in
	*sun60iw2*) ;;
	*) die "This is for sun60iw2 (A733) kernels; running kernel is '${KVER}'." ;;
esac
log "Target kernel: ${KVER}"

# --- Build prerequisites ----------------------------------------------------
log "Installing build prerequisites (dkms, kernel headers, curl)"
apt-get update
apt-get install -y --no-install-recommends dkms curl ca-certificates || die "could not install build prerequisites"

if [[ ! -d "/usr/src/linux-headers-${KVER}" && ! -d "/lib/modules/${KVER}/build" ]]; then
	apt-get install -y "linux-headers-${KVER}" 2>/dev/null \
		|| die "kernel headers for ${KVER} not found; install the matching linux-headers package first"
fi

# img-bxm-dkms includes <sunxi-sid.h>, shipped in bsp/include by our
# pre_package_kernel_headers hook (which the kernel Makefile puts on -I).
if ! find "/usr/src/linux-headers-${KVER}" -name sunxi-sid.h 2>/dev/null | grep -q .; then
	die "sunxi-sid.h missing from the headers package (rebuild the image with the pre_package_kernel_headers hook)"
fi

# --- Install GPU + VPU packages ---------------------------------------------
log "Installing Radxa archive keyring"
if [[ ! -f "${RADXA_APT_KEYRING}" ]]; then
	tmpd="$(mktemp -d)"
	ver="$(curl -fsSL "${RADXA_KEYRING_RELEASE}/VERSION")" || die "could not query radxa-archive-keyring version"
	curl -fsSL -o "${tmpd}/keyring.deb" "${RADXA_KEYRING_RELEASE}/radxa-archive-keyring_${ver}_all.deb" \
		|| die "could not download radxa-archive-keyring"
	dpkg -i "${tmpd}/keyring.deb" || die "radxa-archive-keyring install failed"
	rm -rf "${tmpd}"
fi

log "Adding Radxa a733-bullseye package repo"
echo "deb [signed-by=${RADXA_APT_KEYRING}] ${RADXA_APT_URL}/ ${RADXA_APT_SUITE} ${RADXA_APT_COMPONENTS}" \
	> "${RADXA_APT_LIST}"
apt-get update

log "Installing GPU + VPU packages"
apt-get install -y "${PKG_GPU_DKMS}" "${PKG_GPU_USERSPACE}" "${PKG_VPU[@]}" || die "package install failed — see README"

# --- Ensure the kernel module built (DKMS, from source) ---------------------
log "Checking DKMS build of the GPU module"
dkms status 2>/dev/null | grep -i img-bxm || true
if ! find "/lib/modules/${KVER}" -name 'pvrsrvkm.ko*' 2>/dev/null | grep -q .; then
	log "pvrsrvkm.ko not present yet; running dkms autoinstall for ${KVER}"
	dkms autoinstall -k "${KVER}" || true
fi
find "/lib/modules/${KVER}" -name 'pvrsrvkm.ko*' 2>/dev/null | grep -q . \
	|| die "pvrsrvkm.ko was not built for ${KVER}; inspect /var/lib/dkms/*/make.log"
depmod "${KVER}"

# --- Runtime wiring ---------------------------------------------------------
log "Autoloading pvrsrvkm at boot"
echo "pvrsrvkm" > /etc/modules-load.d/pvr.conf
ldconfig

# Desktop-built userspace links X/Wayland client libs; install them or the drivers won't dlopen.
log "Installing PowerVR userspace runtime deps (X/Wayland client libs)"
apt-get install -y --no-install-recommends \
	libx11-xcb1 libxcb-dri3-0 libxcb-present0 libxcb-sync1 libxshmfence1 libwayland-client0 \
	|| log "WARNING: could not install some X/Wayland client libs; Vulkan/GLES may not load."

# Radxa bundles its own libOpenCL; install ocl-icd first, then divert Radxa's
# aside so there's a single loader (diverting first would leave none).
log "Standardising on the ocl-icd OpenCL loader"
apt-get install -y --no-install-recommends ocl-icd-libopencl1 \
	|| log "WARNING: could not install ocl-icd-libopencl1; leaving Radxa's bundled loader in place."
if dpkg -s ocl-icd-libopencl1 > /dev/null 2>&1; then
	for f in /usr/lib/libOpenCL.so /usr/lib/libOpenCL.so.1; do
		if [[ -e "${f}" ]] && ! dpkg-divert --list "${f}" | grep -q .; then
			dpkg-divert --add --rename --divert "${f}.radxa-disabled" "${f}"
		fi
	done
	ldconfig
fi

# Register the OpenCL ICD the package omits (else clinfo finds 0 platforms).
ocl_lib="$(ldconfig -p | awk '/libPVROCL\.so\.1/{print $NF; exit}')"
if [[ -n "${ocl_lib}" ]]; then
	log "Registering PowerVR OpenCL ICD (${ocl_lib})"
	install -d /etc/OpenCL/vendors
	echo "${ocl_lib}" > /etc/OpenCL/vendors/imgtec.icd
else
	log "WARNING: libPVROCL.so.1 not found; skipping OpenCL ICD registration."
fi

# Cedar VPU: device-node perms + gst-omx flags that avoid an OMX Loaded->Idle stall.
log "Wiring up Cedar VPU"
cat > /etc/udev/rules.d/99-cedar-ve.rules <<'EOF'
KERNEL=="cedar_dev*", MODE="0666"
SUBSYSTEM=="cedar_ve",  TAG+="uaccess", MODE="0666"
SUBSYSTEM=="cedar_ve2", TAG+="uaccess", MODE="0666"
EOF
GSTOMX="/etc/xdg/gstomx.conf"
if [[ -f "${GSTOMX}" ]]; then
	HACKS="event-port-settings-changed-ndata-parameter-swap;event-port-settings-changed-port-0-to-1;no-disable-outport;no-component-reconfigure;no-component-role;no-empty-eos-buffer;pass-color-format-to-decoder;pass-profile-to-decoder;signals-premature-eos;height-multiple-16"
	sed -i "s|^hacks=.*|hacks=${HACKS}|" "${GSTOMX}"
fi

# Load now so the running system matches its next-boot state (no reboot needed).
log "Loading the GPU module"
modprobe pvrsrvkm || die "modprobe pvrsrvkm failed; check dmesg"

log "Done. GPU + VPU active now and on boot."
log "Validate GPU: 'apt-get install clinfo && clinfo' lists 'PowerVR B-Series'."
log "Validate VPU: 'gst-inspect-1.0 omxh264dec' shows a Hardware decoder."
