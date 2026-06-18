# sun60iw2 (A733) GPU/VPU acceleration — opt-in

**Status: GPU validated on hardware (Orange Pi 4 Pro, headless Trixie).** VPU
(`--with-vpu`) is still untested.

This adds *optional* PowerVR GPU acceleration to the sun60iw2 (Allwinner A733)
boards. It is deliberately kept out of the base image and is opt-in, because the
GPU userspace is non-redistributable and headless installs don't need it.

## Validation (confirmed on hardware)

After running the enabler and rebooting on a headless Trixie image:

- Kernel: `pvrsrvkm` loads, `[drm] Initialized pvr 24.2.6603887`, RGX firmware
  (`rgx.fw.36.56.104.183`) loads on first client connect, `renderD128` present
  and owned by `pvrsrvkm` (`img,gpu`).
- **OpenCL works** — `clinfo` enumerates `PowerVR B-Series BXM-4-64`, contexts
  create successfully, and the device's `Driver Version 24.2@6603887` matches the
  kernel's `pvr` build, proving the `img-bxm-dkms` (KM) and `xserver-xorg-img-bxm`
  (UM) are a genuinely matched DDK pair. This is the validation path for a
  headless server (OpenCL needs no display).
- **Vulkan/GLES** load (after the X/Wayland client libs are installed) but fail to
  create an instance on a bare TTY — they need a display/compositor. Expected on a
  headless box; not a sign of a broken GPU.

Two gaps in Radxa's desktop-built packages that the enabler now fixes
automatically: the userspace links X/Wayland client libs (must be installed or the
drivers won't even `dlopen`), and the OpenCL driver ships without its
`/etc/OpenCL/vendors/*.icd` registration (so `clinfo` finds 0 platforms until it's
created).

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

**Caveat — malformed package names.** The userspace and 2.0.0 VPU packages have
the version and `.deb` suffix baked into their `Package:` field (e.g.
`xserver-xorg-img-bxm-1.21.1-2.deb`, `libcedarc-dev-2.0.0-arm64`). That's ugly but
apt still installs them by that exact literal name — it only treats a name as a
local file when a matching file exists in the cwd. So the script just lists the
literal names; no pool-path workaround needed. (The clean name `xserver-xorg-img-bxm`
fails with "Unable to locate package" precisely because the real name is mangled.)

## AI accelerator (NPU) — not available here

Asked to look: the `a733-bullseye` repo has **no Allwinner NPU userspace package**.
The `rknn2` / `rknn_model_zoo` entries in the repo are Rockchip RKNN, not Allwinner,
so they don't apply to the A733's VeriSilicon NPU. The only unexplored candidate is
`allwinner-prebuilt-extra` (0.1.9) — worth a `dpkg -c` to see if it bundles any NPU
libraries (`libVIPlite`, `libovx`, `galcore`, etc.). NPU enablement is a separate,
larger effort (its own kernel driver + userspace) and is out of scope for this GPU
draft.

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

- **Userspace dependencies / Xorg ABI.** RESOLVED (tested on hardware): the
  userspace package installs cleanly on Trixie via apt with **no heavy
  dependencies and no conflicts**. At runtime the drivers need a handful of
  X/Wayland *client* libs present to load (the enabler installs them), after which
  **OpenCL works**. The bundled Xorg DDX (ABI 1.21 vs Trixie's newer Xserver) and
  headless Vulkan/GLES are not usable without a display — but that's irrelevant to
  a headless server, where the render node + OpenCL are what count.
- **VPU is higher-risk than GPU.** `libgstreamer-openmax-allwinner` (`1.4.6-3`)
  targets GStreamer 1.18 (bullseye); Trixie ships 1.24+. Expect the gst-omx path to
  need more work than the GPU path. `--with-vpu` is therefore the more experimental
  option.

The `--debs DIR` mode (hand-pulled `.deb`s, `dpkg -i`) is the escape hatch when the
repo's dependency resolution fights with Trixie.

## Other open items

- **`bsp/include` headers** — Armbian's `linux-headers` package omits the vendor
  `bsp/` subtree, so the GPU DKMS build couldn't find `<sunxi-sid.h>`. RESOLVED by
  `pre_package_kernel_headers__sun60iw2_bsp_include` in the family, which copies the
  kernel's own `bsp/include` into the headers package (version-matched, and useful
  to any out-of-tree module). The kernel Makefile already puts `-I$(srctree)/bsp/include`
  on `LINUXINCLUDE`, so the angle-bracket include resolves with no per-build
  staging. CONFIRMED on hardware that `sunxi-sid.h` is the only `bsp/` header the
  build needs — with `bsp/include` present, `img-bxm-dkms` 0.1.0-3 compiles fully
  against our 6.6 vendor kernel. (The enabler just sanity-checks the header is
  present and errors out clearly if the headers package predates this hook.)
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
