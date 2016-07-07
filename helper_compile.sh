#!/bin/bash

function do_clean_up()
{
	## update all "lib" & .ccache files to logname user
	#
	#chown -R $(/usr/bin/logname):$(/usr/bin/id -g $(/usr/bin/logname)) $SRC/lib $HOME/.ccache
	#
}

#
# uncomment if you want to call do_clean_up on Ctrl-C
#trap '{ echo "Hey, you pressed Ctrl-C.  Time to clean-up & quit." ; do_clean_up; exit 1; }' INT

# useful for forked version of Armbian "lib" using github RSA public key
# uncomment if you want the Armbian "lib" files to be managed with logname user (login name) 
# instead of root UID

#PREFIX_GIT_LIB='sudo -u $(/usr/bin/logname)'

#
# uncomment/modify the following config *if* needed
#

#USE_CCACHE="yes"
#EXPERIMENTAL_DEBOOTSTRAP="yes"
#EXTENDED_DEBOOTSTRAP="yes"
#USE_MAINLINE_GOOGLE_MIRROR="yes"
#COMPRESS_OUTPUTIMAGE="yes"
#SEVENZIP="yes"

#PROGRESS_DISPLAY="plain"
#PROGRESS_LOG_TO_FILE="yes"
#USEALLCORES="yes"

#RELEASE="xenial"
#RELEASE="trusty"
#RELEASE="jessie"

#SUBREVISON=""

#BOARD=""
#BRANCH="default"
#BRANCH="next"

#KERNEL_ONLY="no"
#KERNEL_ONLY="yes"

#KERNEL_CONFIGURE="yes" 
#KERNEL_CONFIGURE="no"

#CLEAN_LEVEL="make,debs"

#DEST_LANG="en_US.UTF-8"

