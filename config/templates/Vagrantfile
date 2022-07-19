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
    config.vm.define "Armbian Builder" do |builder|
        # We should use a box that is compatible with Virtualbox and Libvirt
        builder.vm.box = "generic/ubuntu2204"
        builder.vm.box_version = ">= 4.0.2"

        # provisioning: install dependencies, download the repository copy
        builder.vm.provision "shell", inline: $provisioning_script

        # forward terminal type for better compatibility with Dialog - disabled on Ubuntu by default
        builder.ssh.forward_env = ["TERM"]

        builder.vm.hostname = "armbian-builder"

        # SSH password auth is disabled by default, uncomment to enable and set the password
        #config.ssh.password = "armbian"

        builder.vm.provider "virtualbox" do |vb|
            vb.name = "Armbian Builder"

	    # Default images are not big enough to build Armbian.
	    #config.vagrant.plugins = "vagrant-disksize"
	    #config.disksize.size = "40GB"

            # uncomment this to enable the VirtualBox GUI
            #vb.gui = true

            # Tweak these to fit your needs.
            #vb.memory = "8192"
            #vb.cpus = "4"
        end

        builder.vm.provider "libvirt" do |libvirt|
            # Some specifics libvirt options
            libvirt.driver = "kvm"
	    libvirt.uri = "qemu:///system"
	    libvirt.default_prefix = ""

            # Default images are not big enough to build Armbian.
	    libvirt.storage_pool_name = "default"
	    libvirt.storage :file, :size => "40G"

            # Tweak these to fit your needs.
            libvirt.memory = "8192"
            libvirt.cpus = "4"
        end

        case File.basename(Dir.getwd)
        when "templates"
	    builder.vm.synced_folder "../..", "/vagrant", type: "sshfs"
        when "userpatches"
            builder.vm.synced_folder "..", "/vagrant", type: "sshfs"
        end
    end
end
