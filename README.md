# Armbian

Ubuntu/Debian images for ARM based single-board computers
http://www.armbian.com

## How to build my own image or kernel?

**Preparation**

- x86/x64 machine running any OS; 4G ram, SSD, quad core (recommended),
- [VirtualBox](https://www.virtualbox.org/wiki/Downloads) or similar virtualization software **(highly recommended with a minimum of 20GB hard disk space for the virtual disk image)**,
- alternatively - [Docker](https://github.com/igorpecovnik/lib/pull/255#issuecomment-205045273), [systemd-nspawn](https://www.freedesktop.org/software/systemd/man/systemd-nspawn.html) or other containerization software,
- compilation environment is **highly recommended** to be [Ubuntu Trusty 14.04](http://archive.ubuntu.com/ubuntu/dists/trusty-updates/main/installer-amd64/current/images/netboot/mini.iso) or [Ubuntu Xenial 16.04](http://archive.ubuntu.com/ubuntu/dists/xenial-updates/main/installer-amd64/current/images/netboot/mini.iso) (other releases are **not officially supported**),
- installed basic system, OpenSSH and Samba (optional),
- superuser rights (configured `sudo` or root shell).

**Execution**
	
	apt-get -y install git
	git clone https://github.com/igorpecovnik/lib --depth 1
	cp lib/compile.sh .
	./compile.sh
	
This will download all necessary sources, execute compilation and/or build a bootable image. Most of things will be cached so next run will be extremely faster!

## How to edit kernel configuration?

Edit `compile.sh` and set

	KERNEL_CONFIGURE="yes"

to display kernel configuration menu prior to compilation

More info:

- [Documentation](http://www.armbian.com/using-armbian-tools/)
- [Prebuilt images](http://www.armbian.com/download/)
- [Support forums](http://forum.armbian.com/ "Armbian support forum")
- [Project at Github](https://github.com/igorpecovnik/lib)
