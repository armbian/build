<h2 align="center">
  <a href=#><img src="https://raw.githubusercontent.com/armbian/.github/master/profile/logosmall.png" alt="Armbian logo"></a>
  <br><br>
</h2>

# Armbian Linux Build Framework

## Purpose of This Repository

The **Armbian Linux build framework** creates customizable OS images based on **Debian** or **Ubuntu** for **single-board computers (SBCs)** and embedded devices. It builds a complete Linux system — bootloader, kernel and root filesystem — with control over configuration, firmware, device trees and system optimizations.

The framework supports **native**, **cross** and **containerized** builds for multiple architectures (`x86_64`, `aarch64`, `armhf`, `riscv64`) and is suitable for development, testing, production and automation.

> **Looking for prebuilt images?** Use [Armbian Imager](https://github.com/armbian/imager/releases) — the easiest way to download and flash Armbian to an SD card or USB drive. Available for Linux, macOS and Windows.

## Quick Start

```bash
git clone https://github.com/armbian/build
cd build
./compile.sh
```

<a href="#quick-start"><img src=".github/README.gif" alt="Build demonstration" width="100%"></a>

## Build Host Requirements

### Hardware
- **RAM:** ≥ 8 GB (less with `KERNEL_BTF=no`)
- **Disk:** ~50 GB free space
- **Architecture:** `x86_64`, `aarch64` or `riscv64`

### Operating System
- **Native builds:** Armbian/Debian 13 (Trixie)
- **Containerized:** any Docker-capable Linux
- **Windows:** WSL2 with Armbian/Debian 13 (Trixie)

### Software
- Superuser privileges (`sudo` or root)
- An up-to-date system (an outdated Docker or other host tooling can cause failures)

## Built With

This framework is primarily a large collection of **Bash** scripts (see `compile.sh` and everything under `lib/`, driven by `lib/single.sh`), plus:

- **Kernel & U-Boot patches** and per-board device trees / overlays under `patch/` (thousands of `*.patch`, `*.dts*`, `*.dtbo`, plus overlay `Makefile`s)
- **Board, family, kernel and distribution configuration** under `config/` (shell fragments, kernel `.config`s, boot-env `.txt`s, Image Tree Source `.its`)
- **Debian packaging sources** under `packages/` (BSP for CLI and desktop, kernel packaging helpers, blobs, build packages)
- **Extensions** (opt-in build features) under `extensions/`
- **Reusable Bash tools** under `tools/` and `.github/scripts/` (with a small amount of **JavaScript** for GitHub Actions helpers, e.g. `.github/scripts/wip-label.js`)
- **CI in YAML** under `.github/workflows/` (see [CI overview](https://actions.armbian.com/?repo=build))
- A composite **GitHub Action** entrypoint in `action.yml` at the repo root

## Repository Layout

| Path | Purpose |
|---|---|
| `compile.sh` | Main CLI entrypoint; sources `lib/single.sh` and calls `cli_entrypoint` |
| `action.yml` | Composite GitHub Action (`Rebuild Armbian`) for building images/kernels in CI |
| `lib/` | Bash library that implements the build framework (`lib/single.sh` is the entry) |
| `config/boards/` | Per-board configuration (`.conf`, `.csc`, `.wip`, `.eos`, `.tvb`) |
| `config/bootenv/` | U-Boot boot-environment templates |
| `config/cli/` | CLI (minimal / server) package lists per release |
| `config/distributions/` | Supported Debian/Ubuntu release definitions |
| `config/its/` | Image Tree Source (`.its`) files for the device tree image builder |
| `packages/` | Debian packaging sources (`armbian`, `bsp`, `bsp-cli`, `bsp-desktop`, `blobs`, `extras-buildpkgs`) |
| `patch/` | Kernel and U-Boot patches, device trees and overlays, organised by target/version |
| `extensions/` | Optional build-time extensions (opted in via `ENABLE_EXTENSIONS`) |
| `tools/` | Small maintenance tools (`mk_format_patch`, `unifying_configs`) |
| `.github/` | Issue/PR templates, labels, CODEOWNERS generator, workflows |
| `VERSION` | Framework version marker |

### Board configuration file extensions

Board configs live in `config/boards/`. The file extension encodes support status; see [`config/boards/README.md`](config/boards/README.md) for the full list of variables.

| Extension | Meaning |
|---|---|
| `.conf` | Officially supported |
| `.csc` | Community maintained / unstable, no active Armbian maintainer |
| `.wip` | Work in progress |
| `.eos` | End of support |
| `.tvb` | TV box, community supported (no Armbian maintainer) |

### Upstream distributions

Supported Debian and Ubuntu bases are declared under `config/distributions/`. See [`config/distributions/README.md`](config/distributions/README.md) for the current support-level convention.

## Using It as a GitHub Action

This repository ships a composite Action (`action.yml`, name: **Rebuild Armbian**) that checks out `armbian/os`, `armbian/build` and your customisations, runs `./compile.sh requirements`, then invokes `./compile.sh` with the inputs you provide. Key inputs (defaults from `action.yml`):

| Input | Default |
|---|---|
| `armbian_target` | `kernel` |
| `armbian_board` | `uefi-x86` |
| `armbian_branch` | `main` |
| `armbian_kernel_branch` | `current` |
| `armbian_release` | `noble` |
| `armbian_ui` | `minimal` |
| `armbian_compress` | `sha,img,xz` |
| `armbian_artifacts` | `build/output/images/` |
| `armbian_download_base_url` | `https://dl.armbian.com` |
| `armbian_download_repository` | `archive` |
| `armbian_index_url` | `https://github.armbian.com/armbian-images.json` |

See `action.yml` for the full list of inputs (signing, release tagging, prerelease behaviour, index enrichment, etc.).

## CI

Continuous integration is defined by the workflows under `.github/workflows/`. For a live overview of runs for this repository, see:

👉 **[actions.armbian.com — build](https://actions.armbian.com/?repo=build)**

## Resources

- **[Documentation](https://docs.armbian.com/Developer-Guide_Overview/)** — building, configuring and customizing
- **[Website](https://www.armbian.com)** — news, features, boards
- **[Blog](https://blog.armbian.com)** — development updates and technical articles
- **[Forums](https://forum.armbian.com)** — community support and discussions

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for how to report issues, prepare a development environment, generate patches and submit pull requests. Credits are listed in [CREDITS.md](CREDITS.md).

## Support

- **Community forums:** [forum.armbian.com](https://forum.armbian.com)
- **Real-time chat:** [Community IRC/Discord](https://docs.armbian.com/Community_IRC/)
- **Paid consultation:** [armbian.com/contact](https://www.armbian.com/contact)

## Contributors

Thank you to everyone who has contributed to Armbian.

<a href="https://github.com/armbian/build/graphs/contributors">
  <img alt="Contributors" src="https://contrib.rocks/image?repo=armbian/build" />
</a>

## Armbian Partners

Our [partnership program](https://forum.armbian.com/subscriptions) supports Armbian's development and community. Learn more about [our partners](https://armbian.com/partners).

## License

This project is licensed under the **GNU General Public License, version 2** — see [LICENSE](LICENSE).
