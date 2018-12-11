cat <<EOF
#!/bin/sh
#
# ${FAMILY} post installation script
#

# read config
[ -f /etc/armbian-release ] && . /etc/armbian-release


exit 0
EOF
