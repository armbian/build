Package: libgl1-mesa-dri
Source: mesa
Version: 99.99
Architecture: all
Maintainer: Debian X Strike Force <debian-x@lists.debian.org>
Installed-Size: 194517
Depends: libc6 (>= 2.28), libdrm2 (>= 2.4.99), libelf1 (>= 0.142), libexpat1 (>= 2.0.1), libgcc1 (>= 1:3.4), libglapi-mesa, libllvm7 (>= 1:7~svn298832-1~), libsensors5 (>= 1:3.5.0), libstdc++6 (>= 5.2), zlib1g (>= 1:1.1.4)
Section: libs
Priority: optional
Multi-Arch: allowed
Homepage: https://mesa3d.org/
Description: free implementation of the OpenGL API -- DRI modules
 This version of Mesa provides GLX and DRI capabilities: it is capable of
 both direct and indirect rendering.  For direct rendering, it can use DRI
 modules from the libgl1-mesa-dri package to accelerate drawing.
 .
 This package does not include the OpenGL library itself, only the DRI
 modules for accelerating direct rendering.
 .
 For a complete description of Mesa, please look at the
 libglx-mesa0 package.
 Dummy package for libgl1-mesa-dri
