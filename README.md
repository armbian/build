<h3 align="center">
  <a href=#><img src="https://raw.githubusercontent.com/armbian/.github/master/profile/logosmall.png" alt="Armbian logo"></a>
  <br><br>
</h3>

# Armbian Build Framework

The **Armbian Linux Build Framework** creates customizable OS images based on **Debian** or **Ubuntu** for **single-board computers (SBCs)** and embedded devices. It builds a complete Linux system — kernel, bootloader, and root filesystem — giving you control over versions, configuration, firmware, device trees, and system optimizations.

The framework supports **native**, **cross**, and **containerized** builds for multiple architectures (`x86_64`, `aarch64`, `armhf`, `riscv64`) and is suitable for development, testing, production, or automation.

> **Looking for prebuilt images?** Use [Armbian Imager](https://github.com/armbian/imager/releases) — the easiest way to download and flash Armbian to your SD card or USB drive. Available for Linux, macOS, and Windows.

## Quick Start

```bash
git clone https://github.com/armbian/build
cd build
./compile.sh
```

<a href="#armbian-build-framework"><img src=".github/README.gif" alt="Build demonstration" width="100%"></a>

## Build Host Requirements

### Hardware
- **RAM:** ≥8GB (less with `KERNEL_BTF=no`)
- **Disk:** ~50GB free space
- **Architecture:** x86_64, aarch64, or riscv64

### Operating System
- **Native builds:** Armbian or Ubuntu 24.04 (Noble)
- **Containerized:** Any Docker-capable Linux
- **Windows:** WSL2 with Armbian/Ubuntu 24.04

### Software
- Superuser privileges (`sudo` or root)
- Up-to-date system (outdated Docker or other tools can cause failures)

## What's in this repository

The build framework is driven by `compile.sh` (Bash) which sources the library under `lib/`. Board, kernel, bootloader, distribution, and userspace assets live in the top-level directories below.

| Path | Purpose |
|:--|:--|
| `compile.sh` | Entry point that sources `lib/single.sh` and dispatches to the CLI |
| `lib/` | Bash library implementing the build logic |
| `config/boards/` | Per-board configuration files (`.conf`, `.csc`, `.wip`, `.eos`, `.tvb`) |
| `config/bootenv/`, `config/bootscripts/` | U-Boot environment defaults and `boot-*.cmd` scripts |
| `config/cli/`, `config/distributions/` | Userspace package lists and distribution status |
| `config/sources/`, `config/sources/families/` | SoC / family definitions mapping boards to kernels and U-Boot |
| `patch/` | Kernel, U-Boot, ATF, and misc patches organized by target and version |
| `packages/` | Armbian-specific packaging (`bsp-cli`, `bsp-desktop`, kernel packaging helpers, board BSPs) |
| `extensions/` | Optional build extensions loaded via `ENABLE_EXTENSIONS` |
| `tools/` | Helper scripts (e.g. `mk_format_patch`, `unifying_configs`) |
| `action.yml` | GitHub composite action wrapping `compile.sh` for CI reuse |
| `VERSION` | Current framework version |

### Board configuration status

Board configuration files use their extension to signal support level:

| Extension | Meaning |
|:--|:--|
| `.conf` | Supported |
| `.csc` | Community maintained / unstable |
| `.wip` | Work in progress |
| `.eos` | End of life |
| `.tvb` | TV box |

See [`config/boards/README.md`](config/boards/README.md) for the full list of variables (e.g. `BOARDFAMILY`, `BOOTCONFIG`, `KERNEL_TARGET`, `SERIALCON`, `DEFAULT_OVERLAYS`, …) available in a board file.

## Reusable GitHub Action

`action.yml` exposes the framework as a composite action (`armbian/build`) that other workflows can call to build a kernel or image. Key inputs include `armbian_target` (`image` or `kernel`), `armbian_board`, `armbian_kernel_branch` (`legacy`/`current`/`edge`), `armbian_release`, `armbian_ui` (`minimal`, `server`, or a desktop environment), `armbian_extensions`, and `armbian_compress`. Optional PGP inputs sign the produced images.

Additional runner setup notes for self-hosted workers live in [`.github/workflows/README.md`](.github/workflows/README.md).

## Languages and tooling

- **Bash / POSIX shell** — `compile.sh`, everything under `lib/`, most of `packages/` and `tools/`, and the U-Boot boot script sources in `config/bootscripts/`
- **YAML** — GitHub Actions workflows in `.github/workflows/`, issue templates, `.pre-commit-config.yaml`, `.coderabbit.yaml`, and the composite `action.yml`
- **Python** — helper scripts used from the build library
- **Make / Kbuild** — device-tree overlay Makefiles under `patch/kernel/archive/*/overlay/`
- **C / device tree source** — kernel and U-Boot patches under `patch/`
- **Debian packaging** — under `packages/` (control files, postinst/prerm scripts, systemd units)

## Resources

- **[Documentation](https://docs.armbian.com/Developer-Guide_Overview/)** — Comprehensive guides for building, configuring, and customizing
- **[Website](https://www.armbian.com)** — News, features, and board information
- **[Blog](https://blog.armbian.com)** — Development updates and technical articles
- **[Forums](https://forum.armbian.com)** — Community support and discussions

## Contributing

We welcome contributions! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on reporting issues, submitting changes, and working with patches. Board maintainers are tracked automatically in `config/boards/*` and mirrored into [`.github/CODEOWNERS`](.github/CODEOWNERS).

## Support

### Community Forums
Get help from users and contributors on troubleshooting, configuration, and development.
👉 [forum.armbian.com](https://forum.armbian.com)

### Real-time Chat
Join discussions with developers and community members on IRC or Discord.
👉 [Community Chat](https://docs.armbian.com/Community_IRC/)

### Paid Consultation
For commercial projects, guaranteed response times, or advanced needs, paid support is available from Armbian maintainers.
👉 [Contact us](https://www.armbian.com/contact)

## License

This project is released under the **GNU General Public License v2.0** — see [`LICENSE`](LICENSE).

## Contributors

Thank you to everyone who has contributed to Armbian!

<a href="https://github.com/armbian/build/graphs/contributors">
  <img alt="Contributors" src="https://contrib.rocks/image?repo=armbian/build" />
</a>

## Armbian Partners

Our [partnership program](https://forum.armbian.com/subscriptions) supports Armbian's development and community. Learn more about [our Partners](https://armbian.com/partners).
