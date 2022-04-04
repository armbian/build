<p align="center">
  <a href="#build-framework">
  <img src=".github/armbian-logo.png" alt="Armbian logo" width="144">
  </a><br>
  <strong>armbian build framework</strong><br>
</p>

[![GitHub last commit (branch)](https://img.shields.io/github/last-commit/armbian/build/master)](https://github.com/armbian/build/commits)
[![GitHub Workflow Status](https://img.shields.io/github/workflow/status/armbian/build/Build?label=build%20train)](https://github.com/armbian/build/actions/workflows/build-train.yml)
[![Twitter Follow](https://img.shields.io/twitter/follow/armbian?style=flat-square)](https://twitter.com/intent/follow?screen_name=armbian)
[![Join the Discord server](https://img.shields.io/discord/854735915313659944.svg?color=7289da&label=Discord%20server&logo=discord)](https://discord.gg/gNJ2fPZKvc)
[![Become a patron](https://img.shields.io/liberapay/patrons/armbian.svg?logo=liberapay)](https://liberapay.com/armbian)

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

- builds custom Linux optimized for [single board computers](https://www.armbian.com/download/),
- covers filesystem generation, low-level control software, kernel image compilation and bootloader compilation,
- provides a consistent user experience by keeping system standards across different platforms.

## Getting started

- x64 / aarch64 machine with at least 2GB of memory and ~35GB of disk space for a VM, container or native OS,
- Ubuntu Hirsute 21.04 x64 / aarch64 for native building or any [Docker](https://docs.armbian.com/Developer-Guide_Building-with-Docker/) capable x64 / aarch64 Linux for containerised,
- superuser rights (configured sudo or root access).

### Build script overview

```text
apt-get -y install git
git clone https://github.com/armbian/build
cd build
./compile.sh
```

<a href="#how-to-build-an-image-or-a-kernel"><img src=".github/README.gif" alt="Armbian logo" width="100%"></a>

- will prepare the workspace by installing necessary dependencies and sources
- it guides through the process until either a kernel package set or a ready-to-use image for a SDcard is created

#### Build parameter examples

Show work in progress areas in interactive mode:

```text
./compile.sh EXPERT="yes"
```

Run build framework inside Docker container:

```text
./compile.sh docker
```

Build minimal CLI Armbian Focal image for Orangepi Zero. Use modern kernel and write image to the SD card:

```text
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

[Build parameters, advanced build options, user defined configuration, build with Docker?](#additional-information)

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

## Download prebuilt images

<https://www.armbian.com/download/>

Armbian [releases](https://docs.armbian.com/Release_Changelog/) quarterly at the end of [February, May, August, November](https://github.com/armbian/documentation/blob/master/docs/Process_Release-Model.md). You are welcome to propose changes to our default [images build list](https://github.com/armbian/build/blob/master/config/targets.conf).

## Project structure

```text
├── cache                                Work / cache directory
│   ├── rootfs                           Compressed vanilla Debian and Ubuntu rootfilesystem cache
│   ├── sources                          Kernel, u-boot and various drivers sources. Mainly C code
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
└── userpatches                          User: configuration patching area
    ├── lib.config                       User: framework common config/override file
    ├── config-default.conf              User: default user config file
    ├── customize-image.sh               User: script will execute just before closing the image
    ├── atf                              User: ARM trusted firmware
    ├── kernel                           User: Linux kernel per kernel family
    ├── misc                             User: various
    └── u-boot                           User: universal boot loader patches
```

## Contribution

- **You don't need to be a programmer to help!**

- The easiest way to help is by "Starring" our repository - it helps more people find our code.

- You also can maintain and develop [docs](https://github.com/armbian/documentation), [CI](https://github.com/armbian/ci-testing-tools), [autotests](https://github.com/armbian/autotests), [seed torrents](https://forum.armbian.com/topic/4198-seed-our-torrents/), help on [forum moderating](https://forum.armbian.com/topic/12631-help-on-forum-moderating/), [project administration](https://forum.armbian.com/forum/39-armbian-project-administration/), [costs](https://www.armbian.com/donate).

Please make sure to read the [Contributing Guide](.github/CONTRIBUTING.md) before you write any code.

## Support

- Community support

    Armbian is free software and provides **best effort help** through [community forums](https://forum.armbian.com/). If you can't find answer there and/or with help of [general project search engine](https://www.armbian.com/search) and [documentation](https://docs.armbian.com), consider [hiring an expert](https://www.debian.org/consultants/).

- Personal support

    Personal support limited to active project supporters and sponsors. The shortest way to become one and receive our attention is a four figure [donation to our non-profit project](https://www.armbian.com/donate).

## Contact

- [Forums](https://forum.armbian.com) for Participate in Armbian
- IRC: `#armbian` on Libera.chat
- Follow [@armbian](https://twitter.com/armbian) on twitter or [LinkedIn](https://www.linkedin.com/company/armbian).
- Bugs: [issues](https://github.com/armbian/build/issues) / [JIRA](https://armbian.atlassian.net/jira/software/c/projects/AR/issues)

## Contributors

Thank you to all the people who already contributed armbian!

<a href="https://github.com/armbian/build/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=armbian/build" />
</a>

### Also

- [Current and past contributors](https://github.com/armbian/build/graphs/contributors), our families and friends,
- [Support staff](https://forum.armbian.com/members/2-moderators/) that keeps forums usable.
- [Individuals](https://forum.armbian.com/)that help with their ideas, reports and [donations](https://www.armbian.com/donate).

## Sponsors

Most of the project is sponsored with a work done by volunteer collaborators, while some part of the project costs are being covered by the industry. We would not be able to get this far without their help.

[Do you want to see yourself below?](https://www.armbian.com/#contact)

<a href="https://www.armbian.com/download/?tx_maker=xunlong" target="_blank"><img border=0 src="https://www.armbian.com/wp-content/uploads/2018/03/orangepi-logo-150x150.png" width="122" height="122"></a><a href="https://www.armbian.com/download/?tx_maker=friendlyelec" target="_blank"><img border=0 src="https://www.armbian.com/wp-content/uploads/2018/02/friendlyelec-logo-150x150.png" width="122" height="122"></a><a href="https://k-space.ee" target="_blank"><img border=0 src="https://www.armbian.com/wp-content/uploads/2018/03/kspace-150x150.png" width="122" height="122"></a><a href="https://www.innoscale.net" target="_blank"><img border=0 src="https://www.armbian.com/wp-content/uploads/2020/07/innoscale-2-150x150.png" width="122" height="122"></a><a href="https://www.armbian.com/download/?tx_maker=olimex" target="_blank"><img border=0 src="https://www.armbian.com/wp-content/uploads/2018/02/olimex-logo-150x150.png" width="122" height="122"></a><a href="https://www.armbian.com/download/?tx_maker=kobol" target="_blank"><img border=0 src="https://www.armbian.com/wp-content/uploads/2020/06/Kobol_logo-150x150.png" width="122" height="122"></a><a href="https://github.com/WorksOnArm/cluster/issues/223" target="_blank"><img border=0 src="https://www.armbian.com/wp-content/uploads/2020/11/work-on-arm-150x150.png" width="122" height="122"></a><a href="https://fosshost.org/" target="_blank"><img border=0 src="https://www.armbian.com/wp-content/uploads/2020/11/foss-host-150x150.png" width="122" height="122"></a><a href="https://nlnet.nl/" target="_blank"><img border=0 src="https://www.armbian.com/wp-content/uploads/2022/01/nlnet-fundation-150x150.png" width="122" height="122"></a><a href="#"><img border=0 src="https://www.armbian.com/wp-content/uploads/2021/06/lanecloud-150x150.png" width="122" height="122"></a><a href="https://www.khadas.com/" target="_blank"><img border=0 src="https://www.armbian.com/wp-content/uploads/2021/05/khadas-150x150.png" width="122" height="122"></a>

## License

This software is published under the GPL-2.0 License license.
