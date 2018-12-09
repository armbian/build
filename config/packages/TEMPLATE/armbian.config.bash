ARMBIAN_PKG_PACKAGE=armbian-example-package				# package name
ARMBIAN_PKG_VERSION="2.9"								# to set package to certain version and prevent rebuild if nothing is changed
ARMBIAN_PKG_MAINTAINER="John Doe"						# overwrite global settings per package
ARMBIAN_PKG_MAINTAINERMAIL="john@armbian.com"			# overwrite global settings per package
ARMBIAN_PKG_ARCH=all									# the same meaning as in Debian
ARMBIAN_PKG_PRIORITY=optional							# the same meaning as in Debian
ARMBIAN_PKG_DEPENDS="libc6 (>= 2.14)"					# the same meaning as in Debian
ARMBIAN_PKG_CONFLICTS="nano"							# the same meaning as in Debian
ARMBIAN_PKG_BREAKS="text (<< 2.9)"						# the same meaning as in Debian
ARMBIAN_PKG_REPLACES="joe (<< 2.9), hello-joe"			# the same meaning as in Debian
ARMBIAN_PKG_SECTION="devel"								# the same meaning as in Debian
ARMBIAN_PKG_HOMEPAGE="https://www.johndoe.com"			# the same meaning as in Debian
ARMBIAN_PKG_DESCRIPTION="Example"						# the same meaning as in Debian
ARMBIAN_PKG_REPOSITORY=bionic       					# internal settings for placing into repository subdir (bionic,jessie,...)
