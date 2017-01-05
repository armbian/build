## Quick Start with Vagrant

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

Once it's finally up and you're logged in, it works much like any of the other install (note: these commands are run on the *guest* box).

	cp lib/compile.sh .
	sudo ./compile.sh

There are two directories that are mapped from the host to the guest:

* You'll find the git repo is shared, and
* The *output* directory is also shared (makes it easy to preserve cache, downloads, and IOSs between builds). It also makes them easily accessible on your host box.

Wrap up your vagrant box when no longer needed (log out of the guest before running these on the host system):

	# Shutdown, but leave the box around for more building at a later time:
	vagrant halt

	# Trash the box and remove all the related storage devices.
	vagrant destroy
