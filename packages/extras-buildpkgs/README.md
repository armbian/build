# Requirements

* Xenial build host

* Extra 5GB of disk space

# Limitations

* Packages are built only for Jessie, Xenial and Stretch targets, installing on older distributions may be done manually if dependencies can be satisfied

# TODO

### Process

* Switch from qemu & distcc to multiarch cross-compiling if possible

### Package-specific:

* libvdpau-sunxi: select branch (master or dev)

## Notes

libcedrus compiled without USE_UMP=1 requires access to /dev/ion

libcedrus compiled with USE_UMP=1 caused segfault last time I tested video playback with mpv

libmali-sunxi-r3p0 contains *.so symlinks (instead of libmali-sunxi-dev) to help searching libraries by SONAME for libMali.so

libmali-sunxi-r3p0 is packaged differently for [Debian](https://www.debian.org/doc/debian-policy/ap-pkg-diversions.html) and [Ubuntu](https://wiki.ubuntu.com/X/EGLDriverPackagingHOWTO)

libglshim1 is installed to private directory (`/usr/lib/arm-linux-gnueabihf/glshim`) and can be activated by using LD_LIBRARY_PATH
