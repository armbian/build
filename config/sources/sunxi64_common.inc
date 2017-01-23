ARCH=arm64
KERNEL_IMAGE_TYPE=Image
HAS_UUID_SUPPORT=yes

case $BRANCH in
	dev)
	BOOTSCRIPT='boot-sun50i-next.cmd:boot.cmd'
	BOOTENV_FILE='sun50i-next.txt'
	LINUXCONFIG='linux-sun50i-dev'
	;;
esac
