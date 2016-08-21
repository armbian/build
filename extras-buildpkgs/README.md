# Requirements

* Xenial build host

* apt-cacher-ng enabled

# Limitations

* Using QEMU emulation in chroot, so compilation may take a long time (~10 hours)

* Limited error checking, process is not aborted on single package building failure

* Packages are built only for Jessie and Xenial target, installing on older distributions may be done manually if dependencies can be satisfied

# TODO

### Process

* Switch from qemu to multiarch cross-compiling

### Package-specific:

* libvdpau-sunxi: select branch (master or dev)

* mpv: test and add configuration file for direct framebuffer output

## Notes

libcedrus compiled without USE_UMP=1 requires access to /dev/ion

libcedrus compiled with USE_UMP=1 caused segfault last time I tested video playback with mpv
