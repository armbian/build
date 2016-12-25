# Armbian

Ubuntu/Debian images for ARM based single-board computers
http://www.armbian.com

## How to build my own image or kernel?

**Preparation**

- x86/x64 machine running any OS; 4G ram, SSD, quad core (recommended),
- [VirtualBox](https://www.virtualbox.org/wiki/Downloads) or similar virtualization software **(highly recommended with a minimum of 20GB hard disk space for the virtual disk image)**,
- alternatively - [Docker](https://github.com/igorpecovnik/lib/pull/255#issuecomment-205045273), [systemd-nspawn](https://www.freedesktop.org/software/systemd/man/systemd-nspawn.html) or other containerization software. Using Xenial build host inside containers is **highly recommended**,
- quick start (using Vagrant) this is the easiest way to get started. See steps below,
- compilation environment is **highly recommended** to be [Ubuntu Xenial 16.04 x64](http://archive.ubuntu.com/ubuntu/dists/xenial-updates/main/installer-amd64/current/images/netboot/mini.iso) (other releases are **not officially supported** but [Ubuntu Trusty 14.04 x64](http://archive.ubuntu.com/ubuntu/dists/trusty-updates/main/installer-amd64/current/images/netboot/mini.iso) might still work),
- installed basic system, OpenSSH and Samba (optional),
- superuser rights (configured `sudo` or root shell).

**Execution**
	
	apt-get -y install git
	git clone https://github.com/igorpecovnik/lib --depth 1
	cp lib/compile.sh .
	./compile.sh

This will download all necessary sources, execute compilation and/or build a bootable image. Most of things will be cached so next run will be extremely faster!

**Quick Start**

First, you'll need to [install vargrant](https://www.vagrantup.com/downloads.html) on your host box. You'll also need to install a plug-in that will enable us to resize the primary storage device. Without it, Vagrant images are too small to build Armbian.

	vagrant plugin install vagrant-disksize

Now we'll need to [install git](https://git-scm.com/downloads) and check out the Armbian code. While this might seem obvious, we'll rely on it being there when we use Vagrant. 

	# Check out the code.
	git clone --depth 1 https://github.com/igorpecovnik/lib.git lib
	
	# Make the Vagrant box available. This might take a while but only needs to be done once.
	vagrant box add ubuntu/xenial64
	
	# If the box gets updated by the folks at HashiCorp, we'll want to update our copy too.
	# This only needs done once and a while.
	vagrant box update
	
	# Finally! Let's bring the box up. This might take a minute or two.
	cd lib
	vagrant up
	
	# When the box has been installed we can get access via ssh.
	vagrant ssh

Once it's finally up and you're logged in, it works much like any of the other install (note: these are run on the *guest* box).

	cp lib/compile.sh .
	sudo ./compile.sh

There are two directories that are mapped from the host to the guest:

* You'll find the git repo is shared, and
* The *output* directory is shared (makes it easy to preserve cache, downloads, and IOSs between builds).

Wrap up your vagrant box when no longer needed (log out of the guest before running these):

	# Shutdown, but leave the box around for more building at a later time:
	vagrant halt
	
	# Trash the box and remove all the related storage devices.
	vagrant destroy

## How to change kernel configuration?

Edit `compile.sh` and set

	KERNEL_CONFIGURE="yes"

to display kernel configuration menu prior to compilation

More info:

- [Documentation](http://www.armbian.com/using-armbian-tools/)
- [Prebuilt images](http://www.armbian.com/download/)
- [Support forums](http://forum.armbian.com/ "Armbian support forum")
- [Project at Github](https://github.com/igorpecovnik/lib)
