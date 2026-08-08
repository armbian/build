<h3 align="center">
  <a href=#><img src="https://raw.githubusercontent.com/armbian/.github/master/profile/logosmall.png" alt="Armbian logo"></a>
  <br><br>
</h3>

## Purpose of This Repository

The **Armbian Linux Build Framework** creates customizable OS images based on **Debian** or **Ubuntu** for **single-board computers (SBCs)** and embedded devices.

It builds a complete Linux system including kernel, bootloader, and root filesystem, giving you control over versions, configuration, firmware, device trees, and system optimizations.

The framework supports **native**, **cross**, and **containerized** builds for multiple architectures (`x86_64`, `aarch64`, `armhf`, `riscv64`) and is suitable for development, testing, production, or automation.

> **Looking for prebuilt images?** Use [Armbian Imager](https://github.com/armbian/imager/releases) — the easiest way to download and flash Armbian to your SD card or USB drive. Available for Linux, macOS, and Windows.

## Quick Start

```bash
git clone https://github.com/armbian/build
cd build
./compile.sh
```

<a href="#quick-start"><img src=".github/README.gif" alt="Build demonstration" width="100%"></a>

The entry point [`compile.sh`](compile.sh) sources `lib/single.sh` and delegates to the framework's CLI. It can also be invoked as a GitHub composite Action via [`action.yml`](action.yml) — see its `inputs:` (e.g. `armbian_target`, `armbian_board`, `armbian_kernel_branch`, `armbian_release`, `armbian_ui`) for the supported build parameters.

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

Under the hood, the framework is driven mainly by **Bash** (`compile.sh`, `lib/`, board/family configs, patch hooks) with some **Python** helpers (for example in `action.yml` when generating the release-assets manifest). Kernel and u-boot sources are patched from `patch/` and built with the usual upstream toolchains (kernel `Makefile`, u-boot defconfigs, device tree overlays, etc.).

## Repository Layout

| Path | What lives there |
|:--|:--|
| [`compile.sh`](compile.sh) | User-facing entry point; loads the framework and calls the CLI |
| [`action.yml`](action.yml) | GitHub composite Action wrapping `compile.sh` for CI-driven builds |
| `lib/` | Bash library implementing the build framework (functions, tools, CLI) |
| `config/boards/` | Per-board configuration files (see [`config/boards/README.md`](config/boards/README.md)) |
| `config/bootenv/`, `config/bootscripts/` | U-Boot environment fragments and boot script templates |
| `config/cli/` | CLI userspace package sets ([README](config/cli/README.md)) |
| `config/distributions/` | Supported Debian/Ubuntu release definitions ([README](config/distributions/README.md)) |
| `config/sources/` | SoC family sources and defaults ([README](config/sources/README.md)) |
| `config/its/` | Image Tree Source (`.its`) files used by the DT/image builder |
| `extensions/` | Optional build extensions activated via `ENABLE_EXTENSIONS=` |
| `packages/` | Armbian-specific package sources ([README](packages/README.md)) — kernel packaging (`armbian/`), BSP (`bsp/`, `bsp-cli/`, `bsp-desktop/`), blobs, extras |
| `patch/` | Kernel and u-boot patches, kernel `.config`s, and DT overlay Makefiles, organised per family/branch |
| `tools/` | Small maintenance helpers ([README](tools/README.md)) |
| `.github/` | Issue/PR templates, labels, CODEOWNERS, workflows |

### Board configuration files

Board files under `config/boards/` use a status suffix:

| Extension | Meaning |
|:--|:--|
| `.conf` | Supported |
| `.csc`  | Community maintained / unstable |
| `.wip`  | Work in progress |
| `.eos`  | End of life |
| `.tvb`  | TV-box class hardware |

The full list of variables that can be set inside a board file (e.g. `BOARDFAMILY`, `KERNEL_TARGET`, `BOOTCONFIG`, `SERIALCON`, `DEFAULT_OVERLAYS`, `PACKAGE_LIST_BOARD`, …) is documented in [`config/boards/README.md`](config/boards/README.md).

Distribution status labels used in `config/distributions/` follow the same idea (`supported`, `csc`, `eos`) — see [`config/distributions/README.md`](config/distributions/README.md).

## Continuous Integration

GitHub Actions workflows live in [`.github/workflows/`](.github/workflows/). See [`.github/workflows/README.md`](.github/workflows/README.md) for notes on self-hosted runner requirements (small / big / arm64) and how to run workflows against forked repositories via the `repository_dispatch` helper.

## Resources

- **[Documentation](https://docs.armbian.com/Developer-Guide_Overview/)** — Comprehensive guides for building, configuring, and customizing
- **[Website](https://www.armbian.com)** — News, features, and board information
- **[Blog](https://blog.armbian.com)** — Development updates and technical articles
- **[Forums](https://forum.armbian.com)** — Community support and discussions

## Contributing

We welcome contributions! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on reporting issues, submitting changes, and contributing code. Development conventions and code-review expectations are described in the [Development Code Review Procedures and Guidelines](https://docs.armbian.com/Development-Code_Review_Procedures_and_Guidelines/).

If you maintain a board, keep its entry accurate — the `BOARD_MAINTAINER` field in `config/boards/*` is periodically synced from the [maintainers database](https://www.armbian.com/update-data/).

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

This project is licensed under the **GNU General Public License, version 2** — see [LICENSE](LICENSE) for the full text. Contributor credits are listed in [CREDITS.md](CREDITS.md) and at [armbian.com/authors](https://www.armbian.com/authors).

## Contributors

Thank you to everyone who has contributed to Armbian!

<a href="https://github.com/armbian/build/graphs/contributors">
  <img alt="Contributors" src="https://contrib.rocks/image?repo=armbian/build" />
</a>

## Armbian Partners

Our [partnership program](https://forum.armbian.com/subscriptions) supports Armbian's development and community. Learn more about [our Partners](https://armbian.com/partners).
