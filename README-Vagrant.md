# Quick Start with Vagrant

## Vagrant HOST Steps

The following steps are preformed on the *host* that runs Vagrant.

### Installing Vagrant and Downloading Armbian

#### Virtualbox Version

**WARNING:** We'll be using [Virtualbox as a virtualization provider for Vagrant](https://www.vagrantup.com/docs/virtualbox/). Virtualbox has [documented issues running Xenial under heavy disk IO](https://bugs.launchpad.net/cloud-images/+bug/1616794). Please make sure your version of Virtualbox is >= 5.1.12 where the issue, ["Storage: fixed a problem with the LsiLogic SCSI controller where requests could be lost with SMP guests"](https://www.virtualbox.org/wiki/Changelog), appears to have been resolved.

First, you'll need to [install Vagrant](https://www.vagrantup.com/downloads.html) on your host box. Next, you'll need to install a plug-in that will enable us to resize the primary storage device. Without it, the default Vagrant images are too small to build Armbian.

	vagrant plugin install vagrant-disksize

Now we'll need to [install git](https://git-scm.com/downloads) and clone the Armbian repo. While this might seem obvious, we rely on it being there when we use Vagrant to bring up our guest-build box.

	# Clone the project.
	git clone --depth 1 https://github.com/igorpecovnik/lib.git lib

	# Make the Vagrant box available. This might take a while but only needs to be done once.
	vagrant box add ubuntu/xenial64

	# If the box gets updated by the folks at HashiCorp, we'll want to update our copy too.
	# This only needs done once and a while.
	vagrant box update

### Armbian Directory Structure

Before we bring up the box, take note of the [directory structure]( https://docs.armbian.com/Developer-Guide_Build-Process/#directory-structure) used by the Armbian build tool. When you read the lib/Vagrant file you'll see that Vagrant automatically creates a directory for *output*. This is helpful as it enables you to easily retrieve your images from the host once built. It also speeds-up the build process by caching files used during the build. In addition, Vagrant creates the *userscripts* directory. This is where you'd put any files used to [customize the build process](https://docs.armbian.com/Developer-Guide_User-Configurations/). 

### Creating the Vagrant Guest Box Used to Build 
Let's bring the box up. This might take a minute or two depending on your bandwidth and hardware.

	# We have to be in the same directory as the Vagrant file.
	cd lib

	# And now we simply let vagrant create our box and bring it up. 
	vagrant up

	# When the box has been installed we can get access via ssh.
	# (No need for passwords, Vagrant installs the keys we'll need.)
	vagrant ssh

## Vagrant GUEST Steps

The following steps are all run on the *guest* Vagrant created for us.

Once it's finally up and you're logged in, it works much like any of the other install methods (NOTE: again, these commands are run on the *guest* box).

	# Copy the compile script out of the lib directory to your new home directory.
	cp lib/compile.sh .

	# Let's get building!
	sudo ./compile.sh

## More Vagrant HOST Steps

Wrap up your vagrant box when no longer needed (log out of the guest before running these commands on the *host* system):

	# Shutdown, but leave the box around for more building at a later time:
	vagrant halt

	# Trash the box and remove all the related storage devices.
	vagrant destroy
