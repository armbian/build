

- Libraries for creating ARM SD images for various boards: Cubieboard, BananaPi, Cubox, Humminboard, Olimex, ...
- Boot loaders and kernel images are compiled only once and cached - overridden with SOURCE_COMPILE="yes" 

    ```shell
	#!/bin/bash
	# 
	# Edit and execute this script
	#
	
	# numbers
    SDSIZE="1200"								# SD image size in MB
    REVISION="1.3"								# image release version
    
    # method
    SOURCE_COMPILE="no"							# force source compilation: yes / no
    KERNEL_CONFIGURE="no"						# want to change my default configuration
    KERNEL_CLEAN="no"							# run MAKE clean before kernel compilation
    USEALLCORES="no"							# Use all CPU cores for compiling
    
    # user 
    DEST_LANG="en_US.UTF-8" 	 				# sl_SI.UTF-8, en_US.UTF-8
    TZDATA="Europe/Ljubljana" 					# Timezone
    ROOTPWD="1234"   		  					# Must be changed @first login
    HOST="$BOARD"						 		# Hostname
    MAINTAINER="Igor Pecovnik"					# deb signature
    MAINTAINERMAIL="igor.pecovnik@****l.com"	# deb signature
    
    # advanced
    FBTFT="yes"									# https://github.com/notro/fbtft 
    EXTERNAL="no"								# compile extra drivers`
#-----------------------------------------------------------------------------------------------------
# source is where we start the script
SRC=$(pwd)
# Destination
DEST=$(pwd)/output                      		      	
# get updates of the main build libraries
if [ -d "$SRC/lib" ]; then
	cd $SRC/lib
	git pull 
else
	git clone https://github.com/igorpecovnik/lib lib
fi
source $SRC/lib/main.sh # Main
#-------------------------------------------------------------------------------------------------------------------------
    ```

===
<img src="http://cdn.flaticon.com/png/256/47478.png">
