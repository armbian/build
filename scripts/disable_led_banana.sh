### BEGIN INIT INFO
# Provides: Disable blinking leds from Banana
# Required-Start: $local_fs $network
# Required-Stop: $local_fs $remote_fs
# Default-Start: 2 3 4 5
# Default-Stop: 0 1 6
# Short-Description: Banana Led disabler
# Description: Disable bright leds using /sys/class/leds
### END INIT INFO
#
# Turn off bright flashing LEDs!!
echo none > /sys/class/leds/green\:ph24\:led1/trigger

