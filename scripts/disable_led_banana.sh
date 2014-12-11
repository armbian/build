#! /bin/bash
### BEGIN INIT INFO
# Provides:             Disable blinking leds from Banana
# Required-Start:       $local_fs $network 
# Required-Stop:        $local_fs $remote_fs 
# Default-Start:        2 3 4 5
# Default-Stop:         0 1 6
# Short-Description:    Banana Led disabler
### END INIT INFO

case "$1" in
    start)
        echo none > /sys/class/leds/green\:ph24\:led1/trigger
;;
    *)
        ## If no parameters are given, print which are avaiable.
        echo "Usage: $0 {start}"
        exit 1
        ;;
esac
