# -*- mode: ruby -*-
# vi: set ft=ruby :

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

    #######################################################################
    # We could sync more folders (that *seems* like the best way to go),
    # but in many cases builds fail because hardlinks are not supported.
    # So, a more failproof approach is to just use a larger disk.
    #
    # Following the directory structure outlined here:
    # https://docs.armbian.com/Developer-Guide_Build-Process/#directory-structure

    # So we don't have to download the code a 2nd time.
    config.vm.synced_folder ".", "/home/ubuntu/lib"

    # Share folders with the host to make it easy to get our images out.
    config.vm.synced_folder "../output", "/home/ubuntu/output", create: true

    # Bring over your customizations.
    config.vm.synced_folder "../userpatches", "/home/ubuntu/userpatches", create: true

    config.vm.provider "virtualbox" do |vb|
        vb.name = "Armbian Builder"
        vb.gui = true

        # Tweak these to fit your needs.
        vb.memory = "8192"
        vb.cpus = "4"

    end
end
