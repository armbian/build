<h2 align="center">
  <a href=#><img src="https://raw.githubusercontent.com/armbian/.github/master/profile/logosmall.png" alt="Armbian logo"></a>
  <br><br>
</h2>

# Armbian Linux Build Framework

## Purpose of This Repository

The **Armbian Linux build framework** produces customizable OS images based on **Debian** or **Ubuntu** for **single-board computers (SBCs)** and embedded devices. It assembles kernel, bootloader and root filesystem for a wide range of boards and SoC families, with native, cross and containerized builds.

> **Looking for prebuilt images?** Use [Armbian Imager](https://github.com/armbian/imager/releases) — the easiest way to download and flash Armbian to your SD card or USB drive. Available for Linux, macOS and Windows.

## Quick Start

```bash
git clone https://github.com/armbian/build
cd build
./compile.sh
```

<a href="#armbian-linux-build-framework"><img src=".github/README.gif" alt="Build demonstration" width="100%"></a>

Interactive menus guide you through target, board, kernel branch and userspace release selection. Non-interactive invocations pass key=value pairs on the command line, e.g.:

```bash
./compile.sh build BOARD=uefi-x86 BRANCH=current RELEASE=trixie \
             BUILD_MINIMAL=yes BUILD_DESKTOP=no KERNEL_CONFIGURE=no
```

See the [Armbian documentation](https://docs.armbian.com/Developer-Guide_Overview/) for the full option reference.

## Build Host Requirements

### Hardware
- **RAM:** ≥ 8 GB (less with `KERNEL_BTF=no`)
- **Disk:** ~50 GB free space
- **Architecture:** x86_64, aarch64, or riscv64

### Operating System
- **Native builds:** Armbian/Debian 13 (Trixie)
- **Containerized:** any Docker-capable Linux
- **Windows:** WSL2 with Armbian/Debian 13 (Trixie)

### Software
- Superuser privileges (`sudo` or root)
- Up-to-date system (outdated Docker or other tools can cause failures)

## What's Built With

The framework itself is written primarily in:

- **Bash** — `compile.sh`, everything under `lib/functions/` and `lib/tools/*.sh`, patch/build helpers, and most extension entry points under `extensions/`
- **Python** — build tooling under `lib/tools/` (e.g. `patching.py`, `aggregation.py`, `lib/tools/info/`)
- **YAML** — GitHub Actions workflows in `.github/workflows/`, `.github/labels.yml`, `.github/dependabot.yml`, `.coderabbit.yaml`, `.pre-commit-config.yaml`, and GitHub issue templates
- **Shell-style key=value configuration** — board/family/distribution definitions under `config/`
- **Patches and Device Tree overlays** — thousands of `.patch` files plus `.dts`/`.dtsi`/`.dtso` sources carried under `patch/kernel/*/overlay/` and family patch dirs

## Repository Layout

| Path | Contents |
|---|---|
| `compile.sh` | Entry point; loads `lib/single.sh` and dispatches to the CLI |
| `action.yml` | Reusable **GitHub composite Action** (`Rebuild Armbian`) for building images or kernels in CI |
| `lib/` | Core build logic: functions, tools (shell and Python), and the single-entry loader |
| `config/` | Board, family, distribution, kernel/u-boot source and CLI package definitions |
| `config/boards/` | One file per supported board (see board extensions below) |
| `config/distributions/` | Supported Debian/Ubuntu release definitions and their status |
| `config/cli/` | Per-release CLI package lists |
| `extensions/` | Opt-in build extensions enabled via `ENABLE_EXTENSIONS=` |
| `packages/` | In-tree package sources and bsp payloads (`blobs/`, `bsp/`, `plymouth-theme-armbian/`, …) |
| `patch/` | Kernel, u-boot, ATF and misc patches, organized per branch/family |
| `tools/` | Developer helpers (e.g. `mk_format_patch`, `unifying_configs`) |
| `.github/` | CODEOWNERS, issue/PR templates, labels, workflows and helper scripts |

## Board Configuration

Each file in `config/boards/` describes one board. The filename extension signals its support status:

| Extension | Meaning |
|---|---|
| `.conf` | Standard board configuration |
| `.csc` | Community-maintained / unstable |
| `.wip` | Work in progress |
| `.eos` | End of life |
| `.tvb` | TV box, community supported (no Armbian maintainer) |

See [`config/boards/README.md`](config/boards/README.md) for the full list of per-board build options (`BOARD_NAME`, `BOARDFAMILY`, `BOOTCONFIG`, `KERNEL_TARGET`, overlays, package lists, etc.), and [`config/distributions/README.md`](config/distributions/README.md) for distribution status.

## Using the GitHub Action

This repository also ships a composite action (`action.yml`) that other repositories can call to rebuild Armbian images or kernels:

```yaml
- uses: armbian/build@main
  with:
    armbian_token: ${{ secrets.GITHUB_TOKEN }}
    armbian_target: image            # or "kernel"
    armbian_board: uefi-x86
    armbian_branch: main
    armbian_kernel_branch: current
    armbian_release: noble
    armbian_ui: minimal
    armbian_compress: sha,img,xz
```

Key inputs (see `action.yml` for the complete list and defaults):

| Input | Default | Purpose |
|---|---|---|
| `armbian_token` | *(required)* | GitHub installation access token |
| `armbian_target` | `kernel` | Build image or kernel |
| `armbian_board` | `uefi-x86` | Target hardware platform |
| `armbian_branch` | `main` | Branch of the build framework |
| `armbian_kernel_branch` | `current` | `legacy` / `current` / `edge` |
| `armbian_release` | `noble` | Userspace release |
| `armbian_ui` | `minimal` | `minimal`, `server`, or a desktop environment |
| `armbian_compress` | `sha,img,xz` | Output compression / checksum method |
| `armbian_extensions` | *(empty)* | Space-separated extension list |
| `armbian_pgp_key` / `armbian_pgp_password` | *(empty)* | Optional image signing |

## Continuous Integration

Workflow runs and build status for this repository are tracked on the Armbian CI dashboard:

👉 **[actions.armbian.com — build](https://actions.armbian.com/?repo=build)**

## Contributing

Contributions are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidance on reporting issues, preparing patches, labeling conventions and submitting pull requests. Development procedures are documented at [docs.armbian.com](https://docs.armbian.com/Development-Code_Review_Procedures_and_Guidelines/).

## Resources

- **[Documentation](https://docs.armbian.com/Developer-Guide_Overview/)** — guides for building, configuring and customizing
- **[Website](https://www.armbian.com)** — news, features and board information
- **[Blog](https://blog.armbian.com)** — development updates and technical articles
- **[Forums](https://forum.armbian.com)** — community support and discussions

## Support

### Community Forums
Get help from users and contributors on troubleshooting, configuration and development.
👉 [forum.armbian.com](https://forum.armbian.com)

### Real-time Chat
Join discussions with developers and community members on IRC or Discord.
👉 [Community Chat](https://docs.armbian.com/Community_IRC/)

### Paid Consultation
For commercial projects, guaranteed response times, or advanced needs, paid support is available from Armbian maintainers.
👉 [Contact us](https://www.armbian.com/contact)

## License

Armbian build framework is released under the [GNU General Public License v2.0](LICENSE).

## Contributors

Thank you to everyone who has contributed to Armbian!

<a href="https://github.com/armbian/build/graphs/contributors">
  <img alt="Contributors" src="https://contrib.rocks/image?repo=armbian/build" />
</a>

## Armbian Partners

Our [partnership program](https://forum.armbian.com/subscriptions) supports Armbian's development and community. Learn more about [our Partners](https://armbian.com/partners).
