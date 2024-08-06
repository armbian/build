#!/bin/bash

v4l2-ctl -d /dev/video0 --set-ctrl=white_balance_automatic=1

insmod /usr/lib/modules/6.1.43-bigtree-cb2/kernel/drivers/input/touchscreen/raspits_ft5426.ko

