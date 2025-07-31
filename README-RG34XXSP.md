# RG34XXSP Armbian Support Branch

This is the active development branch for RG34XXSP Armbian support, forked from the official Armbian build system.

## Repository Structure

- **CLAUDE.md** - Project instructions and development guidelines
- **CLAUDEDOCS/** - Active documentation copied from main project repo
- **CLAUDESCRIPTS/** - Active scripts copied from main project repo
- **config/boards/rg34xxsp.csc** - Board configuration for RG34XXSP
- **packages/bsp/rg34xxsp/** - Board Support Package files
- **patch/kernel/archive/sunxi-6.12/** - Kernel patches for H700 support

## Original Project

This fork originated from the RG34XXSP-Armbian-Port project at https://github.com/mitswan/RG34XXSP-Armbian-Port

The original repository now contains historical documentation and obsolete content, while this repository contains the active Armbian build system with RG34XXSP support.

## Build Instructions

See CLAUDE.md for complete development guidelines and CLAUDEDOCS/PLAN.md for current implementation status.

```bash
./compile.sh build BOARD=rg34xxsp BRANCH=current RELEASE=bookworm BUILD_MINIMAL=yes BUILD_DESKTOP=no KERNEL_CONFIGURE=no
```

## Hardware Support

The RG34XXSP is based on the Allwinner H700 SoC with the following key features:
- ARM64 Cortex-A53 quad-core CPU
- Mali-G31 GPU
- 3.5" IPS display (640x480)
- Built-in WiFi and Bluetooth
- Handheld gaming form factor

## Community Status

This is a community-maintained board configuration. It follows Armbian's community build standards and is intended for eventual upstream submission to the official Armbian project.

---

*For the complete official Armbian documentation, see the original README.md*