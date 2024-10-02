#!/bin/bash
exec </dev/null </dev/null 2>/dev/null
export LANG=C LC_ALL=C

# In all cases, we want the media to be in quiescent, clean state.
sync
[ -x /sbin/mdadm ] && /sbin/mdadm --wait-clean --scan

# Function used to park all SATA disks.
function ParkDisks() {
    if [ -x /sbin/hdparm ]; then
        Wait=0
        for Dev in /sys/block/sd* ; do
            [ -e $Dev ] && /sbin/hdparm -y /dev/${Dev##*/} && Wait=2
            sleep $Wait
            echo 1 > /sys/class/block/${Dev##*/}/device/delete
        done
        sleep $Wait
    fi  
}

case "$1" in
    # reboot|kexec)
        # Do not park disks when rebooting or switching kernels.
    #     ;;  
    *)  
        ParkDisks
        ;;  
esac
