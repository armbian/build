<h3 align="center">
  <a href=#><img src="https://raw.githubusercontent.com/armbian/.github/master/profile/logosmall.png" alt="Armbian logo"></a>
  <br><br>
</h3>

## Purpose of This Repository

This repository is a customized fork of [armbian/build](https://github.com/armbian/build) specifically for the Oneplus 8t (Oneplus Kebab) Android Phone.

This fork has required changes to get Wifi working on the Phone after installing Armbian. See [docs/fork_changes.md](./docs/fork_changes.md) for a run down of the diff.

See [docs/flashing_instrutions.md](./docs/flashing_instructions.md) for flashing instructions. 

### Merging Upstream

>> Could you merge this upstream?

Probably! If someone from Armbian is seeing this and wants to kick my ass into doing that, please reach out. I needed something working quickly for my needs so ended up in a fork.

## Quick Start

```bash
git clone https://github.com/andrewthetechie/armbian-oneplus-kebab
cd build
# Release=trixie is not booting, but Noble does. Desktop/GUI acceleration also not working well. 
./compile.sh build BOARD=oneplus-kebab BUILD_DESKTOP=no BUILD_MINIMAL=no KERNEL_CONFIGURE=no RELEASE=noble
```

Then follow [docs/flashing_instrutions.md](./docs/flashing_instructions.md) for flashing onto your phone.

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

## Resources

- **[Armbian Documentation](https://docs.armbian.com/Developer-Guide_Overview/)** — Comprehensive guides for building, configuring, and customizing
- **[Armbian Website](https://www.armbian.com)** — News, features, and board information
- **[Armbian Blog](https://blog.armbian.com)** — Development updates and technical articles
- **[Armbian Forums](https://forum.armbian.com)** — Community support and discussions

## Support

Don't bug the Armbian folks for support on this - its my own mess. 


## Contributors

Thank you to everyone who has contributed to Armbian! Seriously, without ya'll I couldn't have done these tiny changes to get this working for my specific needs.

<a href="https://github.com/armbian/build/graphs/contributors">
  <img alt="Contributors" src="https://contrib.rocks/image?repo=armbian/build" />
</a>
