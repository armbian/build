#!/bin/bash
# build.sh

reset;

echo -e "Console - Armbian-Builder > started!"
echo -e "Console - Armbian-Builder > Setup your settings & run build!"

while true;
do
read -p "Enter Board > " board
read -p "Enter Branch > " branch
read -p "Enter Release > " release

read -p "Build Minimal?(Yy/Nn) > " bm
case $bm in
		y|Y) bm="yes";; continue;
		n|N) bm="no";; continue;
        *) echo "Invalid option. Defaulting to no minimal build."; bm="no";;
esac

read -p "Build Desktop?(Yy/Nn) > " bm
case $bd in
		y|Y) bd="yes";; continue;
		n|N) bd="no";; continue;
        *) echo "Invalid option. Defaulting to no minimal build."; bm="no";;
esac

read -p "Kernel Configure(Yy/Nn) > " kn
case $bm in
		y|Y) kn="yes";; continue;
		n|N) kn="no";; continue;
        *) echo "Invalid option. Defaulting to no minimal build."; bm="no";;
esac

echo -e "Console - Armbian-Builder > Building for: $board with options: $branch, $release, Build-Minimal = $bm, Build-Desktop=$bd, Kernel-Configure=$kn !"

./compile.sh BOARD=$board BRANCH=$branch RELEASE=$release BUILD_MINIMAL=$bm BUILD_DESKTOP=$bd KERNEL_CONFIGURE=kn
done
