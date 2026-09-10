<h2 align="center">
  <a href=#><img src="https://raw.githubusercontent.com/armbian/.github/master/profile/logosmall.png" alt="Armbian logo"></a>
  <br><br>
</h2>

# Armbian Linux Build Framework

## Purpose of This Repository

The **Armbian Linux Build Framework** creates customizable OS images based on **Debian** or **Ubuntu** for **single-board computers (SBCs)** and embedded devices. It builds a complete Linux system — bootloader, kernel, device trees, firmware, and root filesystem — giving you full control over versions, configuration, and system tuning.

The framework supports **native**, **cross**, and **containerized** builds for multiple architectures (`x86_64`, `aarch64`, `armhf`, `riscv64`) and is suitable for development, testing, production, and automation.

> **Looking for prebuilt images?** Use [Armbian Imager](https://github.com/armbian/imager/releases) — the easiest way to download and flash Armbian to your SD card or USB drive. Available for Linux, macOS, and Windows.

## Quick Start

```bash
git clone https://github.com/armbian/build
cd build
./compile.sh
```

<a href="#armbian-linux-build-framework"><img src=".github/README.gif" alt="Build demonstration" width="100%"></a>

The interactive menu will guide you through selecting a target (image or kernel), a board, a kernel branch, and a userspace release. Non-interactive builds are also supported by passing build parameters on the command line — see the documentation for the full list of options.

## Build Host Requirements

### Hardware
- **RAM:** ≥ 8 GB (less possible with `KERNEL_BTF=no`)
- **Disk:** ~50 GB free space
- **Architecture:** `x86_64`, `aarch64`, or `riscv64`

### Operating System
- **Native builds:** Armbian/Debian 13 (Trixie)
- **Containerized:** any Docker-capable Linux
- **Windows:** WSL2 with Armbian/Debian 13 (Trixie)

### Software
- Superuser privileges (`sudo` or root)
- An up-to-date system (outdated Docker or other tooling can cause build failures)

The framework itself is written primarily in **Bash** with **Python** helpers, and drives GNU **Make**, cross-toolchains, `debootstrap`, `apt`/`aptly`, and related packaging tools.

## Repository Layout

| Path | Contents |
|:--|:--|
| `compile.sh` | Main entrypoint that sources the framework and starts the CLI |
| `lib/` | Build framework libraries (functions, tooling, single-entry loader) |
| `config/` | Configuration: boards, boot environments, kernels, distributions, sources |
| `config/boards/` | Per-board definitions (see [`config/boards/README.md`](config/boards/README.md) for the full list of options) |
| `config/distributions/` | Supported Debian/Ubuntu userspace bases and their status |
| `config/sources/` | SoC/family sources and mappings |
| `patch/` | Kernel, U-Boot, ATF and misc. patches, organized per branch/family |
| `extensions/` | Optional build-time extensions |
| `packages/` | Armbian package sources (kernel packaging scripts, BSP, etc.) |
| `tools/` | Helper tools (see [`tools/README.md`](tools/README.md)) |
| `action.yml` | Composite GitHub Action `Rebuild Armbian` for building images/kernels in CI |

### Board support status

Board configurations under `config/boards/` are named with a suffix indicating their support level:

| Suffix | Meaning |
|:--|:--|
| `.conf` | Supported |
| `.wip` | Work in progress |
| `.csc` | Community maintained / unstable |
| `.eos` | End of life |
| `.tvb` | TV box |

## Using as a GitHub Action

This repository also ships a composite action (`action.yml`, `Rebuild Armbian`) that wraps a build inside a GitHub workflow. It accepts inputs such as `armbian_target`, `armbian_board`, `armbian_branch`, `armbian_kernel_branch`, `armbian_release`, `armbian_ui`, `armbian_compress`, `armbian_extensions`, and optional GPG signing keys, and uploads the resulting artifacts from `build/output/images/`.

## Continuous Integration

CI for this repository is tracked centrally on the Armbian actions dashboard:

👉 **[actions.armbian.com — build](https://actions.armbian.com/?repo=build)**

## Resources

- **[Documentation](https://docs.armbian.com/Developer-Guide_Overview/)** — Comprehensive guides for building, configuring, and customizing
- **[Website](https://www.armbian.com)** — News, features, and board information
- **[Blog](https://blog.armbian.com)** — Development updates and technical articles
- **[Forums](https://forum.armbian.com)** — Community support and discussions

## Contributing

We welcome contributions! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on reporting issues, submitting changes, and contributing code. Credits and authors are listed in [CREDITS.md](CREDITS.md).

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

Released under the **GNU General Public License, version 2** — see [LICENSE](LICENSE).

## Contributors

Thank you to everyone who has contributed to Armbian!

<a href="https://github.com/armbian/build/graphs/contributors">
  <img alt="Contributors" src="https://contrib.rocks/image?repo=armbian/build" />
</a>

## Armbian Partners

Our [partnership program](https://forum.armbian.com/subscriptions) supports Armbian's development and community. Learn more about [our Partners](https://armbian.com/partners).
