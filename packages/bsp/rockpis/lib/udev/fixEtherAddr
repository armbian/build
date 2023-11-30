#!/bin/sh
#Assign specified interface a fixed, unique Ethernet MAC address constructed
#from given prefix byte followed by five byte RK3308 CPU serial number
#Ethernet prefix byte value less 2 should be exactly divisible by 4
#e.g. (prefix - 2) % 4 == 0

[ "$2" ] || {
  echo "Specify network interface and first Ethernet address byte in hex" >&2
  exit 1
}

cpuSerialNum() {
#output first 5 bytes of CPU Serial number in hex with a space between each
#nvmem on RK3308 does not handle multiple simultaneous readers :-(
  nvmem=/sys/bus/nvmem/devices/rockchip-otp0/nvmem
  serNumOffset=20
  /bin/flock -w2 $nvmem /bin/od -An -vtx1 -j $serNumOffset -N 5 $nvmem
}

Id=`cpuSerialNum` && { #fail if Rockchip nvmem not available
  /sbin/ip link set $1 address $2:`echo $Id | tr ' ' :`
}
