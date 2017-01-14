# Quick Start with Vagrant

## Vagrant HOST Steps

The following steps are preformed on the *host* that runs Vagrant.

### Installing Vagrant and Downloading Armbian

First, you'll need to [install vargrant](https://www.vagrantup.com/downloads.html) on your host box. Next, you'll need to install a plug-in that will enable us to resize the primary storage device. Without it, the default Vagrant images are too small to build Armbian.

	vagrant plugin install vagrant-disksize

Now we'll need to [install git](https://git-scm.com/downloads) and check out the Armbian code. While this might seem obvious, we rely on it being there when we use Vagrant to bring up our guest-build box.

	# Check out the code.
	git clone --depth 1 https://github.com/igorpecovnik/lib.git lib

	# Make the Vagrant box available. This might take a while but only needs to be done once.
	vagrant box add ubuntu/xenial64

	# If the box gets updated by the folks at HashiCorp, we'll want to update our copy too.
	# This only needs done once and a while.
	vagrant box update

### Armbian Directory Structure

Before we bring up the box, take note of the [directory structure]( https://docs.armbian.com/Developer-Guide_Build-Process/#directory-structure) used by the Armbian build tool. When you read the lib/Vagrant file you'll see that Vagrant automatically creates a directory for *output*. This is helpful as it enables you to easily get your images once built. It also speeds-up the build process by caching files used during the build. In addition, Vagrant creates the *userscripts* directory. This is where you'd put any files used to [customize the build process](https://docs.armbian.com/Developer-Guide_User-Configurations/). 

### Creating the Vagrant Guest Box Used to Build 
Let's bring the box up. This might take a minute or two depending on your bandwidth and hardware.

	# We have to be in the same directory as the Vagrant file.
	cd lib

	# And now we simply let vagrant create out box and bring it up. 
	vagrant up

	# When the box has been installed we can get access via ssh.
	# (No need for passwords, Vagrant installs the keys we'll need.)
	vagrant ssh

## Vagrant GUEST Steps

The following steps are all run on the *guest* Vagrant created for us.

Once it's finally up and you're logged in, it works much like any of the other install methods (NOTE: again, these commands are run on the *guest* box).

	# Copy the compile script out of the lib directory.
	cp lib/compile.sh .

	# Let's get buidling!
	sudo ./compile.sh

## More Vagrant HOST Steps

Wrap up your vagrant box when no longer needed (log out of the guest before running these on the *host* system):

	# Shutdown, but leave the box around for more building at a later time:
	vagrant halt

	# Trash the box and remove all the related storage devices.
	vagrant destroy
