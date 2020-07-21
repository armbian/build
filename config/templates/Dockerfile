FROM ubuntu:20.04
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       gnupg \
       gnupg1 \
       gpgv1
RUN sh -c  "if [ x"" != x$http_proxy ]; then \
			    apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --keyserver-options http-proxy=$http_proxy --recv-keys ED75B5A4483DA07C >/dev/null 2>&1; \
		    else \
			    apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys ED75B5A4483DA07C >/dev/null 2>&1; \
		    fi"
RUN echo "deb http://repo.aptly.info/ nightly main" > /etc/apt/sources.list.d/aptly.list
RUN dpkg --add-architecture i386
RUN apt-get update \
    && apt-get -y upgrade \
    && apt-get install -y --no-install-recommends \
       git \
       dialog \
       lsb-release \
       binutils \
       wget \
       ca-certificates \
       device-tree-compiler \
       pv \
       bc \
       lzop \
       zip \
       binfmt-support \
       build-essential \
       ccache \
       debootstrap \
       ntpdate \
       gawk \
       gcc-arm-linux-gnueabihf \
       qemu-user-static \
       u-boot-tools \
       uuid-dev \
       zlib1g-dev \
       unzip \
       libusb-1.0-0-dev \
       parted \
       pkg-config \
       libncurses5-dev \
       whiptail \
       debian-keyring \
       debian-archive-keyring \
       f2fs-tools \
       libfile-fcntllock-perl \
       rsync \
       libssl-dev \
       nfs-kernel-server \
       btrfs-progs \
       ncurses-term \
       p7zip-full \
       kmod \
       dosfstools \
       libc6-dev-armhf-cross \
       fakeroot \
       xxd \
       imagemagick \
       curl \
       patchutils \
       python2 \
       python3 \
       liblz4-tool \
       libpython2.7-dev \
       linux-base \
       swig \
       libpython3-dev \
       python3-dev \
       systemd-container \
       udev \
       g++-8-arm-linux-gnueabihf \
       lib32stdc++6 \
       cpio \
       tzdata \
       psmisc \
       acl \
       libc6-i386 \
       lib32ncurses6 \
       lib32tinfo6 \
       locales \
       ncurses-base \
       zlib1g:i386 \
       pixz \
       bison \
       libbison-dev \
       flex \
       libfl-dev \
       pigz \
       aptly \
       aria2 \
       cryptsetup \
       cryptsetup-bin \
       python3-distutils
RUN locale-gen en_US.UTF-8

# Static port for NFSv3 server used for USB FEL boot
RUN sed -i 's/\(^STATDOPTS=\).*/\1"--port 32765 --outgoing-port 32766"/' /etc/default/nfs-common \
    && sed -i 's/\(^RPCMOUNTDOPTS=\).*/\1"--port 32767"/' /etc/default/nfs-kernel-server

ENV LANG='en_US.UTF-8' LANGUAGE='en_US:en' LC_ALL='en_US.UTF-8' TERM=screen
WORKDIR /root/armbian
ENTRYPOINT [ "/bin/bash", "/root/armbian/compile.sh" ]
