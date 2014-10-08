### BEGIN INIT INFO
# Provides: Disable bright leds from Cubietruck
# Required-Start: $local_fs $network
# Required-Stop: $local_fs $remote_fs
# Default-Start: 2 3 4 5
# Default-Stop: 0 1 6
# Short-Description: CT Led disabler
# Description: Disable bright leds from cubietruck using /sys/class/leds
### END INIT INFO
#
# Turn off bright flashing LEDs!!
echo 0 > /sys/class/leds/blue:ph21:led1/brightness  
echo 0 > /sys/class/leds/orange:ph20:led2/brightness
echo 0 > /sys/class/leds/white:ph11:led3/brightness
echo 0 > /sys/class/leds/green:ph07:led4/brightness

