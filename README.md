<h3 align=center><a href="#armbian-build-engine"><img src=".github/armbian-logo.png" alt="Armbian logo" width="144"></a><br>
build engine</h3>

<p align=right>&nbsp;</p>

## Table of contents

- [What this project does?](#what-this-project-does)
- [What do you need to get started?](#what-do-you-need-to-get-started)
- [How to build an image or a kernel?](#how-to-build-an-image-or-a-kernel)
- [Compare with industry standards](#compare-with-industry-standards)
- [Where to download prebuilt images?](#where-to-download-prebuilt-images)
- [Additional information](#additional-information)
- [Build engine overview](#build-engine-overview)
- [Support](#support)
- [Contribute](#contribute)
- [Social](#social)
- [Credits](#credits)
- [Sponsors](#sponsors)

<p align=right>&nbsp;</p>

## What this project does?

- builds custom Debian based Linux system optimised for [supported single board computers](https://www.armbian.com/download/),
- covers root filesystem generation, kernel image compilation and bootloader compilation,
- maintains low-level control software for a [selection of hardware](https://www.armbian.com/download/),
- provides a consistent user experience by keeping system standards across different SBC platforms.

<p align=right>&nbsp;</p>

## What do you need to get started?
    
- x64 machine with at least 2GB of memory and ~30GB of disk space for the VM, container or native OS,
- Ubuntu Bionic 18.04 / Focal 20.04 x64 for native building or any [Docker](https://docs.armbian.com/Developer-Guide_Building-with-Docker/) capable x64 Linux for containerised,
- superuser rights (configured sudo or root access).

<p align=right><a href=#table-of-contents>⇧</a></p>

## How to build an image or a kernel?

```text
apt -y install git
git clone https://github.com/armbian/build
cd build
./compile.sh
```
<a href="#how-to-build-an-image-or-a-kernel"><img src=".github/README.gif" alt="Armbian logo" width="100%"></a>

<p align=right><a href=#table-of-contents>⇧</a></p>

## Compare with industry standards

Check similarity, advantages and disadvantages compared with leading industry standard build software.

Function | Armbian | Yocto | Buildroot |
|:--|:--|:--|:--|
| Target | general purpose | embedded | embedded / IOT | 
| U-boot and kernel | compiled from sources | compiled from sources | compiled from sources |
| Hardware support maintenance &nbsp;&nbsp; &nbsp; &nbsp;| complete | outside | outside | 
| Root file system | Debian or Ubuntu based| custom | custom |
| Package manager | APT | any | none |
| Configurability | limited | large | large |
| Initramfs support | yes | yes | yes |
| Getting started | quick | very slow | slow |
| Cross compilation | yes | yes | yes |

<p align=right><a href=#table-of-contents>⇧</a></p>

## Where to download prebuilt images?

https://www.armbian.com/download/

Armbian releases quarterly at the end of [February, May, August, November](https://github.com/armbian/documentation/blob/master/docs/Process_Release-Model.md). Contributers are welcome to propose changes to our default [images build list](https://github.com/armbian/build/blob/master/config/targets.conf).

<p align=right><a href=#table-of-contents>⇧</a></p>

## Additional information

- [Advanced build options](https://docs.armbian.com/Developer-Guide_Build-Options/),
- [User configurations](https://docs.armbian.com/Developer-Guide_User-Configurations/),
- Building with [Docker](https://docs.armbian.com/Developer-Guide_Building-with-Docker/) or [Vagrant](https://docs.armbian.com/Developer-Guide_Using-Vagrant/),
- [Developers forums](https://forum.armbian.com/forum/4-development/),
- [Central project search](https://www.armbian.com/search),
- [IRC channel logs](http://irc.armbian.com).

<p align=right><a href=#table-of-contents>⇧</a></p>

## Build engine overview

```text
├── cache                                    Work / cache directory
│   ├── rootfs                               Compressed vanilla Debian and Ubuntu rootfilesystem variants cache
│   ├── sources                              Kernel, u-boot and various drivers sources. Mainly C code
│   ├── toolchains                           External cross compilers from Linaro™ or ARM™
├── config                                   Packages repository configurations
│   ├── targets.conf                         Board build target configuration
│   ├── boards                               Board configurations
│   ├── bootenv                              Initial boot loaders environments per family
│   ├── bootscripts                          Initial Boot loaders scripts per family
│   ├── kernel                               Kernel build configurations per family
│   ├── sources                              Kernel and u-boot sources locations and scripts
│   ├── templates                            User configuration templates which populate userpatches
│   └── torrents                             External compiler and rootfs cache torrents
├── lib                                      Main build engine libraries
├── output                                   Build artifact
│   └── deb                                  Deb packages
│   └── images                               Bootable images - RAW or compressed
│   └── debug                                Patch and build logs
│   └── config                               Kernel configuration export location
│   └── patch                                Created patches location
├── packages                                 Support scripts, binary blobs, packages
│   ├── blobs                                Wallpapers, various configs, closed source bootloaders
│   ├── bsp                                  Scripts and configs overlay for rootfs
│   └── extras-buildpkgs                     Optional compilation and packaging engine
├── patch                                    Collection of patches
│   ├── atf                                  ARM trusted firmware
│   ├── kernel                               Linux kernel patches
|   |   └── family-branch                    Per kernel family and branch
│   ├── misc                                 Linux kernel packaging patches
│   └── u-boot                               Universal boot loader patches
|       ├── u-boot-board                     For specific board
|       └── u-boot-family                    For entire kernel family
└── userpatches                              User: configuration patching area
    ├── lib.config                           User: engine common config/override file
    ├── config-default.conf                  User: default user config file
    ├── customize-image.sh                   User: script will execute just before closing the image
    ├── atf                                  User: ARM trusted firmware
    ├── kernel                               User: Linux kernel per kernel family
    ├── misc                                 User: various
    └── u-boot                               User: universal boot loader patches
```

<p align=right><a href=#table-of-contents>⇧</a></p>

## Support

- Have you found a bug in the **build engine**? 

    Try to recreate the problem with a clean build script clone. If a problem does not go away, search for [existing and closed issues](https://github.com/armbian/build/issues) and if your problem or idea is not addressed yet, [open a new issue](https://github.com/armbian/build/issues/new). 
    
- Do you have troubles with **your board or generic Linux application**? 
    
    Consider using [general project search](https://www.armbian.com/search), best effort [community support](https://forum.armbian.com/) or hiring an expert. Hardware and generic support is extremly limited.

<p align=right><a href=#table-of-contents>⇧</a></p>

## Contribute

- Want to add a new feature? 

    Armbian build engine is an open source project and you are more then welcome [to contribute](https://www.armbian.com/get-involved) to it. Remember to [discuss new feature](https://forum.armbian.com/forum/4-development/) prior to development since we might already have plans or we have no plans to integrate your work.

- Want to help with anything? 

    Address [opened issues](https://github.com/armbian/build/issues), join regulars on [their already active missions](https://armbian.atlassian.net/browse/AR), start maintaining low level u-boot / kernel code, drivers or scripted applications like [armbian-config](https://github.com/armbian/config). Or help [managing our costs](https://www.armbian.com/donate)!

<p align=right><a href=#table-of-contents>⇧</a></p>

## Social

- Interact in [forums](https://forum.armbian.com),
- Chat with fellow users on IRC [#armbian](https://webchat.freenode.net/?channels=armbian) on [freenode](https://freenode.net/)
- Follow @armbian on [Twitter](https://twitter.com/armbian) or [LinkedIN](https://www.linkedin.com/company/armbian).

Get [updates on Armbian development̉](https://docs.armbian.com/Release_Changelog/) and chat with the project maintainers.

<p align=right><a href=#table-of-contents>⇧</a></p>

## Credits

- [Current and past contributors](https://github.com/armbian/build/graphs/contributors), our families and friends,
- [Support staff that keeps forums usable](https://forum.armbian.com/members/2-moderators/),
- [Individuals that help with their ideas](https://forum.armbian.com/), reports and [donations](https://www.armbian.com/donate).

<p align=right><a href=#table-of-contents>⇧</a></p>

## Sponsors

Most of the project is sponsored with a work done by volunteer collaborators, while some part of the project costs are being covered by the industry. We would not be able to get this far without their help. 

[Do you want to see yourself below?](https://www.armbian.com/#contact)

<img src="https://www.armbian.com/wp-content/uploads/2018/03/orangepi-logo-150x150.png" alt="Armbian logo" width="144" height="144"><img src="https://www.armbian.com/wp-content/uploads/2018/02/friendlyelec-logo-150x150.png" alt="Armbian logo" width="144" height="144">
<img src="https://www.armbian.com/wp-content/uploads/2018/03/kspace-150x150.png" width="144" height="144">
<img src="https://www.armbian.com/wp-content/uploads/2018/02/olimex-logo-150x150.png" width="144" height="144">
<img src="https://www.armbian.com/wp-content/uploads/2018/03/helios4_logo-150x150.png" width="144" height="144">

<p align=right><a href=#table-of-contents>⇧</a></p>

