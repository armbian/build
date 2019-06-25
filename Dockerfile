FROM ubuntu:18.04
RUN dpkg --add-architecture i386
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get -y dist-upgrade && \
	DEBIAN_FRONTEND=noninteractive apt-get install -y git dialog lsb-release binutils wget ca-certificates device-tree-compiler \
	pv bc lzop zip binfmt-support build-essential ccache debootstrap ntpdate gawk gcc-arm-linux-gnueabihf \
	qemu-user-static u-boot-tools uuid-dev zlib1g-dev unzip libusb-1.0-0-dev parted pkg-config libncurses5-dev whiptail \
	debian-keyring debian-archive-keyring f2fs-tools libfile-fcntllock-perl rsync libssl-dev nfs-kernel-server btrfs-tools \
	ncurses-term p7zip-full kmod dosfstools libc6-dev-armhf-cross fakeroot xxd \
	curl patchutils python liblz4-tool libpython2.7-dev linux-base swig libpython-dev \
	systemd-container udev g++-5-arm-linux-gnueabihf lib32stdc++6 cpio tzdata psmisc acl \
	libc6-i386 lib32ncurses5 lib32tinfo5 locales ncurses-base zlib1g:i386 pixz bison libbison-dev flex libfl-dev \
        aptly aria2 cryptsetup cryptsetup-bin gnupg1 gpgv1
RUN locale-gen en_US.UTF-8
ENV LANG='en_US.UTF-8' LANGUAGE='en_US:en' LC_ALL='en_US.UTF-8' TERM=screen
WORKDIR /root/armbian
ENTRYPOINT [ "/bin/bash", "/root/armbian/compile.sh" ]
