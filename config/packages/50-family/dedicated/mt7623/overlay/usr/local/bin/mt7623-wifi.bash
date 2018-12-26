#!/bin/bash
/usr/local/bin/wmt_loader &
sleep 3
/usr/local/bin/stp_uart_launcher -p /lib/firmware/mediatek &
sleep 3
/bin/echo A >/dev/wmtWifi
