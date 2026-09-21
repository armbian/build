<h2 align="center">
  <a href=#><img src="https://raw.githubusercontent.com/armbian/.github/master/profile/logosmall.png" alt="Armbian logo"></a>
  <br><br>
</h2>

# Armbian Linux Build Framework

## Purpose of This Repository

The **Armbian Linux Build Framework** builds customizable Debian- and Ubuntu-based OS images (kernel, bootloader and root filesystem) for a large catalogue of single-board computers and embedded devices. It is the tooling used to produce the images distributed by the Armbian project.

> **Looking for prebuilt images?** Use [Armbian Imager](https://github.com/armbian/imager/releases) — the easiest way to download and flash Armbian to your SD card or USB drive. Available for Linux, macOS and Windows.

## Quick Start

```bash
git clone https://github.com/armbian/build
cd build
./compile.sh
```

<a href="#quick-start"><img src=".github/README.gif" alt="Build demonstration" width="100%"></a>

The `compile.sh` entrypoint is a Bash script that sources the framework in `lib/` and then dispatches to the requested command (build an image, build a kernel, generate patches, etc.). Configuration is driven by files under `config/` and per-board `*.conf` / `*.csc` / `*.wip` / `*.eos` / `*.tvb` files under `config/boards/`.

## Build Host Requirements

### Hardware
- **RAM:** ≥ 8 GB (less with `KERNEL_BTF=no`)
- **Disk:** ~50 GB free space
- **Architecture:** `x86_64`, `aarch64` or `riscv64`

### Operating system
- **Native builds:** Armbian / Debian 13 (Trixie)
- **Containerized:** any Docker-capable Linux
- **Windows:** WSL2 with Armbian / Debian 13 (Trixie)

### Software
- Superuser privileges (`sudo` or root)
- An up-to-date host (outdated Docker or other tooling can cause failures)

## Repository Layout

| Path | Contents |
|------|----------|
| `compile.sh` | Bash entrypoint invoked by users and CI |
| `lib/` | Build framework (Bash functions, tool wrappers, single-source entry `lib/single.sh`) |
| `config/` | Board, distribution, CLI, boot-env, kernel and source definitions |
| `config/boards/` | Per-board configuration files (see `config/boards/README.md`) |
| `config/bootenv/` | U-Boot boot-env fragments |
| `config/cli/` | CLI package lists (see `config/cli/README.md`) |
| `config/distributions/` | Supported Debian/Ubuntu releases and their status |
| `config/its/` | Image Tree Source (`.its`) files consumed by the device tree builder |
| `extensions/` | Optional build-time extensions |
| `packages/` | Armbian packaging (kernel scripts, `bsp`, `bsp-cli`, `bsp-desktop`, blobs, extras — see `packages/README.md`) |
| `patch/` | Kernel and U-Boot patch sets, per version/branch |
| `tools/` | Small helpers (`mk_format_patch`, `unifying_configs` — see `tools/README.md`) |
| `action.yml` | GitHub composite Action for building images/kernels |
| `VERSION` | Framework version |
| `.github/` | Issue/PR templates, labels, CODEOWNERS, workflows |

## Board Configuration

Boards live under `config/boards/`. The file extension indicates the support status of that board:

| Extension | Status |
|-----------|--------|
| `.conf` | Supported (has an active Armbian maintainer) |
| `.csc` | Community supported (no Armbian maintainer) |
| `.tvb` | TV box, community supported (no Armbian maintainer) |
| `.wip` | Work in progress |
| `.eos` | End of life |

See [`config/boards/README.md`](config/boards/README.md) for the full list of variables a board file can define (`BOARD_NAME`, `BOARDFAMILY`, `BOOTCONFIG`, `KERNEL_TARGET`, `SERIALCON`, `MODULES*`, `DEFAULT_OVERLAYS`, `CPUMIN` / `CPUMAX`, …).

Upstream distribution support is tracked in [`config/distributions/README.md`](config/distributions/README.md).

## GitHub Action

`action.yml` at the repository root exposes the build framework as a reusable GitHub composite Action. It checks out `armbian/os`, this repository and the caller's customisations, installs build requirements, and invokes `./compile.sh` with the chosen inputs. Selected inputs (see `action.yml` for the full list and defaults):

| Input | Default | Purpose |
|-------|---------|---------|
| `armbian_target` | `kernel` | What to build (e.g. `kernel`, `image`) |
| `armbian_board` | `uefi-x86` | Target board |
| `armbian_branch` | `main` | Framework branch to check out |
| `armbian_kernel_branch` | `current` | Kernel branch (`legacy` / `current` / `edge` / …) |
| `armbian_release` | `noble` | Userspace release |
| `armbian_ui` | `minimal` | `minimal`, `server` or a desktop environment |
| `armbian_compress` | `sha,img,xz` | Image compression / checksum outputs |
| `armbian_artifacts` | `build/output/images/` | Path uploaded as artifact |
| `armbian_pgp_key` / `armbian_pgp_password` | *(empty)* | Optional signing key |

## Continuous Integration

This repository ships a large collection of GitHub Actions workflows under `.github/workflows/` covering data synchronization, maintenance, linting, security scanning and artifact builds. A live overview of all runs for this repo is available at:

- **CI overview:** <https://actions.armbian.com/?repo=build>

## Contributing

We welcome contributions! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on reporting issues, working on issues, opening pull requests and communicating with the team. Contributor credits are listed in [CREDITS.md](CREDITS.md) and at <https://www.armbian.com/authors>.

## Resources

- **Documentation:** <https://docs.armbian.com/Developer-Guide_Overview/>
- **Website:** <https://www.armbian.com>
- **Blog:** <https://blog.armbian.com>
- **Forums:** <https://forum.armbian.com>

## Support

- **Community forums** — troubleshooting, configuration and development help: [forum.armbian.com](https://forum.armbian.com)
- **Real-time chat** — IRC and Discord (bridged): [Community Chat](https://docs.armbian.com/Community_IRC/)
- **Paid consultation** — commercial projects and guaranteed response times: [Contact us](https://www.armbian.com/contact)

## Contributors

Thank you to everyone who has contributed to Armbian!

<a href="https://github.com/armbian/build/graphs/contributors">
  <img alt="Contributors" src="https://contrib.rocks/image?repo=armbian/build" />
</a>

## Armbian Partners

Our [partnership program](https://forum.armbian.com/subscriptions) supports Armbian's development and community. Learn more about [our Partners](https://armbian.com/partners).

## License

This project is licensed under the GNU General Public License v2.0 — see [LICENSE](LICENSE).
