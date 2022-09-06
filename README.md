<p align="center">
  <a href="#build-framework">
  <img src=".github/armbian-logo.png" alt="Armbian logo" width="144">
  </a><br>
  <strong>Armbian Linux Build Framework</strong><br>
<br>
<a href=https://github.com/armbian/build/actions/workflows/build-train.yml><img alt="GitHub Workflow Status" src="https://img.shields.io/github/workflow/status/armbian/build/Build%20train?logo=githubactions&label=Kernel%20compile&logoColor=white&style=for-the-badge"></a>
<a href=https://github.com/armbian/build/actions/workflows/build-all-desktops.yml><img alt="GitHub Workflow Status" src="https://img.shields.io/github/workflow/status/armbian/build/Build%20All%20Desktops?logo=githubactions&logoColor=white&label=Images%20assembly&style=for-the-badge"></a>
<a href=https://github.com/armbian/build/actions/workflows/smoke-tests.yml><img alt="GitHub Workflow Status" src="https://img.shields.io/github/workflow/status/armbian/build/Smoke%20tests%20on%20DUTs?logo=speedtest&label=Smoke%20test&style=for-the-badge"></a>
 <br>

<br>
<a href=https://twitter.com/armbian><img alt="Twitter Follow" src="https://img.shields.io/twitter/follow/armbian?logo=twitter&style=flat-square"></a>
<a href=http://discord.armbian.com/><img alt="Discord" src="https://img.shields.io/discord/854735915313659944?label=Discord&logo=discord&style=flat-square"></a>
<a href=https://liberapay.com/armbian><img alt="Liberapay patrons" src="https://img.shields.io/liberapay/patrons/armbian?logo=liberapay&style=flat-square"></a>
</p>



## Table of contents

