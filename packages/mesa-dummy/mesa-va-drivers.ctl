Package: mesa-va-drivers
Source: mesa
Version: 99.99
Architecture: all
Maintainer: Debian X Strike Force <debian-x@lists.debian.org>
Installed-Size: 20290
Depends: libc6 (>= 2.28), libdrm2 (>= 2.4.99), libelf1 (>= 0.142), libexpat1 (>= 2.0.1), libgcc1 (>= 1:3.4), libllvm7 (>= 1:7~svn298832-1~), libstdc++6 (>= 5.2), libx11-xcb1, libxcb-dri2-0 (>= 1.8), libxcb-dri3-0, libxcb-present0, libxcb-sync1, libxcb-xfixes0, libxcb1 (>= 1.9.2), libxshmfence1, zlib1g (>= 1:1.1.4), libva-driver-abi-1.4
Enhances: libva2
Breaks: vdpau-va-driver (<< 0.7.4-5)
Replaces: vdpau-va-driver (<< 0.7.4-5)
Provides: va-driver
Section: libs
Priority: optional
Multi-Arch: allowed
Homepage: https://mesa3d.org/
Description: Mesa VA-API video acceleration drivers
 These libraries provide the Video Acceleration API (VA-API) for Unix.
 They provide accelerated video playback (incl. H.264) and video
 post-processing for the supported graphics cards.
 .
 This package enables support for VA-API for some gallium drivers.
 Dummy package for mesa-va-drivers
