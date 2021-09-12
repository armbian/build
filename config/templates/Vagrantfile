# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.require_version ">= 1.5"

$provisioning_script = <<SCRIPT
# use remote git version instead of sharing a copy from host to preserve proper file permissions
# and prevent permission related issues for the temp directory
git clone https://github.com/armbian/build /home/vagrant/armbian
mkdir -p /vagrant/output /vagrant/userpatches
ln -sf /vagrant/output /home/vagrant/armbian/output
ln -sf /vagrant/userpatches /home/vagrant/armbian/userpatches
SCRIPT

Vagrant.configure(2) do |config|

    # What box should we base this build on?
    config.vm.box = "ubuntu/focal64"
    config.vm.box_version = ">= 20180719.0.0"

    # Default images are not big enough to build Armbian.
    config.vagrant.plugins = "vagrant-disksize"
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

    case File.basename(Dir.getwd)
    when "templates"
        config.vm.synced_folder "../..", "/vagrant"
    when "userpatches"
        config.vm.synced_folder "..", "/vagrant"
    end
end