- [What this project does?](#what-this-project-does)
- [Getting started](#getting-started)
- [Compare with industry standards](#compare-with-industry-standards)
- [Download prebuilt images](#download-prebuilt-images)
- [Project structure](#project-structure)
- [Contribution](#contribution)
- [Support](#support)
- [Contact](#contact)
- [Contributors](#contributors)
- [Sponsors](#sponsors)
- [License](#license)

## What this project does?

- Builds custom kernel, image or a distribution optimized for low resource HW such as single board computers,
- Include filesystem generation, low-level control software, kernel image and bootloader compilation,
- Provides a consistent user experience by keeping system standards across different platforms.

## Getting started

### Basic requirements

- x64 or aarch64 machine with at least 2GB of memory and ~35GB of disk space for a virtual machine, container or bare metal installation,
- Ubuntu Jammy 22.04 x64 or aarch64 for native building or any [Docker](https://docs.armbian.com/Developer-Guide_Building-with-Docker/) capable x64 / aarch64 Linux for containerised,
- Superuser rights (configured sudo or root access).

### Simply start with the build script

```bash
apt-get -y install git
git clone https://github.com/armbian/build
cd build
./compile.sh
```

<a href="#how-to-build-an-image-or-a-kernel"><img src=".github/README.gif" alt="Armbian logo" width="100%"></a>

- Interactive graphical interface.
- The workspace will be prepared by installing the necessary dependencies and sources.
- It guides the entire process until a kernel package or ready-to-use image of the SD card is created.

### Build parameter examples

Show work in progress areas in interactive mode:

```bash
./compile.sh EXPERT="yes"
```

Run build framework inside Docker container:

```bash
./compile.sh docker
```

Build minimal CLI Armbian Focal image for Orangepi Zero. Use modern kernel and write image to the SD card:

```bash
./compile.sh \
BOARD=orangepizero \
BRANCH=current \
RELEASE=focal \
BUILD_MINIMAL=yes \
BUILD_DESKTOP=no \
KERNEL_ONLY=no \
KERNEL_CONFIGURE=no \
CARD_DEVICE="/dev/sda"
```

More information:

- [Building Armbian](https://docs.armbian.com/Developer-Guide_Build-Preparation/) — how to start, how to automate;
- [Build options](https://docs.armbian.com/Developer-Guide_Build-Options/) — all build options;
- [Building with Docker](https://docs.armbian.com/Developer-Guide_Building-with-Docker/) — how to build inside container;
- [User configuration](https://docs.armbian.com/Developer-Guide_User-Configurations/) — how to add packages, patches and override sources config;


## Download prebuilt images

- quarterly released **supported** builds —  <https://www.armbian.com/download>
- weekly released **unsupported** community builds —  <https://github.com/armbian/community>
- upon code change **unsupported** development builds —  <https://github.com/armbian/build/releases>

## Compare with industry standards

Check similarity, advantages and disadvantages compared with leading industry standard build software.

Function | Armbian | Yocto | Buildroot |
|:--|:--|:--|:--|
| Target | general purpose | embedded | embedded / IOT |
| U-boot and kernel | compiled from sources | compiled from sources | compiled from sources |
| Board support maintenance &nbsp; | complete | outside | outside |
| Root file system | Debian or Ubuntu based| custom | custom |
| Package manager | APT | any | none |
| Configurability | limited | large | large |
| Initramfs support | yes | yes | yes |
| Getting started | quick | very slow | slow |
| Cross compilation | yes | yes | yes |

## Project structure

```text
├── cache                                Work / cache directory
│   ├── rootfs                           Compressed userspace packages cache
│   ├── sources                          Kernel, u-boot and various drivers sources.
│   ├── toolchains                       External cross compilers from Linaro™ or ARM™
├── config                               Packages repository configurations
│   ├── targets.conf                     Board build target configuration
│   ├── boards                           Board configurations
│   ├── bootenv                          Initial boot loaders environments per family
│   ├── bootscripts                      Initial Boot loaders scripts per family
│   ├── cli                              CLI packages configurations per distribution
│   ├── desktop                          Desktop packages configurations per distribution
│   ├── distributions                    Distributions settings
│   ├── kernel                           Kernel build configurations per family
│   ├── sources                          Kernel and u-boot sources locations and scripts
│   ├── templates                        User configuration templates which populate userpatches
│   └── torrents                         External compiler and rootfs cache torrents
├── extensions                           extend build system with specific functionality
├── lib                                  Main build framework libraries
├── output                               Build artifact
│   └── deb                              Deb packages
│   └── images                           Bootable images - RAW or compressed
│   └── debug                            Patch and build logs
│   └── config                           Kernel configuration export location
│   └── patch                            Created patches location
├── packages                             Support scripts, binary blobs, packages
│   ├── blobs                            Wallpapers, various configs, closed source bootloaders
│   ├── bsp-cli                          Automatically added to armbian-bsp-cli package 
│   ├── bsp-desktop                      Automatically added to armbian-bsp-desktopo package
│   ├── bsp                              Scripts and configs overlay for rootfs
│   └── extras-buildpkgs                 Optional compilation and packaging engine
├── patch                                Collection of patches
│   ├── atf                              ARM trusted firmware
│   ├── kernel                           Linux kernel patches
|   |   └── family-branch                Per kernel family and branch
│   ├── misc                             Linux kernel packaging patches
│   └── u-boot                           Universal boot loader patches
|       ├── u-boot-board                 For specific board
|       └── u-boot-family                For entire kernel family
├── tools                                Tools for dealing with kernel patches and configs
└── userpatches                          User: configuration patching area
    ├── lib.config                       User: framework common config/override file
    ├── config-default.conf              User: default user config file
    ├── customize-image.sh               User: script will execute just before closing the image
    ├── atf                              User: ARM trusted firmware
    ├── kernel                           User: Linux kernel per kernel family
    ├── misc                             User: various
    └── u-boot                           User: universal boot loader patches
```

## 🙌 Contribution

#### You don't need to be a programmer to help! [Check out  our list](https://forum.armbian.com/staffapplications/) choose what you wanna do ❤️
- The easiest way to help is by "Starring" our repository - it helps more people find our code.
- [Seed torrents](https://forum.armbian.com/topic/4198-seed-our-torrents/)
- Help with [forum moderating](https://forum.armbian.com/topic/12631-help-on-forum-moderating/)
- [Project administration](https://forum.armbian.com/forum/39-armbian-project-administration/)
- [Donate](https://www.armbian.com/donate).

#### Want to become a maintainer? Please review the [Board Maintainers Procedures and Guidelines](https://docs.armbian.com/Board_Maintainers_Procedures_and_Guidelines/) and if can meet the requirements as well as find a board on the [Board Maintainers](https://docs.armbian.com/Release_Board-Maintainers/) list which has less than 2 maintainers, then please apply using the linked form.

#### If you want to help with development, you should first review the [Development Code Review Procedures and Guidelines](https://docs.armbian.com/Development-Code_Review_Procedures_and_Guidelines/) and then you can review the pre-made Jira dashboards and additional resources provided below to find open tasks and how you can assist:
- [Beginners Dashboard](https://armbian.atlassian.net/jira/dashboards/10000)
- [Developers Dashboard](https://armbian.atlassian.net/jira/dashboards/10103)
- [docs](https://github.com/armbian/documentation)
- [CI](https://github.com/armbian/ci-testing-tools)
- [autotests](https://github.com/armbian/autotests)

## Support

Armbian is free software and provides **best effort help** through [community forums](https://forum.armbian.com/). Make sure to use help of [general project search engine](https://www.armbian.com/search) and [documentation](https://docs.armbian.com) before opening new forum topic. In case you require attention, buy appropriate [subscription level](https://forum.armbian.com/subscriptions) before asking for dedicated attention to the issue you have https://www.armbian.com/contact.

## Contact

- [Forums](https://forum.armbian.com) for Participate in Armbian
- IRC: `#armbian` on Libera.chat
- Discord: [http://discord.armbian.com](http://discord.armbian.com)
- Follow [@armbian](https://twitter.com/armbian) on Twitter or [LinkedIn](https://www.linkedin.com/company/armbian).
- Bugs: [issues](https://github.com/armbian/build/issues) / [JIRA](https://armbian.atlassian.net/jira/dashboards/10000)

## Contributors

Thank you to all the people who already contributed Armbian!

<a href="https://github.com/armbian/build/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=armbian/build" />
</a>

### Also

- [Current and past contributors](https://github.com/armbian/build/graphs/contributors), our families and friends.
- [Support staff](https://forum.armbian.com/members/2-moderators/) that keeps forums usable.
- [Individuals](https://forum.armbian.com/) that help with their ideas, reports and [donations](https://www.armbian.com/donate).

## Sponsors

Most of the project is sponsored with a work done by volunteer collaborators, while some part of the project costs are being covered by the industry. We would not be able to get this far without their help.

[Would you like your name to appear below?](https://www.armbian.com/#contact)

<a href="https://www.armbian.com/download/?tx_maker=xunlong" target="_blank"><img border=0 src="https://www.armbian.com/wp-content/uploads/2018/03/orangepi-logo-150x150.png" width="122" height="122"></a><a href="https://www.armbian.com/download/?tx_maker=friendlyelec" target="_blank"><img border=0 src="https://www.armbian.com/wp-content/uploads/2018/02/friendlyelec-logo-150x150.png" width="122" height="122"></a><a href="https://k-space.ee" target="_blank"><img border=0 src="https://www.armbian.com/wp-content/uploads/2018/03/kspace-150x150.png" width="122" height="122"></a><a href="https://www.innoscale.net" target="_blank"><img border=0 src="https://www.armbian.com/wp-content/uploads/2020/07/innoscale-2-150x150.png" width="122" height="122"></a><a href="https://www.armbian.com/download/?tx_maker=olimex" target="_blank"><img border=0 src="https://www.armbian.com/wp-content/uploads/2018/02/olimex-logo-150x150.png" width="122" height="122"></a><a href="https://www.armbian.com/download/?tx_maker=kobol" target="_blank"><img border=0 src="https://www.armbian.com/wp-content/uploads/2020/06/Kobol_logo-150x150.png" width="122" height="122"></a><a href="https://github.com/WorksOnArm/cluster/issues/223" target="_blank"><img border=0 src="https://www.armbian.com/wp-content/uploads/2020/11/work-on-arm-150x150.png" width="122" height="122"></a><a href="https://fosshost.org/" target="_blank"><img border=0 src="https://www.armbian.com/wp-content/uploads/2020/11/foss-host-150x150.png" width="122" height="122"></a><a href="https://nlnet.nl/" target="_blank"><img border=0 src="https://www.armbian.com/wp-content/uploads/2022/01/nlnet-fundation-150x150.png" width="122" height="122"></a><a href="#"><img border=0 src="https://www.armbian.com/wp-content/uploads/2021/06/lanecloud-150x150.png" width="122" height="122"></a><a href="https://www.khadas.com/" target="_blank"><img border=0 src="https://www.armbian.com/wp-content/uploads/2021/05/khadas-150x150.png" width="122" height="122"></a>

## License

This software is published under the GPL-2.0 License license.
