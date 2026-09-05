<h2 align="center">
  <a href=#><img src="https://raw.githubusercontent.com/armbian/.github/master/profile/logosmall.png" alt="Armbian logo"></a>
  <br><br>
</h2>

# Armbian Linux Build Framework

## Purpose of This Repository

The **Armbian Linux Build Framework** builds customizable OS images based on **Debian** or **Ubuntu** for **single-board computers (SBCs)** and embedded devices — including kernel, bootloader, and root filesystem — with fine-grained control over versions, configuration, firmware, device trees, and system tuning.

It supports **native**, **cross**, and **containerized** builds across multiple architectures (`x86_64`, `aarch64`, `armhf`, `riscv64`) and is suitable for development, testing, production, and automation.

> **Looking for prebuilt images?** Use [Armbian Imager](https://github.com/armbian/imager/releases) — the easiest way to download and flash Armbian to an SD card or USB drive. Available for Linux, macOS, and Windows.

## Quick Start

```bash
git clone https://github.com/armbian/build
cd build
./compile.sh
```

<a href="#armbian-linux-build-framework"><img src=".github/README.gif" alt="Build demonstration" width="100%"></a>

## Build Host Requirements

### Hardware
- **RAM:** ≥ 8 GB (less possible with `KERNEL_BTF=no`)
- **Disk:** ~50 GB free space
- **Architecture:** `x86_64`, `aarch64`, or `riscv64`

### Operating System
- **Native builds:** Armbian / Debian 13 (Trixie)
- **Containerized:** any Docker-capable Linux
- **Windows:** WSL2 with Armbian / Debian 13 (Trixie)

### Software
- Superuser privileges (`sudo` or root)
- Up-to-date system (outdated Docker or other tooling can cause failures)

## Built With

The framework itself is implemented primarily in **Bash** (the top-level entrypoint `compile.sh` and the code under `lib/`, `extensions/`, `tools/` and the `packages/` helpers), with some **Python** utilities. Board, kernel, u-boot, distribution and boot-environment definitions live as plain config, Kconfig, `Makefile` fragments, device-tree sources/overlays and patch series under `config/` and `patch/`. Repository automation is defined as **GitHub Actions** workflows (YAML) under `.github/workflows/`.

## Repository Layout

| Path | Purpose |
|:--|:--|
| `compile.sh` | Top-level entrypoint that sources `lib/single.sh` and dispatches the CLI. |
| `lib/` | Core build library (functions, tooling helpers). |
| `extensions/` | Optional build extensions enabled via `ENABLE_EXTENSIONS=`. |
| `config/boards/` | Per-board configuration files (see support tiers below). |
| `config/bootenv/` | U-Boot boot-environment fragments per family / SoC. |
| `config/bootscripts/` | U-Boot boot scripts (`boot-*.cmd`). |
| `config/cli/` | Package lists for CLI / server userspace. |
| `config/distributions/` | Supported Debian/Ubuntu upstream releases and their status. |
| `config/sources/` | Kernel / u-boot family sources and includes. |
| `config/its/` | Image Tree Source (`.its`) files consumed by the device tree builder. |
| `patch/` | Kernel and u-boot patch archives, organized per branch/version. |
| `packages/` | Armbian-specific packaging (`bsp`, `bsp-cli`, `armbian` kernel packaging scripts, etc.). |
| `tools/` | Small helper utilities (e.g. `mk_format_patch`, `unifying_configs`). |
| `action.yml` | Composite GitHub Action `Rebuild Armbian` — reusable from other repos/workflows. |
| `.github/workflows/` | Repository automation (labels, board data sync, dispatch, mirroring, lint, etc.). |

### Board support tiers

Board configuration files under `config/boards/` are named by their support level (see `config/boards/README.md` and `config/distributions/README.md`):

| Extension | Meaning |
|:--|:--|
| `.conf` | Supported — current package base. |
| `.wip`  | Work in progress. |
| `.csc`  | Community maintained / unstable. |
| `.eos`  | End of life. |
| `.tvb`  | TV box. |

Board options (`BOARD_NAME`, `BOARDFAMILY`, `BOOTCONFIG`, `KERNEL_TARGET`, `SERIALCON`, `MODULES`, `DEFAULT_OVERLAYS`, …) are documented in [`config/boards/README.md`](config/boards/README.md).

## Reusable GitHub Action

This repo also ships a composite action at [`action.yml`](action.yml) (`Rebuild Armbian`) that other workflows can reuse to build a kernel or a full image with configurable board, branch, release, UI, extensions, compression, signing and release-publishing inputs.

## Continuous Integration

Repository automation is implemented as GitHub Actions workflows in `.github/workflows/`. For an overview of what runs, its status, and history, see the Armbian CI dashboard:

👉 <https://actions.armbian.com/?repo=build>

Notes for self-hosted runners are collected in [`.github/workflows/README.md`](.github/workflows/README.md).

## Resources

- **[Documentation](https://docs.armbian.com/Developer-Guide_Overview/)** — Guides for building, configuring, and customizing.
- **[Website](https://www.armbian.com)** — News, features, and board information.
- **[Blog](https://blog.armbian.com)** — Development updates and technical articles.
- **[Forums](https://forum.armbian.com)** — Community support and discussions.

## Contributing

Contributions are welcome — from typo fixes to new board support. See [CONTRIBUTING.md](CONTRIBUTING.md) for how to report issues, prepare an environment, generate patches, and submit pull requests. Credits are listed in [CREDITS.md](CREDITS.md).

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

## Contributors

Thank you to everyone who has contributed to Armbian!

<a href="https://github.com/armbian/build/graphs/contributors">
  <img alt="Contributors" src="https://contrib.rocks/image?repo=armbian/build" />
</a>

## Armbian Partners

Our [partnership program](https://forum.armbian.com/subscriptions) supports Armbian's development and community. Learn more about [our Partners](https://armbian.com/partners).

## License

Released under the [GNU General Public License v2.0](LICENSE).
