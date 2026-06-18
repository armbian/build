# sun60iw2 (A733) GPU/VPU acceleration — opt-in

**Status: first draft / WIP. Not yet verified on hardware.**

This adds *optional* PowerVR GPU acceleration to the sun60iw2 (Allwinner A733)
boards. It is deliberately kept out of the base image and is opt-in, because the
GPU userspace is non-redistributable and headless installs don't need it.

## TL;DR

After flashing and booting an Armbian sun60iw2 image, a user who wants GPU
acceleration runs:

```
sudo /usr/local/sbin/enable-powervr-gpu
```

That script builds the GPU kernel module from source (DKMS) and installs the
matched proprietary userspace from Radxa's packages. Nothing proprietary is
shipped in the image itself.

## Why it's built this way

The A733 GPU is an Imagination PowerVR BXM. Enabling it needs two halves:

1. **Kernel module** (`pvrsrvkm.ko`). This has source. Orange Pi's own 6.6 kernel
   tree carries the Imagination driver at `bsp/modules/gpu/img-bxm/.../rogue_km`,
   and Radxa ships the same driver as a DKMS *source* package (`img-bxm-dkms`).
   Either way the module is **compiled from source**, not extracted as a binary.

2. **Userspace** (`libsrv_um`, `libGLESv2_PVR`, EGL, the Vulkan ICD, the DRI
   driver, `rgx.*` firmware). This is Imagination's proprietary DDK. **There is no
   open source for it** — it only exists as a vendor binary.

### The one hard constraint: KM ↔ UM DDK versions must match

The PowerVR kernel module and userspace are two ends of one DDK release and must
be the **same version**. You cannot freely mix, e.g., Orange Pi's in-tree kernel
module with Radxa's userspace. This is exactly why the proven transplant
(`Incipiens/OrangePiZero3W-GPU-VPU`) uses Radxa's `img-bxm-dkms` **and** Radxa's
userspace together — a single, internally-matched set — even though it builds the
module against a 6.6.x-sun60iw2 kernel.

This draft follows the same matched-set principle: pull **both** halves from
Radxa's packages (DKMS module source + matched userspace). The module is built
from source against our kernel; only the irreducibly-closed userspace is a binary.

### Packages, not image carving

