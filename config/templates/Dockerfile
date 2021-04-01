FROM ubuntu:20.04
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       gnupg \
       gnupg1 \
       gpgv1 \
    && rm -rf /var/lib/apt/lists/*
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
       acl \
       aptly \
       aria2 \
       bc \
       binfmt-support \
       binutils \
       bison \
       btrfs-progs \
       build-essential \
       ca-certificates \
       ccache \
       cpio \
       cryptsetup \
       cryptsetup-bin \
       curl \
       debian-archive-keyring \
       debian-keyring \
       debootstrap \
       device-tree-compiler \
       dialog \
       dosfstools \
       f2fs-tools \
       fakeroot \
       flex \
       g++-8-arm-linux-gnueabihf \
       gawk \
       gcc-arm-linux-gnueabihf \
       git \
       imagemagick \
       jq \
       kmod \
       lib32ncurses6 \
       lib32stdc++6 \
       lib32tinfo6 \
       libbison-dev \
       libc6-dev-armhf-cross \
       libc6-i386 \
       libfile-fcntllock-perl \
       libfl-dev \
       liblz4-tool \
       libncurses5-dev \
       libpython2.7-dev \
       libpython3-dev \
       libssl-dev \
       libusb-1.0-0-dev \
       linux-base \
       locales \
       lsb-release \
       lzop \
       ncurses-base \
       ncurses-term \
       nfs-kernel-server \
       ntpdate \
       openssh-client \
       p7zip-full \
       parted \
       patchutils \
       pigz \
       pixz \
       pkg-config \
       psmisc \
       pv \
       python2 \
       python3 \
       python3-dev \
       python3-distutils \
       qemu-user-static \
       rsync \
       swig \
       systemd-container \
       tzdata \
       u-boot-tools \
       udev \
       unzip \
       uuid-dev \
       uuid-runtime \
       wget \
       whiptail \
       xxd \
       zip \
       zlib1g-dev \
       zlib1g:i386 \
    && rm -rf /var/lib/apt/lists/*
RUN locale-gen en_US.UTF-8

# Static port for NFSv3 server used for USB FEL boot
RUN sed -i 's/\(^STATDOPTS=\).*/\1"--port 32765 --outgoing-port 32766"/' /etc/default/nfs-common \
    && sed -i 's/\(^RPCMOUNTDOPTS=\).*/\1"--port 32767"/' /etc/default/nfs-kernel-server

ENV LANG='en_US.UTF-8' LANGUAGE='en_US:en' LC_ALL='en_US.UTF-8' TERM=screen
WORKDIR /root/armbian
ENTRYPOINT [ "/bin/bash", "/root/armbian/compile.sh" ]
