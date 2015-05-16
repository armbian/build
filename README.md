**This is a script to build Debian or Ubuntu for various ARM single board computers.** It uses proven sources and configurations to create **uboot**, **kernel** and bootable **SD images** for: 
	
-  Cubieboard 1,2,3
-  BananaPi / PRO / R1
-  Cubox, Hummingboard
-  Olimex Lime, Lime 2, Micro, 
-  Orange Pi
-  Udoo quad

# How to use script?

You will need to setup proven development environment with [Ubuntu 14.04 LTS x64 server image](http://releases.ubuntu.com/14.04/) and cca. 20G of free space. Install basic system and create this call script:

	nano compile.sh

copy and paste the following code:

	#!/bin/bash	
	# 
	# 	Edit and execute this script - Ubuntu 14.04 x86/64 recommended
	#
	#   Check https://github.com/igorpecovnik/lib for possible updates
	#

	# method
	KERNEL_ONLY="no"                            # build kernel only
	SOURCE_COMPILE="yes"                        # force source compilation
	KERNEL_CONFIGURE="no"                       # change default configuration
	KERNEL_CLEAN="yes"                          # MAKE clean before compilation
	USEALLCORES="yes"                           # Use all CPU cores
	BUILD_DESKTOP="no"                          # desktop with hw acceleration for some boards 
	
	# user 
	DEST_LANG="en_US.UTF-8"                     # sl_SI.UTF-8, en_US.UTF-8
	TZDATA="Europe/Ljubljana"                   # time zone
	ROOTPWD="1234"                              # forced to change @first login
	SDSIZE="1500"                               # SD image size in MB
	AFTERINSTALL=""                             # command before closing image 
	MAINTAINER="Igor Pecovnik"                  # deb signature
	MAINTAINERMAIL="igor.pecovnik@****l.com"    # deb signature
	GPG_PASS=""                                 # set GPG password for non-interactive packing
	
	# advanced
	KERNELTAG="v4.0.3"                         # kernel TAG - valid only for mainline
	UBOOTTAG="v2015.04"							# kernel TAG - valid for all sunxi
	FBTFT="yes"                                 # https://github.com/notro/fbtft 
	EXTERNAL="yes"                              # compile extra drivers
	FORCE="yes"									# ignore manual changes to source

	# source is where we start the script
	SRC=$(pwd)
	# destination
	DEST=$(pwd)/output                                      
	# get updates of the main build libraries
	if [ -d "$SRC/lib" ]; then
    	cd $SRC/lib
		git pull 
	else
    	# download SDK
   		apt-get -y -qq install git
    	git clone https://github.com/igorpecovnik/lib
	fi
	source $SRC/lib/main.sh

# How to help?

Engage in script development, test & send feedback or just help to buy some new toys ;)

[![Paypal donate](https://www.paypalobjects.com/en_US/i/btn/btn_donate_SM.gif)](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=CUYH2KR36YB7W)
