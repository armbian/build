<h2 align="center">
  <a href=#><img src="https://raw.githubusercontent.com/armbian/.github/master/profile/logosmall.png" alt="Armbian logo"></a>
  <br><br>
</h2>

# Armbian Linux Build Framework

## Purpose of This Repository

The **Armbian Linux Build Framework** is the tooling that builds customizable **Debian**- and **Ubuntu**-based OS images (and kernels, U-Boot, and BSP packages) for a wide range of **single-board computers (SBCs)** and other embedded devices.

It supports **native**, **cross**, and **containerized** builds for multiple architectures (`x86_64`, `aarch64`, `armhf`, `riscv64`) and is suitable for development, testing, production, and automation.

> **Looking for prebuilt images?** Use [Armbian Imager](https://github.com/armbian/imager/releases) — the easiest way to download and flash Armbian to an SD card or USB drive. Available for Linux, macOS, and Windows.

## Quick Start

```bash
git clone https://github.com/armbian/build
cd build
./compile.sh
```

<a href="#quick-start"><img src=".github/README.gif" alt="Build demonstration" width="100%"></a>

`compile.sh` is the entry point of the framework; it sources the rest of the build library from `lib/` and drives the interactive/CLI build flow.

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
- An up-to-date host system (outdated Docker or other host tooling can cause failures)

## Built With

The framework is primarily **Bash**, with **Python** helpers, patch series applied to Linux/U-Boot/other upstream sources, YAML for CI and configuration data, plain-text `.conf` fragments for boards/families/distributions, and Debian packaging (`Makefile`, control files, etc.) in `packages/`.

## Repository Layout

| Path | Purpose |
|:--|:--|
| `compile.sh` | Main entry point of the build framework |
| `lib/` | Core build library sourced by `compile.sh` |
| `config/` | Board, family, distribution, kernel and boot-env configuration |
| `config/boards/` | Per-board configuration files (see [`config/boards/README.md`](config/boards/README.md)) |
| `config/sources/` | SoC / family sources definitions |
| `config/distributions/` | Supported Debian/Ubuntu release definitions |
| `config/cli/` | CLI userspace package lists |
| `patch/` | Patches applied to kernel, U-Boot and other upstream sources |
| `packages/` | Armbian packaging: kernel deb scripts, `bsp`, `bsp-cli`, `blobs`, `extras-buildpkgs` (see [`packages/README.md`](packages/README.md)) |
| `extensions/` | Optional build-time extensions |
| `tools/` | Helper tools (see [`tools/README.md`](tools/README.md)) |
| `action.yml` | Reusable **GitHub composite Action** (`Rebuild Armbian`) for building images/kernels in CI |
| `VERSION` | Current framework version |

### Board configuration file extensions

Board configs in `config/boards/` use a file extension that reflects their support status:

| Extension | Meaning |
|:--|:--|
| `.conf` | Supported |
| `.csc` | Community maintained / unstable |
| `.wip` | Work in progress |
| `.eos` | End of life |
| `.tvb` | TV box |

See [`config/distributions/README.md`](config/distributions/README.md) for the equivalent status tags applied to upstream distribution support.

## Using the Reusable GitHub Action

This repository also ships `action.yml`, a composite GitHub Action named `Rebuild Armbian` that other workflows can call to build an image or a kernel using this framework. Its inputs include, among others:

- `armbian_target` – build `image` or `kernel` (default: `kernel`)
- `armbian_board` – target board (default: `uefi-x86`)
- `armbian_branch` – framework branch to check out (default: `main`)
- `armbian_kernel_branch` – kernel branch, e.g. `current` / `edge` / `legacy` (default: `current`)
- `armbian_release` – userspace release (default: `noble`)
- `armbian_ui` – `minimal`, `server`, or a desktop environment name (default: `minimal`)
- `armbian_compress` – output compression, e.g. `sha,img,xz`
- `armbian_extensions` – extensions to enable
- `armbian_pgp_key` / `armbian_pgp_password` – optional signing key material

See `action.yml` for the full input list and defaults.

## Continuous Integration

The workflows in `.github/workflows/` cover data sync, maintenance, security scans, artifact builds and infrastructure mirroring. Rather than duplicate that list here, see the live overview:

👉 <https://actions.armbian.com/?repo=build>

## Contributing

Contributions are welcome — issues, docs, bug fixes and features alike. See [CONTRIBUTING.md](CONTRIBUTING.md) for the workflow (forking, patch creation, PR labels, commit message expectations), and [CREDITS.md](CREDITS.md) for authors.

## Resources

- **[Documentation](https://docs.armbian.com/Developer-Guide_Overview/)** — building, configuring, and customizing
- **[Website](https://www.armbian.com)** — news, features, and board information
- **[Blog](https://blog.armbian.com)** — development updates and technical articles
- **[Forums](https://forum.armbian.com)** — community support and discussions

## Support

### Community forums
Help from users and contributors on troubleshooting, configuration, and development.
👉 [forum.armbian.com](https://forum.armbian.com)

### Real-time chat
Discussions with developers and the community on IRC or Discord.
👉 [Community Chat](https://docs.armbian.com/Community_IRC/)

### Paid consultation
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

This project is licensed under the **GNU General Public License v2.0**. See [LICENSE](LICENSE) for details.
