# Armbian packaging #

This Subsystem is primarely designed to make packages from the following sections:

- common
	- armbian-config
	- armbian-desktop
	- armbian-firmware
	- armbian-firmware-full
	- armbian-bsp *(this is now the same with one exception. It doesn't execute family_tweaks and family_tweaks_bsp. Those functions are getting manually implemented into the packages below)* 
- family
	- rockchip
	- sun7i
	- etc.
- board
	- pinebook
	- cubietruck
	- etc.

# How it works? #

It search for the file named **armbian.config.bash**. This file contain package informations like:


	ARMBIAN_PKG_PACKAGE=armbian-example-package		# package name, leave empty of you only want to run scripts
	ARMBIAN_PKG_VERSION="2.9"				# to set package to certain version and prevent rebuild if nothing is changed
	ARMBIAN_PKG_MAINTAINER="John Doe"			# overwrite global settings per package
	ARMBIAN_PKG_INSTALL="no"				# if you only want to pack package and not install it
	ARMBIAN_PKG_MAINTAINERMAIL="john@armbian.com"		# overwrite global settings per package
	ARMBIAN_PKG_ARCH=all					# the same meaning as in Debian
	ARMBIAN_PKG_PRIORITY=optional				# the same meaning as in Debian
	ARMBIAN_PKG_DEPENDS="libc6 (>= 2.14)"			# the same meaning as in Debian
	ARMBIAN_PKG_CONFLICTS="nano"				# the same meaning as in Debian
	ARMBIAN_PKG_BREAKS="text (<< 2.9)"			# the same meaning as in Debian
	ARMBIAN_PKG_REPLACES="joe (<< 2.9), hello-joe"		# the same meaning as in Debian
	ARMBIAN_PKG_SECTION="devel"				# the same meaning as in Debian
	ARMBIAN_PKG_HOMEPAGE="https://www.johndoe.com"		# the same meaning as in Debian
	ARMBIAN_PKG_DESCRIPTION="Example"			# the same meaning as in Debian
	ARMBIAN_PKG_REPOSITORY=bionic				# internal settings for placing into repository subdir (bionic,jessie,...) 

After reading the config file, it execute **armbian.build.bash** if it exists. This script can manipulate things before packing. Overlay is automatically merged while this script is optional.

# What is the package structure? #

Create a folder inside common, family or board:

	mywhatever
	mywhatever/overlay			# Place files in appropriate directories. This will be packed as is on /
	mywhatever/armbian.build.bash		# script for building before packing
	mywhatever/armbian.config.bash		# package definitions
	mywhatever/armbian.postinst.bash	# bash script to create DEBIAN postinst
	mywhatever/armbian.postrm.bash		# bash script to create DEBIAN postrm
	mywhatever/armbian.preinst.bash		# bash script to create DEBIAN preinst
	mywhatever/armbian.prerm.bash		# bash script to create DEBIAN prerm
	mywhatever/armbian.triggers.bash	# bash script to create DEBIAN triggers


It is possible to add unlimited additional packages to any of the category or even make a new top level category. In that case, you need to adjust lib/makeboarddeb-ng.sh
