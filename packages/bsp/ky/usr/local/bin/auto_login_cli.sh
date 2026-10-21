#!/bin/bash

if [[ -z $1 ]]; then
	user=root
else
	user=$1
fi

[[ -d /lib/systemd/system/getty@.service.d/ ]] && rm /lib/systemd/system/getty@.service.d/ -rf
[[ -f /lib/systemd/system/serial-getty@.service.d/override.conf ]] && rm /lib/systemd/system/serial-getty@.service.d/override.conf -f
[[ -d /etc/systemd/system/getty@.service.d/ ]] && rm /etc/systemd/system/getty@.service.d/ -rf
[[ -f /etc/systemd/system/serial-getty@.service.d/override.conf ]] && rm /etc/systemd/system/serial-getty@.service.d/override.conf -f

if [[ $1 == "-d" ]]; then
	exit
fi

mkdir -p /etc/systemd/system/getty@.service.d/
mkdir -p /etc/systemd/system/serial-getty@.service.d/
cat <<-EOF >  \
/etc/systemd/system/serial-getty@.service.d/override.conf
[Service]
ExecStartPre=/bin/sh -c 'exec /bin/sleep 10'
ExecStart=
ExecStart=-/sbin/agetty --noissue --autologin ${user} %I \$TERM
Type=idle
EOF
cp /etc/systemd/system/serial-getty@.service.d/override.conf  \
/etc/systemd/system/getty@.service.d/override.conf
