#!/bin/sh

### BEGIN INIT INFO
# Provides:		hostapd
# Required-Start:	$remote_fs
# Required-Stop:	$remote_fs
# Should-Start:		$network
# Should-Stop:
# Default-Start:	2 3 4 5
# Default-Stop:		0 1 6
# Short-Description:	Advanced IEEE 802.11 management daemon
# Description:		Userspace IEEE 802.11 AP and IEEE 802.1X/WPA/WPA2/EAP
#			Authenticator
### END INIT INFO

PATH=/sbin:/bin:/usr/sbin:/usr/bin
DAEMON_SBIN=/usr/sbin/hostapd
DAEMON_DEFS=/etc/default/hostapd
DAEMON_CONF=
NAME=hostapd
DESC="advanced IEEE 802.11 management"
PIDFILE=/run/hostapd.pid

[ -x "$DAEMON_SBIN" ] || exit 0
[ -s "$DAEMON_DEFS" ] && . /etc/default/hostapd
[ -n "$DAEMON_CONF" ] || exit 0

DAEMON_OPTS="-B -P $PIDFILE $DAEMON_OPTS $DAEMON_CONF"

. /lib/lsb/init-functions

case "$1" in
  start)
	log_daemon_msg "Starting $DESC" "$NAME"
	start-stop-daemon --start --oknodo --quiet --exec "$DAEMON_SBIN" \
		--pidfile "$PIDFILE" -- $DAEMON_OPTS >/dev/null
	log_end_msg "$?"
	;;
  stop)
	log_daemon_msg "Stopping $DESC" "$NAME"
	start-stop-daemon --stop --oknodo --quiet --exec "$DAEMON_SBIN" \
		--pidfile "$PIDFILE"
	log_end_msg "$?"
	;;
  reload)
  	log_daemon_msg "Reloading $DESC" "$NAME"
	start-stop-daemon --stop --signal HUP --exec "$DAEMON_SBIN" \
		--pidfile "$PIDFILE"
	log_end_msg "$?"
	;;
  restart|force-reload)
  	$0 stop
	sleep 8
	$0 start
	;;
  status)
	status_of_proc "$DAEMON_SBIN" "$NAME"
	exit $?
	;;
  *)
	N=/etc/init.d/$NAME
	echo "Usage: $N {start|stop|restart|force-reload|reload|status}" >&2
	exit 1
	;;
esac

exit 0
