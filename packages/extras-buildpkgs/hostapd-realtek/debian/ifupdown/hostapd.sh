#!/bin/sh

# Copyright (C) 2006-2009 Debian hostapd maintainers
# 	Faidon Liambotis <paravoid@debian.org>
#	Kel Modderman <kel@otaku42.de>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# On Debian GNU/Linux systems, the text of the GPL license,
# version 2, can be found in /usr/share/common-licenses/GPL-2.

# quit if we're called for lo
if [ "$IFACE" = lo ]; then
	exit 0
fi

if [ -n "$IF_HOSTAPD" ]; then
	HOSTAPD_CONF="$IF_HOSTAPD"
else
	exit 0
fi

HOSTAPD_BIN="/usr/sbin/hostapd"
HOSTAPD_PNAME="hostapd"
HOSTAPD_PIDFILE="/run/hostapd.$IFACE.pid"
HOSTAPD_OMIT_PIDFILE="/run/sendsigs.omit.d/hostapd.$IFACE.pid"

if [ ! -x "$HOSTAPD_BIN" ]; then
	exit 0
fi

if [ "$VERBOSITY" = "1" ]; then
	TO_NULL="/dev/stdout"
else
	TO_NULL="/dev/null"
fi

hostapd_msg() {
	case "$1" in
		verbose)
			shift
			echo "$HOSTAPD_PNAME: $@" > "$TO_NULL"
			;;
		stderr)
			shift
			echo "$HOSTAPD_PNAME: $@" > /dev/stderr
			;;
		*) ;;

	esac
}

test_hostapd_pidfile() {
	if [ -n "$1" ] && [ -f "$2" ]; then
		if start-stop-daemon --stop --quiet --signal 0 \
			--exec "$1" --pidfile "$2"; then
			return 0
		else
			rm -f "$2"
			return 1
		fi
	else
		return 1
	fi
}

init_hostapd() {
	HOSTAPD_OPTIONS="-B -P $HOSTAPD_PIDFILE $HOSTAPD_CONF"
	HOSTAPD_MESSAGE="$HOSTAPD_BIN $HOSTAPD_OPTIONS"

	test_hostapd_pidfile "$HOSTAPD_BIN" "$HOSTAPD_PIDFILE" && return 0

	hostapd_msg verbose "$HOSTAPD_MESSAGE"
	start-stop-daemon --start --oknodo --quiet --exec "$HOSTAPD_BIN" \
		--pidfile "$HOSTAPD_PIDFILE" -- $HOSTAPD_OPTIONS > "$TO_NULL"

	if [ "$?" -ne 0 ]; then
		return "$?"
	fi

	HOSTAPD_PIDFILE_WAIT=0
	until [ -s "$HOSTAPD_PIDFILE" ]; do
		if [ "$HOSTAPD_PIDFILE_WAIT" -ge 5 ]; then
			hostapd_msg stderr \
				"timeout waiting for pid file creation"
			return 1
		fi

		HOSTAPD_PIDFILE_WAIT=$(($HOSTAPD_PIDFILE_WAIT + 1))
		sleep 1
	done
	cat "$HOSTAPD_PIDFILE" > "$HOSTAPD_OMIT_PIDFILE"

	return 0
}

kill_hostapd() {
	HOSTAPD_MESSAGE="stopping $HOSTAPD_PNAME via pidfile: $HOSTAPD_PIDFILE"

	test_hostapd_pidfile "$HOSTAPD_BIN" "$HOSTAPD_PIDFILE" || return 0

	hostapd_msg verbose "$HOSTAPD_MESSAGE"
	start-stop-daemon --stop --oknodo --quiet --exec "$HOSTAPD_BIN" \
		--pidfile "$HOSTAPD_PIDFILE" > "$TO_NULL"

	[ "$HOSTAPD_OMIT_PIDFILE" ] && rm -f "$HOSTAPD_OMIT_PIDFILE"
}

case "$MODE" in
	start)
		case "$PHASE" in
			pre-up)
				init_hostapd || exit 1
				;;
			*)
				hostapd_msg stderr "unknown phase: \"$PHASE\""
				exit 1
				;;
		esac
		;;
	stop)
		case "$PHASE" in
			post-down)
				kill_hostapd
				;;
			*)
				hostapd_msg stderr "unknown phase: \"$PHASE\""
				exit 1
				;;
		esac
		;;
	*)
		hostapd_msg stderr "unknown mode: \"$MODE\""
		exit 1
		;;
esac

exit 0
