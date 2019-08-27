Package: libgl1-mesa-dev
Source: mesa
Version: 99.99
Architecture: all
Maintainer: Debian X Strike Force <debian-x@lists.debian.org>
Installed-Size: 68
Depends: mesa-common-dev (= 99.99), libdrm-dev (>= 2.4.99), libx11-dev, libx11-xcb-dev, libxcb-dri3-dev, libxcb-present-dev, libxcb-sync-dev, libxshmfence-dev, libxcb-dri2-0-dev, libxcb-glx0-dev, libxdamage-dev, libxext-dev, libxfixes-dev, libxxf86vm-dev, x11proto-dev
Conflicts: libgl-dev
Replaces: libgl-dev
Provides: libgl-dev
Section: libdevel
Priority: optional
Multi-Arch: allowed
Homepage: https://mesa3d.org/
Description: free implementation of the OpenGL API -- GLX development files
 This version of Mesa provides GLX and DRI capabilities: it is capable of
 both direct and indirect rendering.  For direct rendering, it can use DRI
 modules from the libgl1-mesa-dri package to accelerate drawing.
 .
 This package includes headers and static libraries for compiling
 programs with Mesa.
 .
 For a complete description of Mesa, please look at the libglx-mesa0
 package.
 Dummy package for libgl1-mesa-dev
