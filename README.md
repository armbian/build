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

### You don't need to be a programmer to help! 
- The easiest way to help is by "Starring" our repository - it helps more people find our code.
- [Check out our list of volunteer positions](https://forum.armbian.com/staffapplications/) and choose what you want to do ❤️
- [Seed torrents](https://forum.armbian.com/topic/4198-seed-our-torrents/)
- Help with [forum moderating](https://forum.armbian.com/topic/12631-help-on-forum-moderating/)
- [Project administration](https://forum.armbian.com/forum/39-armbian-project-administration/)
- [Donate](https://www.armbian.com/donate).

### Want to become a maintainer?

Please review the [Board Maintainers Procedures and Guidelines](https://docs.armbian.com/Board_Maintainers_Procedures_and_Guidelines/) and if you can meet the requirements as well as find a board on the [Board Maintainers](https://docs.armbian.com/Release_Board-Maintainers/) list which has less than 2 maintainers, then please apply using the linked form.

### Want to become a developer?

If you want to help with development, you should first review the [Development Code Review Procedures and Guidelines](https://docs.armbian.com/Development-Code_Review_Procedures_and_Guidelines/) and then you can review the pre-made Jira dashboards and additional resources provided below to find open tasks and how you can assist:

- [pull requests that needs a review](https://github.com/armbian/build/pulls?q=is%3Apr+is%3Aopen+review%3Arequired)
- dashboard for [junior](https://armbian.atlassian.net/jira/dashboards/10000) and [seniors](https://armbian.atlassian.net/jira/dashboards/10103) developers
- [documentation](https://docs.armbian.com/)
- [continuous integration](https://docs.armbian.com/Process_CI/)

## Support

Support is provided in one of two ways:
- For commercial or prioritized assistance:
  - book a an hour of [professional consultation](https://calendly.com/armbian/consultation),
  - consider becoming a project partner. Reach us out at https://armbian.com/contact,
- Alternatively free support is provided via [general project search engine](https://www.armbian.com/search), [documentation](https://docs.armbian.com), [community forums](https://forum.armbian.com/) or [IRC/Discord](https://docs.armbian.com/Community_IRC/). Keep in mind this is mostly provided by our awesome community members in a **best effort** manner and therefore there are no guaranteed solutions.

## Contact

- [Forums](https://forum.armbian.com) for Participate in Armbian
- IRC: `#armbian` on Libera.chat
- Discord: [http://discord.armbian.com](http://discord.armbian.com)
- Follow [@armbian](https://twitter.com/armbian) on Twitter or [LinkedIn](https://www.linkedin.com/company/armbian).
- Bugs: [issues](https://github.com/armbian/build/issues) / [JIRA](https://armbian.atlassian.net/jira/dashboards/10000)
- Office hours: [Wednesday, 12 midday, 18 afternoon, CET](https://calendly.com/armbian/office-hours)

## Contributors

Thank you to all the people who already contributed Armbian!

<a href="https://github.com/armbian/build/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=armbian/build" />
</a>

### Also

- [Current and past contributors](https://github.com/armbian/build/graphs/contributors), our families and friends.
- [Support staff](https://forum.armbian.com/members/2-moderators/) that keeps forums usable.
- [Friends and individuals](https://armbian.com/authors) who support us with resources and their time.
- [The Armbian Community](https://forum.armbian.com/) that helps with their ideas, reports and [donations](https://www.armbian.com/donate).

## Armbian Partners

Armbian's partnership program helps to support Armbian and the Armbian community! Please take a moment to familiarize your self with our Partners:
- [Click here to visit our Partners page!](https://armbian.com/partners)
- [How can I become a Partner?](https://forum.armbian.com/subscriptions)

## License

This software is published under the GPL-2.0 License license.