The proven `Incipiens` hack loop-mounts a Radxa disk image and copies files out of
it. That works but is ugly and has poor provenance. Radxa's images are built by
[`rsdk`](https://github.com/RadxaOS-SDK/rsdk) from Radxa's Debian package repo
(`radxa-build/radxa-a733` only hosts the build workflow). So the same binaries are
available as **`.deb` packages** with real versioning and dependencies — that's
what `enable-powervr-gpu.sh` consumes instead of carving an image.

### Confirmed package source (June 2026)

The packages live in Radxa's **`a733-bullseye`** apt repo
(`https://github.com/radxa-repo/a733-bullseye`), suite `a733-bullseye`, component
`main`. The signing key is `radxa-archive-keyring` (a `.deb` from
[`radxa-pkg/radxa-archive-keyring`](https://github.com/radxa-pkg/radxa-archive-keyring)
that installs `/usr/share/keyrings/radxa-archive-keyring.gpg`).

| Package | Version | Arch | Role |
|---|---|---|---|
| `img-bxm-dkms` | `0.1.0-3` | all | GPU kernel module — built from source via DKMS |
| `xserver-xorg-img-bxm` | `1.21.1-2` | arm64 | PowerVR userspace (GLES/EGL/Vulkan ICD/DRI/rgx fw) |
| `libcedarc-dev` | `2.0.0` | arm64 | Cedar VPU userspace (`--with-vpu`) |
| `libgstreamer-openmax-allwinner` | `1.4.6-3` | arm64 | gst-omx VPU plugin (`--with-vpu`) |

The GPU module and userspace are a matched DDK pair shipped in the same suite, so
pulling both from `a733-bullseye` keeps them version-coherent.

### Why opt-in and not in the image

The PowerVR userspace is non-redistributable, so Armbian can't bake it into a
published image regardless. Shipping a small enabler script that fetches the
vendor packages on demand keeps the image clean and licensing-safe, and matches
the fact that GPU accel is optional for this project's headless use case.

## What ships in the image vs. what the script fetches

| Component | Source | Where it lives |
|---|---|---|
| `enable-powervr-gpu` script | this repo (GPL) | baked into the image (`/usr/local/sbin`) |
| `pvrsrvkm.ko` GPU module | built from source (DKMS) | built on first run |
| PowerVR userspace + firmware | Radxa `.deb` (proprietary) | fetched on first run |
| Cedar VPU userspace (`--with-vpu`) | Radxa `.deb` | fetched on first run |

## Suite mismatch — the main open risk

These packages are built for **Debian 11 (bullseye)** and we install them on an
Armbian **Trixie (Debian 13)** rootfs. Two consequences to validate on hardware:

- **Userspace dependencies / Xorg ABI.** `xserver-xorg-img-bxm` is packaged as an
  Xorg DDX and pulls an X server stack whose ABI is bullseye's, not Trixie's. On a
  headless image we don't want X at all — what we actually need is the render-node
  path (`pvrsrvkm` + `libsrv_um` + GLES/EGL + the Vulkan ICD), which depends mainly
  on `libc`/`libdrm` and should be far more portable across suites (newer glibc
  runs older binaries). The likely outcome: GLES/EGL/Vulkan **offscreen/render**
  works; **X11 acceleration** does not on Trixie. We may need to install only the
  render libs (as the `Incipiens` hack does, skipping the Xorg files) rather than
  apt-installing the whole package on a headless rootfs.
- **VPU is higher-risk than GPU.** `libgstreamer-openmax-allwinner` (`1.4.6-3`)
  targets GStreamer 1.18 (bullseye); Trixie ships 1.24+. Expect the gst-omx path to
  need more work than the GPU path. `--with-vpu` is therefore the more experimental
  option.

The `--debs DIR` mode (hand-pulled `.deb`s, `dpkg -i`) is the escape hatch when the
repo's dependency resolution fights with Trixie.

## Other open items

- **`sunxi-sid.h`** availability in the Armbian `linux-headers` package. Orange
  Pi's tree has it under `bsp/include`; confirm the headers package installs it.
  If not, stage it under `/usr/src/linux-headers-$(uname -r)/bsp/include/` before
  the DKMS build (the `Incipiens` hack copies it from the Radxa headers).
- **Does `img-bxm-dkms` 0.1.0-3 build against our 6.6 kernel?** Incipiens proved
  0.1.0-2 builds against 6.6.98-sun60iw2; -3 is expected to as well, but untested.
- **Hardware test.** Nothing here has been run on a board yet.

## Possible future refinement: build the module in the kernel package

Instead of on-device DKMS, the module could be built host-side from Orange Pi's
in-tree `bsp/modules/gpu` and shipped inside the `linux-image` package (dok2d's
kernel build has a working recipe: set `LICHEE_TOOLCHAIN_PATH` /
`LICHEE_CROSS_COMPILER`, strip `.SECONDARY` from the GPU kbuild template for GNU
make ≥ 4.4). That's more "Armbian-native," but then the userspace must match
**Orange Pi's** DDK version rather than Radxa's — which is only known to be
published for their bullseye/5.15 stack. Left as a follow-up until the version
question is resolved.

## References

- `Incipiens/OrangePiZero3W-GPU-VPU` — proven GPU+VPU transplant onto a
  6.6-sun60iw2 image (the method this is derived from).
- `RadxaOS-SDK/rsdk`, `radxa-build/radxa-a733` — where Radxa's images/packages
  come from.
- Project notes: `notes/10-opi-a733-kernel-fork-analysis.md` (in-tree GPU source),
  `notes/13-gpu-vpu-acceleration.md` (this effort).
