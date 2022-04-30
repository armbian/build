sed -i 's|mirrors.ustc.edu.cn/debian-security|security.debian.org/debian-security|g' /etc/apt/sources.list
sed -i 's|mirrors.ustc.edu.cn/debian-security|security.debian.org|g' /etc/apt/sources.list
sed -i 's|mirrors.ustc.edu.cn/ubuntu-ports|ports.ubuntu.com|g' /etc/apt/sources.list
sed -i 's/mirrors.ustc.edu.cn/deb.debian.org/g' /etc/apt/sources.list
sed -i 's|mirrors.tuna.tsinghua.edu.cn/debian-security|security.debian.org/debian-security|g' /etc/apt/sources.list
sed -i 's|mirrors.tuna.tsinghua.edu.cn/debian-security|security.debian.org|g' /etc/apt/sources.list
sed -i 's|mirrors.tuna.tsinghua.edu.cn/ubuntu-ports|ports.ubuntu.com|g' /etc/apt/sources.list
sed -i 's/mirrors.tuna.tsinghua.edu.cn/deb.debian.org/g' /etc/apt/sources.list
sed -i 's|mirrors.tuna.tsinghua.edu.cn/armbian|apt.armbian.com|g' /etc/apt/sources.list.d/armbian.list
echo "done"
