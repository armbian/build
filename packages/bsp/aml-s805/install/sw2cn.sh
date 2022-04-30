echo "Change apt & docker mirror"
sed -i 's/deb.debian.org/mirrors.ustc.edu.cn/g' /etc/apt/sources.list
sed -i 's|security.debian.org/debian-security|mirrors.ustc.edu.cn/debian-security|g' /etc/apt/sources.list
sed -i 's|security.debian.org|mirrors.ustc.edu.cn/debian-security|g' /etc/apt/sources.list
sed -i 's|ports.ubuntu.com|mirrors.ustc.edu.cn/ubuntu-ports|g' /etc/apt/sources.list
sed -i 's|apt.armbian.com|mirrors.tuna.tsinghua.edu.cn/armbian|g' /etc/apt/sources.list.d/armbian.list
mkdir /etc/docker -p
cp -p /boot/install/docker-daemon.json /etc/docker/daemon.json
echo "done"
