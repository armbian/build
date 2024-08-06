#!/bin/bash

sudo chown biqu:biqu /home/biqu/ -R
# sudo ntpdate stdtime.gov.hk

sync

cd /boot/scripts

#./extend_fs.sh &

./system_cfg.sh &

./connect_wifi.sh &

./csi.sh &

# regular sync to prevent data loss when direct power outage
./sync.sh &
