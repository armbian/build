## How to build my own image? ##

**Prerequisition:**

- x86 machine running any OS, 4G ram, SSD, quad core (recommended)
- [virtual box](https://www.virtualbox.org/wiki/Downloads) or similar virtualization software.
- download and install [Ubuntu 14.04](http://archive.ubuntu.com/ubuntu/dists/trusty-updates/main/installer-amd64/current/images/netboot/mini.iso) (recommended). Ubuntu 15.04 and Debian Jessie might work well too.
- install basic server, OpenSSH and Samba (optional)
- SSH to VM [as root](http://askubuntu.com/questions/469143/how-to-enable-ssh-root-access-on-ubuntu-14-04) and execute:


		apt-get -y install git
		git clone https://github.com/igorpecovnik/lib
		cp lib/compile.sh .
		chmod +x compile.sh
		./compile.sh


This will download all necessary sources, execute compilation and build an bootable image.

Most of things will be cached so next run will be extremly faster!

## How to build my own kernel? ##

**Prerequisition are the same as building an image!**

Edit *compile.sh* prior to running and alter switch:

	KERNEL_ONLY="yes"

In directory (output/debs) you will find deb packed kernel, together with headers, firmware and u-boot.

If you are doing changes to kernel source, disable GIT lock with:

	FORCE_CHECKOUT="no"

If you want to invoke menu configuration:

	KERNEL_CONFIGURE="yes"

More info:

- [Documentation](http://www.armbian.com/documentation/)
- [Support forums](http://forum.armbian.com/ "Armbian support forum")
- [Project at Github](https://github.com/igorpecovnik/lib)