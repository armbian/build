#!/bin/bash

deviceinfo_name="USB Gadget Network"
deviceinfo_manufacturer="Armbian"
#deviceinfo_usb_idVendor=
#deviceinfo_usb_idProduct=
#deviceinfo_usb_serialnumber=

setup_usb_network_configfs() {
	# See: https://www.kernel.org/doc/Documentation/usb/gadget_configfs.txt
	CONFIGFS=/sys/kernel/config/usb_gadget

	if ! [ -e "$CONFIGFS" ]; then
		echo "  $CONFIGFS does not exist, skipping configfs usb gadget"
		return
	fi

	if [ -e "$CONFIGFS/g1" ]; then
		echo "  $CONFIGFS/g1 already exists, skipping configfs usb gadget"
		return
	fi

	# Default values for USB-related deviceinfo variables
	usb_idVendor="${deviceinfo_usb_idVendor:-0x1D6B}"   # Linux Foundation
	usb_idProduct="${deviceinfo_usb_idProduct:-0x0103}" # NCM (Ethernet) Gadget
	usb_serialnumber="${deviceinfo_usb_serialnumber:-0123456789}"
	usb_network_function="ncm.usb0"

	echo "  Setting up an USB gadget through configfs"
	# Create an usb gadet configuration
	mkdir $CONFIGFS/g1 || echo "  Couldn't create $CONFIGFS/g1"
	echo "$usb_idVendor" > "$CONFIGFS/g1/idVendor"
	echo "$usb_idProduct" > "$CONFIGFS/g1/idProduct"
	echo 0x0100 > "$CONFIGFS/g1/bcdDevice"
	echo 0x0200 > "$CONFIGFS/g1/bcdUSB"

	# Create english (0x409) strings
	mkdir $CONFIGFS/g1/strings/0x409 || echo "  Couldn't create $CONFIGFS/g1/strings/0x409"

	# shellcheck disable=SC2154
	echo "$deviceinfo_manufacturer" > "$CONFIGFS/g1/strings/0x409/manufacturer"
	echo "$usb_serialnumber" > "$CONFIGFS/g1/strings/0x409/serialnumber"
	# shellcheck disable=SC2154
	echo "$deviceinfo_name" > "$CONFIGFS/g1/strings/0x409/product"

	# Create network function.
	mkdir $CONFIGFS/g1/functions/"$usb_network_function" ||
		echo "  Couldn't create $CONFIGFS/g1/functions/$usb_network_function"

	# Create configuration instance for the gadget
	mkdir $CONFIGFS/g1/configs/c.1 ||
		echo "  Couldn't create $CONFIGFS/g1/configs/c.1"
	echo 250 > $CONFIGFS/g1/configs/c.1/MaxPower
	mkdir $CONFIGFS/g1/configs/c.1/strings/0x409 ||
		echo "  Couldn't create $CONFIGFS/g1/configs/c.1/strings/0x409"
	echo "NCM Configuration" > $CONFIGFS/g1/configs/c.1/strings/0x409/configuration ||
		echo "  Couldn't write configration name"

	# Link the network instance to the configuration
	ln -s $CONFIGFS/g1/functions/"$usb_network_function" $CONFIGFS/g1/configs/c.1 ||
		echo "  Couldn't symlink $usb_network_function"

	# Check if there's an USB Device Controller
	if [ -z "$(ls /sys/class/udc)" ]; then
		echo "  No USB Device Controller available"
		return
	fi

	# Link the gadget instance to an USB Device Controller. This activates the gadget.
	# See also: https://github.com/postmarketOS/pmbootstrap/issues/338
	# shellcheck disable=SC2005
	echo "$(ls /sys/class/udc)" > $CONFIGFS/g1/UDC || echo "  Couldn't write UDC"
}

set_usbgadget_ipaddress() {
	local host_ip="${unudhcpd_host_ip:-172.16.42.1}"
	local client_ip="${unudhcpd_client_ip:-172.16.42.2}"
	unudhcpd_pid=$(pgrep unudhcpd)
	if [ "x$unudhcpd_pid" != "x" ]; then
		echo "unudhcpd process already exists, skip setting usb gadget ip, unudhcpd_pid is $unudhcpd_pid"
		return
	fi
	echo "Starting dnsmasq with server ip $host_ip, client ip: $client_ip"
	# Get usb interface
	INTERFACE=""
	ip a add "${host_ip}/255.255.0.0" dev usb0 2> /dev/null && ip link set usb0 up && INTERFACE=usb0
	if [ -z $INTERFACE ]; then
		ip a add "${host_ip}/255.255.0.0" dev eth0 2> /dev/null && eth0 && INTERFACE=eth0
	fi

	if [ -z $INTERFACE ]; then
		echo "  Could not find an interface to run a dhcp server on"
		echo "  Interfaces:"
		ip link
		return
	fi

	echo "  Using interface $INTERFACE"
	echo "  Starting the DHCP daemon"
	ip a show $INTERFACE > /var/log/unudhcpd.log
	nohup /usr/bin/unudhcpd -i "$INTERFACE" -s "$host_ip" -c "$client_ip" >> /var/log/unudhcpd.log 2>&1 &
	return
}
setup_usb_network_configfs
set_usbgadget_ipaddress
