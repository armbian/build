Package: libglx-mesa0
Source: mesa
Version: 99.99
Architecture: all
Maintainer: Debian X Strike Force <debian-x@lists.debian.org>
Installed-Size: 581
Depends: libc6 (>= 2.28), libdrm2 (>= 2.4.99), libexpat1 (>= 2.0.1), libglapi-mesa (= 99.99), libx11-6 (>= 2:1.4.99.1), libx11-xcb1, libxcb-dri2-0 (>= 1.8), libxcb-dri3-0 (>= 1.13), libxcb-glx0 (>= 1.8), libxcb-present0, libxcb-sync1, libxcb1 (>= 1.9.2), libxdamage1 (>= 1:1.1), libxext6, libxfixes3, libxshmfence1, libxxf86vm1, libgl1-mesa-dri
Breaks: glx-diversions (<< 0.8.4~), libopengl-perl (<< 0.6704+dfsg-2)
Provides: libglx-vendor
Section: libs
Priority: optional
Multi-Arch: allowed
Homepage: https://mesa3d.org/
Description: free implementation of the OpenGL API -- GLX vendor library
 Mesa is a 3-D graphics library with an API which is very similar to
 that of OpenGL.  To the extent that Mesa utilizes the OpenGL command
 syntax or state machine, it is being used with authorization from
 Silicon Graphics, Inc.  However, the authors make no claim that Mesa
 is in any way a compatible replacement for OpenGL or associated with
 Silicon Graphics, Inc.
 .
 This version of Mesa provides GLX and DRI capabilities: it is capable of
 both direct and indirect rendering.  For direct rendering, it can use DRI
 modules from the libgl1-mesa-dri package to accelerate drawing.
 .
 This package does not include the modules themselves: these can be found
 in the libgl1-mesa-dri package.
 Dummy package for libglx-mesa0
