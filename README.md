## How to build my own image? ##

**Prerequisition:**

- x86 machine, 4G ram, SSD, quad core
- installed virtual box
- download [Ubuntu 14.04](http://archive.ubuntu.com/ubuntu/dists/trusty-updates/main/installer-amd64/current/images/netboot/mini.iso) (40Mb)
- install basic Ubuntu server, OpenSSH and Samba (optional)
- SSH to VM [as root](http://askubuntu.com/questions/469143/how-to-enable-ssh-root-access-on-ubuntu-14-04) and execute:

		apt-get -y install git
		git clone https://github.com/igorpecovnik/lib
		cp lib/compile.sh .
		chmod +x compile.sh
		./compile.sh

This will download all necessary sources, execute compilation and build an bootable image.

Most of things will be cached so next run will be extremly faster!

[![Paypal donate](https://www.paypalobjects.com/en_US/i/btn/btn_donate_SM.gif)](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=CUYH2KR36YB7W)

Thank you!

## Support ##

- [Building](https://github.com/igorpecovnik/lib/blob/next/documentation/geek-faq.md) and [Using FAQ](https://github.com/igorpecovnik/lib/blob/next/documentation/user-faq.md)
- [Forums](http://forum.armbian.com/ "Armbian support forum")
- [Allwinner SBC community](https://linux-sunxi.org/)
