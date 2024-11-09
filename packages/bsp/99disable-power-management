#!/bin/sh
case "$2" in
	up) iw dev $1 set power_save off || true ;;
	down) iw dev $1 set power_save on || true ;;
esac
