# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.require_version ">= 1.5"

$provisioning_script = <<SCRIPT
mkdir -p /vagrant/output /vagrant/userpatches /home/ubuntu/cache /home/ubuntu/.tmp
ln -sf /home/ubuntu/cache /vagrant/cache
ln -sf /home/ubuntu/.tmp /vagrant/.tmp
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

        # uncomment this to enable the VirtualBox GUI
        #vb.gui = true

        # Tweak these to fit your needs.
        #vb.memory = "8192"
        #vb.cpus = "4"
    end
end
