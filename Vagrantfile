# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.require_version ">= 1.5"

$provisioning_script = <<SCRIPT
dpkg --add-architecture i386
apt-get update && DEBIAN_FRONTEND=noninteractive apt-get -y dist-upgrade && \
	DEBIAN_FRONTEND=noninteractive apt-get install -y git dialog lsb-release binutils wget ca-certificates device-tree-compiler \
	pv bc lzop zip binfmt-support build-essential ccache debootstrap ntpdate gawk gcc-arm-linux-gnueabihf gcc-arm-linux-gnueabi \
	qemu-user-static u-boot-tools uuid-dev zlib1g-dev unzip libusb-1.0-0-dev ntpdate parted pkg-config libncurses5-dev whiptail \
	debian-keyring debian-archive-keyring f2fs-tools libfile-fcntllock-perl rsync libssl-dev nfs-kernel-server btrfs-tools \
	gcc-aarch64-linux-gnu ncurses-term p7zip-full dos2unix dosfstools libc6-dev-armhf-cross libc6-dev-armel-cross libc6-dev-arm64-cross \
	curl gcc-arm-none-eabi libnewlib-arm-none-eabi patchutils python liblz4-tool libpython2.7-dev linux-base swig libpython-dev \
	systemd-container udev distcc libstdc++-arm-none-eabi-newlib gcc-4.9-arm-linux-gnueabihf gcc-4.9-aarch64-linux-gnu \
	g++-4.9-arm-linux-gnueabihf g++-4.9-aarch64-linux-gnu g++-5-aarch64-linux-gnu g++-5-arm-linux-gnueabihf lib32stdc++6 \
	libc6-i386 lib32ncurses5 lib32tinfo5 locales ncurses-base zlib1g:i386 aptly
locale-gen en_US.UTF-8
git clone https://github.com/armbian/build /home/ubuntu/armbian
ln -sf /vagrant/output /home/ubuntu/armbian/output
ln -sf /vagrant/userpatches /home/ubuntu/armbian/userpatches
SCRIPT

Vagrant.configure(2) do |config|

    # What box should we base this build on?
    config.vm.box = "ubuntu/xenial64"

    #######################################################################
    # THIS REQUIRES YOU TO INSTALL A PLUGIN. RUN THE COMMAND BELOW...
    #
    #   $ vagrant plugin install vagrant-disksize
    #
    # Default images are not big enough to build Armbian.
    config.disksize.size = "40GB"

    # provisioning: install dependencies, download the repository copy
    config.vm.provision "shell", inline: $provisioning_script

    # forward terminal type for better compatibility with Dialog - disabled on Ubuntu by default
    config.ssh.forward_env = ["TERM"]

    # default user name is "ubuntu", please do not change it

    # SSH password auth is disabled by default, uncomment to enable and set the password
    #config.ssh.password = "armbian"

    config.vm.provider "virtualbox" do |vb|
        vb.name = "Armbian Builder"

        # uncomment this to use the VirtualBox GUI
        #vb.gui = true

        # Tweak these to fit your needs.
        #vb.memory = "8192"
        #vb.cpus = "4"
    end
end
