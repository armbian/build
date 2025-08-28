<h2 align="center">
  <a href=#><img src="https://raw.githubusercontent.com/armbian/.github/master/profile/logosmall.png" alt="Armbian logo"></a>
  <br><br>
</h2>

### Purpose of This Repository

The **Armbian Linux Build Framework** creates minimal, efficient, and fully [customizable operating system images](https://docs.armbian.com/#key-features) based on **Debian** or **Ubuntu**. It is designed specifically for **low-resource single board computers (SBCs)** and other embedded devices.

This toolchain compiles a custom **Linux kernel**, **bootloader**, and **root filesystem**, providing fine-grained control over:

- Kernel versions and configuration
- Bootloader selection and customization
- Filesystem layout and compression
- Additional firmware, overlays, and device trees
- System optimizations for performance and size

The framework supports **native**, **cross**, and **containerized** builds for multiple architectures (`x86_64`, `aarch64`, `armhf`, `riscv64`), and is suitable for development, testing, production deployment, or automation pipelines.

It ensures **consistency across devices** while remaining modular and extensible through a variety of configuration files, templates, and user patches.

### Quick Start

```bash
git clone https://github.com/armbian/build
cd build
./compile.sh
```

### Resources

[Documentation](https://docs.armbian.com/Developer-Guide_Overview/) • [Website](https://www.armbian.com) • [Blog](https://blog.armbian.com) • [Community Forums](https://forum.armbian.com)



<a href="#how-to-build-an-image-or-a-kernel"><img src=".github/README.gif" alt="Armbian logo" width="100%"></a>

### Build Host Requirements

- **Supported Architectures:** `x86_64`, `aarch64`, `riscv64`
- **System:** VM, container, or bare-metal with:
  - **≥ 8GB RAM** (less with `KERNEL_BTF=no`)
  - **~50GB disk space**
- **Operating System:**
  - Armbian / Ubuntu 24.04 (Noble) for native builds
  - Any Docker-capable Linux for containerized setup
- **Windows:** Windows 10/11 with WSL2 running Armbian / Ubuntu 24.04
- **Access:** Superuser rights (`sudo` or `root`)
- **Important:** Keep your system up-to-date — outdated tools (e.g., Docker) can cause issues.

### Download

Prebuilt Armbian OS Images: <https://www.armbian.com/download>

### Contribute

Learn how to report issues, suggest improvements, or submit code: [CONTRIBUTING.md](CONTRIBUTING.md)

### Support

Armbian offers multiple support channels, depending on your needs:

- **Community Forums**  
  Get help from fellow users and contributors on a wide range of topics — from troubleshooting to development.  
  👉 [forum.armbian.com](https://forum.armbian.com)

- **Discord / IRC/ Matrix Chat**  
  Join real-time discussions with developers and community members for faster feedback and collaboration.  
  👉 [Community Chat](https://docs.armbian.com/Community_IRC/)

- **Paid Consultation**  
  For advanced needs, commercial projects, or guaranteed response times, paid support is available directly from Armbian maintainers.  
  👉 [Contact us](https://www.armbian.com/contact) to discuss consulting options.

### Contributors

Thank you to all the people who already contributed to Armbian!

<a href="https://github.com/armbian/build/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=armbian/build" />
</a>

## Armbian Partners

Armbian's [partnership program](https://forum.armbian.com/subscriptions) helps to support Armbian and the Armbian community! Please take a moment to familiarize yourself with [our Partners](https://armbian.com/partners).
