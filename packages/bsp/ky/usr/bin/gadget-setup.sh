#!/bin/bash
# In busybox ash, should use /bin/sh, but bianbu cannot use /bin/sh

name=`basename $0`
SCRIPT_VERSION="v0.5-SUPPORTROLESW"
CONFIG_FILE=$HOME/.usb_config

# USB Descriptors
VENDOR_ID="0x361c"
PRODUC_ID="0x0007"
MANUAF_STR="Ky"
PRODUC_STR="Ky Composite Device"
SERNUM_STR="20211102"
SN_PATH="/proc/device-tree/serial-number"
[ "$BOARD_SN" ] || BOARD_SN=$( [ -e $SN_PATH ] && tr -d '\000' < $SN_PATH )
[ "$BOARD_SN" ] && SERNUM_STR=$BOARD_SN

CONFIGFS=/sys/kernel/config
GADGET_PATH=$CONFIGFS/usb_gadget/ky
GFUNC_PATH=$GADGET_PATH/functions
GCONFIG=$GADGET_PATH/configs/c.1
[ "$USB_UDC" ] || USB_UDC=$(ls /sys/class/udc | awk "NR==1{print}")

# MSC Debug Ramdisk
RAMDISK_PATH=/var/sdcard
TMPFS_FOUND=`mount | grep tmpfs | grep -v devtmpfs | awk '{print $3}' | grep '/dev/shm' | wc -l`
[ "$TMPFS_FOUND" -eq 1 ] && RAMDISK_PATH=/dev/shm/sdcard
TMPFS_FOUND=`mount | grep tmpfs | grep -v devtmpfs | awk '{print $3}' | grep '/tmp' | wc -l`
[ "$TMPFS_FOUND" -eq 1 ] && RAMDISK_PATH=/tmp/sdcard
# SCSI Target
NAA="naa.6001405c3214b06a"
CORE_DIR=$CONFIGFS/target/core
USB_GDIR=$CONFIGFS/target/usb_gadget

# Global variables to record configured functions
MSC=disabled
UAS=disabled
UAS_ARG=""
MSC_ARG=""
ADB=disabled
UVC=disabled
RNDIS=disabled
FUNCTION_CNT=0
DEBUG=

usage()
{
	echo "$name usage: "
	echo ""
	echo -e "Support Select functions in $CONFIG_FILE:"
	echo -e "\tWrite <func>:<arg> line in $CONFIG_FILE, then run:"
	echo -e "\t$name [start|stop|reload|config]"
	echo -e "Or Select functions manually:"
	echo -e "\t$name <function1>(,<function2>...)"
	echo -e "Set USB connection:"
	echo -e "\t$name [pause|resume]"
	echo -e "\n$name info: show gadget info"
	echo -e "\nhint: udc is automatically selected, you can"
	echo -e "\toverride udc with env USB_UDC_IDX=[integer]/USB_UDC=[str]"
	echo -e "Set USB role-switch:"
	echo -e "\t$name role <rolesw-name> [host|device]"
	echo ""
	echo "Functions and arguments supported:"
	echo -e "\tmsc(:dev/file)  Mass Storage(Bulk-Only)."
	echo -e "\tuas(:dev/file)       Mass Storage(UASP)."
	echo -e "\tadb       Android Debug Bridge over USB."
	echo -e "\tuvc                              Webcam."
	echo -e "\trndis                RNDIS NIC function."
	echo -e "\nKy gadget-setup tool $SCRIPT_VERSION"
	echo ""
}

gadget_info()
{
	echo "$name: $1"
}

gadget_debug()
{
	[ $DEBUG ] && echo "$name: $1"
}

die()
{
	gadget_info "$1"
	exit 1
}

g_remove()
{
	[ -h $1 ] && rm -f $1
	[ -d $1 ] && rmdir $1
	[ -e $1 ] && rm -f $1
}

## MSC

msc_ramdisk_()
{
	# Debug Ramdisk for MSC without any argument
	gadget_info "msc: ramdisk: $RAMDISK_PATH/disk.img"
	mkdir -p $RAMDISK_PATH/sda
	dd if=/dev/zero of=$RAMDISK_PATH/disk.img bs=1M count=1038
	mkdosfs -F 32 $RAMDISK_PATH/disk.img
}

msc_config()
{
	gadget_debug "add a msc function instance"
	MSC_DIR=$GFUNC_PATH/mass_storage.usb0
	mkdir -p $MSC_DIR
	DEVICE=$1
	[ $DEVICE ] || DEVICE=$MSC_ARG
	# Create a backstore
	if [ -z "$DEVICE" ]; then
		echo "$name: no device specificed, select ramdisk as backstore"
		msc_ramdisk_
		echo "tmp files would be created in: $RAMDISK_PATH"
		echo "$RAMDISK_PATH/disk.img" >  $MSC_DIR/lun.0/file
	elif [ -b $DEVICE ]; then
		echo "$name: block device"
		echo "$DEVICE" > $MSC_DIR/lun.0/file
	else
		echo "$name: other path, regular file"
		echo "$DEVICE" > $MSC_DIR/lun.0/file
	fi

	echo 1 > $MSC_DIR/lun.0/removable
	echo 0 > $MSC_DIR/lun.0/nofua
}

msc_link()
{
	gadget_debug "add msc to usb config"
	ln -s $MSC_DIR $GCONFIG/mass_storage.usb0
}

msc_unlink()
{
	gadget_debug "remove msc from usb config"
	g_remove $GCONFIG/mass_storage.usb0
}

msc_clean()
{
	gadget_debug "clean msc"
	g_remove $GFUNC_PATH/mass_storage.usb0
	g_remove $RAMDISK_PATH/disk.img
	g_remove $RAMDISK_PATH/sda
}

## UAS

uas_config()
{
	gadget_debug "add a uas function instance"
	# Load the target modules and mount the add a file function instance system
	# Uncomment these if modules not built-in:
	# lsmod | grep -q configfs || modprobe configfs
	# lsmod | grep -q target_core_mod || modprobe target_core_mod
	DEVICE=$1
	[ $DEVICE ] || DEVICE=$UAS_ARG
	mkdir -p $GADGET_PATH/functions/tcm.0
	# Create a backstore
	if [ -z "$DEVICE" ]; then
		echo "$name: no device specificed, select rd_mcp as backstore"
		BACKSTORE_DIR=$CORE_DIR/rd_mcp_0/ramdisk
		mkdir -p $BACKSTORE_DIR
		# ramdisk
		echo rd_pages=200000 > $BACKSTORE_DIR/control
	elif [ -b $DEVICE ]; then
		echo "$name: block device, select iblock as backstore"
		BACKSTORE_DIR=$CORE_DIR/iblock_0/iblock
		mkdir -p $BACKSTORE_DIR
		echo "udev_path=${DEVICE}" > $BACKSTORE_DIR/control
	else
		echo "$name: other path, select fileio as backstore"
		BACKSTORE_DIR=$CORE_DIR/fileio_0/fileio
		mkdir -p $BACKSTORE_DIR
		DEVICE_SIZE=$(du -b $DEVICE | cut -f1)
		echo "fd_dev_name=${DEVICE},fd_dev_size=${DEVICE_SIZE}" > $BACKSTORE_DIR/control
		# echo 1 > $BACKSTORE_DIR/attrib/emulate_write_cache
	fi
	[ -n "$DEVICE" ] && umount $DEVICE
	echo 1 > $BACKSTORE_DIR/enable
	echo "$name: NAA of target: $NAA"
	# Create an NAA target and a target portal group (TPG)
	mkdir -p $USB_GDIR/$NAA/tpgt_1/
	echo "$name tpgt_1 has lun_0"
	# Create a LUN
	mkdir $USB_GDIR/$NAA/tpgt_1/lun/lun_0
	# Nexus initiator on target port 1 to $NAA
	echo $NAA > $USB_GDIR/$NAA/tpgt_1/nexus

	# Allow write access for non authenticated initiators
	# echo 0 > $USB_GDIR/$NAA/tpgt_1/attrib/demo_mode_write_protect
	ln -s $BACKSTORE_DIR $USB_GDIR/$NAA/tpgt_1/lun/lun_0/data
	#ln -s $BACKSTORE_DIR $USB_GDIR/$NAA/tpgt_1/lun/lun_0/virtual_scsi_port
	# echo 15 > $USB_GDIR/$NAA/tpgt_1/maxburst

	# Enable the target portal group, with 1 lun
	echo 1 > $USB_GDIR/$NAA/tpgt_1/enable
}

uas_link()
{
	gadget_debug "add uas to usb config"
	ln -s $GADGET_PATH/functions/tcm.0 $GCONFIG/tcm.0
}

uas_unlink()
{
	gadget_debug "remove uas from usb config"
	g_remove $GCONFIG/tcm.0
}

uas_clean()
{
	gadget_debug "clean uas"
	[ -d "$USB_GDIR/$NAA/tpgt_1/enable" ] && echo 0 > $USB_GDIR/$NAA/tpgt_1/enable
	g_remove $USB_GDIR/$NAA/tpgt_1/lun/lun_0/data
	g_remove $USB_GDIR/$NAA/tpgt_1/lun/lun_0/virtual_scsi_port
	g_remove $USB_GDIR/$NAA/tpgt_1/lun/lun_0
	g_remove $USB_GDIR/$NAA/tpgt_1/
	g_remove $USB_GDIR/$NAA/
	g_remove $USB_GDIR
	BACKSTORE_DIR=$CORE_DIR/iblock_0/iblock
	g_remove $BACKSTORE_DIR
	BACKSTORE_DIR=$CORE_DIR/fileio_0/fileio
	g_remove $BACKSTORE_DIR
	BACKSTORE_DIR=$CORE_DIR/rd_mcp_0/ramdisk
	g_remove $BACKSTORE_DIR
	g_remove $GADGET_PATH/functions/tcm.0
}

## ADB

adb_config()
{
	gadget_debug "add a adb function instance"
	mkdir $GFUNC_PATH/ffs.adb
}

adb_link()
{
	gadget_debug "add adb to usb config"
	ln -s $GFUNC_PATH/ffs.adb/ $GCONFIG/ffs.adb
	mkdir /dev/usb-ffs
	mkdir /dev/usb-ffs/adb
	mount -o uid=2000,gid=2000 -t functionfs adb /dev/usb-ffs/adb/
	#mkdir /dev/pts
	#mount -t devpts -o defaults,mode=644,ptmxmode=666 devpts /dev/pts
	adbd &
	sleep 1
}

adb_unlink()
{
	gadget_debug "remove adb from usb config"
	killall adbd
	g_remove $GCONFIG/ffs.adb
	[ -e /dev/usb-ffs/adb/ ] && umount /dev/usb-ffs/adb/
	#[ -e /dev/pts ] && umount /dev/pts
	#g_remove /dev/pts
	g_remove /dev/usb-ffs/adb
	g_remove /dev/usb-ffs
}

adb_clean()
{
	gadget_debug "clean adb"
	g_remove $GFUNC_PATH/ffs.adb
}

## UVC

### Setup streaming/ directory.
add_uvc_fmt_resolution()
{
	FORMAT=$1 # $1 format "uncompressed/y" / "mjpeg/m"
	UVC_DISPLAY_W=$2 # $2 Width
	UVC_DISPLAY_H=$3 # $3 Height
	FRAMERATE=$4 # $4 HIGH_FRAMERATE 0/1
	#https://docs.kernel.org/usb/gadget_uvc.html
	UVC_MJPEG_PRE_PATH=$GFUNC_PATH/$UVC_INSTANCE/streaming/$FORMAT
	UVC_FRAME_WDIR=${UVC_MJPEG_PRE_PATH}/${UVC_DISPLAY_H}p
	gadget_debug "UVC_FRAME_WDIR: $UVC_FRAME_WDIR"
	mkdir -p $UVC_FRAME_WDIR
	echo $UVC_DISPLAY_W > $UVC_FRAME_WDIR/wWidth
	echo $UVC_DISPLAY_H > $UVC_FRAME_WDIR/wHeight
	DW_MAX_VD_FB_SZ=$(( $UVC_DISPLAY_W * $UVC_DISPLAY_H * 2 ))
	if [ "$FORMAT"=="mjpeg/m" ]; then
		if [ -e "$CONFIG_FILE" ]; then
			# Attempt to parse the dwMaxVideoFrameBufferSize from ~/.uvcg_config
			parsed_value=$(grep "^mjpeg $UVC_DISPLAY_W $UVC_DISPLAY_H" ~/.uvcg_config | awk '{print $4}')
			# Check if the value was found; if not, keep the pre-calculated value
			if [ ! -z "$parsed_value" ]; then
				DW_MAX_VD_FB_SZ="$parsed_value"
			fi
			gadget_debug "format: $FORMAT, dw_max_video_fb_size: $DW_MAX_VD_FB_SZ"
		fi
	fi
	echo $DW_MAX_VD_FB_SZ > $UVC_FRAME_WDIR/dwMaxVideoFrameBufferSize
	# Many camera host app only shows the default framerate of a format in their list
	# So we set it here.
	if [ "$FRAMERATE" -eq 20 ]; then
		echo 500000 > $UVC_FRAME_WDIR/dwDefaultFrameInterval
	elif [ "$FRAMERATE" -eq 15 ]; then
		echo 666666 > $UVC_FRAME_WDIR/dwDefaultFrameInterval
	elif [ "$FRAMERATE" -eq 30 ]; then
		echo 333333 > $UVC_FRAME_WDIR/dwDefaultFrameInterval
	elif [ "$FRAMERATE" -eq 60 ]; then
		echo 166666 > $UVC_FRAME_WDIR/dwDefaultFrameInterval
	elif [ "$FRAMERATE" -eq 10 ]; then
		echo 1000000 > $UVC_FRAME_WDIR/dwDefaultFrameInterval
	fi
	# lowest framerate in this script is 10fps
	DW_MIN_BITRATE=$(( 10 * $DW_MAX_VD_FB_SZ * 8 ))
	DW_MAX_BITRATE=$(( $FRAMERATE * $DW_MAX_VD_FB_SZ * 8 ))
	if [ "$FORMAT"=="mjpeg/m" ]; then
		# MJPEG can compress the data at least 5:1,
		# let's set the ratio to 4
		DW_MIN_BITRATE=$(( $DW_MIN_BITRATE / 4 ))
		gadget_debug "format: $FORMAT, dw_min_br: $DW_MIN_BITRATE"
	fi
	echo $DW_MIN_BITRATE > $UVC_FRAME_WDIR/dwMinBitRate
	echo $DW_MAX_BITRATE > $UVC_FRAME_WDIR/dwMaxBitRate
	echo -e "\t$UVC_INSTANCE will support ${FORMAT} ${UVC_DISPLAY_W}x${UVC_DISPLAY_H}@${FRAMERATE}p"
	cat <<EOF > $UVC_FRAME_WDIR/dwFrameInterval
166666
333333
416667
500000
666666
1000000
EOF
}

destroy_one_uvc_format_()
{
	FORMAT=$1
	UVC_MJPEG_PRE_PATH=$GFUNC_PATH/$UVC_INSTANCE/streaming/$FORMAT
	for ppath in ${UVC_MJPEG_PRE_PATH}/*p; do
		g_remove $ppath
	done
}

destroy_all_uvc_format_()
{

	destroy_one_uvc_format_ uncompressed/y
	g_remove $GFUNC_PATH/$UVC_INSTANCE/streaming/uncompressed/y
	destroy_one_uvc_format_ mjpeg/m
	g_remove $GFUNC_PATH/$UVC_INSTANCE/streaming/mjpeg/m
}

create_uvc_link_()
{
	mkdir $GFUNC_PATH/$UVC_INSTANCE/streaming/header/h
	ln -s $GFUNC_PATH/$UVC_INSTANCE/streaming/mjpeg/m/ $GFUNC_PATH/$UVC_INSTANCE/streaming/header/h/m
	ln -s $GFUNC_PATH/$UVC_INSTANCE/streaming/uncompressed/y/ $GFUNC_PATH/$UVC_INSTANCE/streaming/header/h/y
	ln -s $GFUNC_PATH/$UVC_INSTANCE/streaming/header/h/ $GFUNC_PATH/$UVC_INSTANCE/streaming/class/fs
	ln -s $GFUNC_PATH/$UVC_INSTANCE/streaming/header/h/ $GFUNC_PATH/$UVC_INSTANCE/streaming/class/hs
	ln -s $GFUNC_PATH/$UVC_INSTANCE/streaming/header/h/ $GFUNC_PATH/$UVC_INSTANCE/streaming/class/ss
	mkdir $GFUNC_PATH/$UVC_INSTANCE/control/header/h
	ln -s $GFUNC_PATH/$UVC_INSTANCE/control/header/h/ $GFUNC_PATH/$UVC_INSTANCE/control/class/fs/
	ln -s $GFUNC_PATH/$UVC_INSTANCE/control/header/h/ $GFUNC_PATH/$UVC_INSTANCE/control/class/ss/
}

destroy_uvc_link_()
{
	g_remove $GFUNC_PATH/$UVC_INSTANCE/control/class/fs/h
	g_remove $GFUNC_PATH/$UVC_INSTANCE/control/class/ss/h
	g_remove $GFUNC_PATH/$UVC_INSTANCE/control/header/h
	g_remove $GFUNC_PATH/$UVC_INSTANCE/streaming/class/ss/h
	g_remove $GFUNC_PATH/$UVC_INSTANCE/streaming/class/hs/h
	g_remove $GFUNC_PATH/$UVC_INSTANCE/streaming/class/fs/h
	g_remove $GFUNC_PATH/$UVC_INSTANCE/streaming/header/h/m
	g_remove $GFUNC_PATH/$UVC_INSTANCE/streaming/header/h/y
	g_remove $GFUNC_PATH/$UVC_INSTANCE/streaming/header/h
}

destroy_uvc_()
{
	destroy_uvc_link_
	destroy_all_uvc_format_
	g_remove $GFUNC_PATH/$UVC_INSTANCE
}

set_uvc_maxpacket_()
{
	MAX=$1 ## $1 1024/2048/3072
	BURST=$2 ## $2 1-15
	FUNCTION=$GFUNC_PATH/$UVC_INSTANCE
	echo -e "\t$UVC_INSTANCE set streaming_maxpacket=$MAX, streaming_maxburst=$BURST"
	echo $MAX > $FUNCTION/streaming_maxpacket
	echo $BURST  > $FUNCTION/streaming_maxburst
}

uvc_config()
{
	UVC_INSTANCE=uvc.0
	gadget_info "Adding a uvc function instance $UVC_INSTANCE..."
	mkdir -p $GFUNC_PATH/$UVC_INSTANCE
	# add_uvc_fmt_resolution <format> <width> <height> <framerate>
	add_uvc_fmt_resolution uncompressed/y 320 240 30
	add_uvc_fmt_resolution uncompressed/y 640 360 30
	add_uvc_fmt_resolution uncompressed/y 640 480 30
	add_uvc_fmt_resolution uncompressed/y 640 640 30
	add_uvc_fmt_resolution uncompressed/y 1280 720 30
	add_uvc_fmt_resolution uncompressed/y 1920 1080 30
	add_uvc_fmt_resolution uncompressed/y 3840 2160 30
	add_uvc_fmt_resolution mjpeg/m 640 360 30
	add_uvc_fmt_resolution mjpeg/m 640 480 30
	add_uvc_fmt_resolution mjpeg/m 1280 720 30
	add_uvc_fmt_resolution mjpeg/m 1920 1080 30
	add_uvc_fmt_resolution mjpeg/m 3840 2160 30
	set_uvc_maxpacket_ 3072 15
	create_uvc_link_
}

uvc_link()
{
	gadget_debug "add uvc to usb config, unlike adb, you have to run ur own uvc-gadget app"
	UVC_INSTANCE=uvc.0
	ln -s $GFUNC_PATH/$UVC_INSTANCE/ $GCONFIG/$UVC_INSTANCE
}

uvc_unlink()
{
	gadget_debug "remove uvc from usb config"
	UVC_INSTANCE=uvc.0
	g_remove $GCONFIG/$UVC_INSTANCE
}

uvc_clean()
{
	gadget_debug "clean uvc"
	UVC_INSTANCE=uvc.0
	destroy_uvc_
}

## RNDIS

rndis_config()
{
	OVERRIDE_VENDOR_FOR_WINDOWS=$1
	# create function instance
	# functions/<f_function allowed>.<instance name>
	# f_function allowed: rndis
	mkdir -p $GFUNC_PATH/rndis.0
}

rndis_link()
{

	# Add Microsoft os descriptors to ensure
	# Windows recognize us as an RNDIS compatible device
	# thus no need to install driver manually.
	# Verified on Windows 10.
	echo 0xEF > $GADGET_PATH/bDeviceClass
	echo 0x02 > $GADGET_PATH/bDeviceSubClass
	echo 0x01 > $GADGET_PATH/bDeviceProtocol
	echo 1 > $GADGET_PATH/os_desc/use
	echo 0x1 > $GADGET_PATH/os_desc/b_vendor_code
	echo "MSFT100" > $GADGET_PATH/os_desc/qw_sign
	mkdir -p $GFUNC_PATH/rndis.0/os_desc/interface.rndis
	echo RNDIS > $GFUNC_PATH/rndis.0/os_desc/interface.rndis/compatible_id
	echo 5162001 > $GFUNC_PATH/rndis.0/os_desc/interface.rndis/sub_compatible_id
	ln -s $GADGET_PATH/configs/c.1 $GADGET_PATH/os_desc/c.1

	ln -s $GFUNC_PATH/rndis.0 $GCONFIG
	HOST_ADDR=`cat $GFUNC_PATH/rndis.0/host_addr`
	DEV_ADDR=`cat $GFUNC_PATH/rndis.0/dev_addr`
	IFNAME=`cat $GFUNC_PATH/rndis.0/ifname`
	gadget_info "rndis function enabled, mac(h): $HOST_ADDR, mac(g): $DEV_ADDR, ifname: $IFNAME."
	gadget_info "execute ifconfig $IFNAME up to enable rndis iface."
}

rndis_unlink()
{
	[ -e $GFUNC_PATH/rndis.0/ifname ] && ifconfig `cat $GFUNC_PATH/rndis.0/ifname` down
	g_remove $GCONFIG/rndis.0
}

rndis_clean()
{
	g_remove $GFUNC_PATH/rndis.0
}

## MTP

mtp_config()
{
	die "MTP Not Supported yet."
}

mtp_link()
{
	die "MTP Not Supported yet."
}

mtp_unlink()
{
	die "MTP Not Supported yet."
}

mtp_clean()
{
   die "MTP Not Supported yet."
}

## GADGET
no_udc()
{
	gadget_info "Echo none to udc"
	gadget_info "We are now trying to echo None to UDC......"
	[ -e $GADGET_PATH/UDC ] || die "gadget not configured yet"
	[ `cat $GADGET_PATH/UDC` ] && echo "" > $GADGET_PATH/UDC
	gadget_info "echo none to UDC successfully done"
	gadget_info "echo none to UDC done."
}

give_hint_to_which_have_udc_()
{
	for config_path in "/sys/kernel/config/usb_gadget/"*; do
		udc_path="$config_path/UDC"
		is_here=$(cat $udc_path | grep $selected_udc | wc -l)
		if [ "$is_here" -gt 0 ]; then
			gadget_info "ERROR: Your udc is occupied by: $udc_path"
		fi
	done
}

echo_udc()
{
	[ -e $GADGET_PATH/UDC ] || die "gadget not configured yet"
	[ `cat $GADGET_PATH/UDC` ] && die "UDC `cat $GADGET_PATH/UDC` already been set"
	if [ "$USB_UDC_IDX" ]; then
		selected_udc=$(ls /sys/class/udc | awk "NR==$USB_UDC_IDX{print}")
	else
		selected_udc=$USB_UDC
		gadget_info "Selected udc by name: $selected_udc"
		gadget_info "We are now trying to echo $selected_udc to UDC......"
	fi
	our_udc_occupied=$(cat /sys/kernel/config/usb_gadget/*/UDC | grep $selected_udc | wc -l)
	if [ "$our_udc_occupied" -gt 0 ]; then
		give_hint_to_which_have_udc_
		gadget_info "ERROR: configfs preserved, run $name resume after conflict resolved"
		exit 127
	fi
	echo  $selected_udc > $GADGET_PATH/UDC
	gadget_info "echo $selected_udc to UDC done"
}

gconfig()
{
	gadget_info "config $VENDOR_ID/$PRODUC_ID/$SERNUM_STR/$MANUAF_STR/$PRODUC_STR."
	mountpoint -q /sys/kernel/config || mount -t configfs none /sys/kernel/config
	[ -e $GADGET_PATH ] && die "ERROR: gadget already configured, should run stop first"
	mkdir $GADGET_PATH
	echo $VENDOR_ID > $GADGET_PATH/idVendor
	echo $PRODUC_ID > $GADGET_PATH/idProduct
	mkdir $GADGET_PATH/strings/0x409
	echo $SERNUM_STR > $GADGET_PATH/strings/0x409/serialnumber
	echo $MANUAF_STR > $GADGET_PATH/strings/0x409/manufacturer
	echo $PRODUC_STR > $GADGET_PATH/strings/0x409/product
	mkdir $GCONFIG
	echo 0xc0 > $GCONFIG/bmAttributes
	echo 500 > $GCONFIG/MaxPower
	mkdir $GCONFIG/strings/0x409
	# Windows rndis driver requires rndis to be the first interface
	[ $RNDIS = okay ] && rndis_config
	[ $MSC = okay ] &&  msc_config
	[ $UAS = okay ] &&  uas_config
	[ $ADB = okay ] &&  adb_config
	[ $UVC = okay ] &&  uvc_config
}

gclean()
{
	[ -e $GADGET_PATH/UDC ] || die "gadget not configured, no need to clean"
	msc_clean
	uas_clean
	rndis_clean
	adb_clean
	uvc_clean
	# Remove string in gadget
	gadget_info "remove strings of $GADGET_PATH."
	g_remove $GADGET_PATH/strings/0x409
	# Remove gadget
	gadget_info "remove $GADGET_PATH."
	g_remove $GADGET_PATH
}

glink()
{
	[ $RNDIS  = okay ] && rndis_link
	[ $MSC  = okay ] && msc_link
	[ $UAS  = okay ] && uas_link
	[ $ADB  = okay ] && adb_link
	[ $UVC  = okay ] && uvc_link
}

gunlink()
{
	[ -e $GADGET_PATH/UDC ] || die "gadget not configured yet"
	rndis_unlink
	msc_unlink
	uas_unlink
	adb_unlink
	uvc_unlink
	# Remove strings:
	gadget_info "remove strings of c.1."
	g_remove $GCONFIG/strings/0x409
	# Remove config:
	gadget_info "remove configs c.1."
	g_remove $GCONFIG
}

select_one()
{
	func=$1

	if [[ "$func" == "#"* ]];then
		gadget_debug "met hashtag, skip"
		return
	fi

	if [[ "$func" == USB_UDC=* ]]; then
		USB_UDC=$(echo $func | awk -F= '{print $2}')
		gadget_info "Set USB_UDC to $USB_UDC from config file"
		return
	fi

	case "$func" in
		msc*|mass*|storage*)
			MSC=okay
			MSC_ARG=$(echo $func | awk -F: '{print $2}')
			;;
		"uvc"|"video|webcam")
			UVC=okay
			;;
		uas*|uasp*)
			UAS=okay
			UAS_ARG=$(echo $func | awk -F: '{print $2}')
			;;
		"rndis"|"network"|"net"|"if")
			RNDIS=okay
			;;
		"mtp")
			MTP=okay
			;;
		"adb"|"fastboot"|"adbd")
			ADB=okay
			;;
		*)
			die "not supported function: $func"
			;;
	esac
	gadget_info "Selected function $func"
	let FUNCTION_CNT=FUNCTION_CNT+1
}

handle_select() {
	local input_str=$1
	local IFS=,  # split via comma
	OLDIFS=$IFS  # split functions
	IFS=,
	for token in $input_str; do
		[ $DEBUG ]
		select_one $token
	done
	IFS=$OLDIFS
}

parse_config()
{
	[ -e  $CONFIG_FILE ] || die "$CONFIG_FILE not found, abort."
	while read line
	do
		select_one $line
	done < $CONFIG_FILE
}

gstart()
{
	gconfig
	glink
	[ $FUNCTION_CNT -lt 1 ] && die "No function selected, will not pullup."
	echo_udc $1
}

gstop()
{
	no_udc
	gunlink
	gclean
}

gen_role_switch_list()
{
	ROLE_SWITCH_LIST=""
	# Find those names with dwc3 in the dir: /sys/kernel/debug/usb
	for dir in /sys/kernel/debug/usb/*; do
		if [[ -d "$dir" && "$dir" == *"dwc3"* ]]; then
			ROLE_SWITCH_LIST="$(basename "$dir") $ROLE_SWITCH_LIST"
		fi
	done
	# Find role-switch location in dir: /sys/class/usb_role/xxx-role-switch/ with a role file existing
	for role_switch in /sys/class/usb_role/*-role-switch/; do
		if [[ -d "$role_switch" && -f "${role_switch}role" ]]; then
			ROLE_SWITCH_LIST="$(basename "$role_switch") $ROLE_SWITCH_LIST"
		fi
	done
}

print_role_switch_info()
{
	gen_role_switch_list
	echo -n "Available DRDs: "
	echo "$ROLE_SWITCH_LIST"
}

# Function to set the role for a specific role switch
set_role() {
	if [ "$#" -lt 1 ]; then
		echo "Usage: $name set_role <role_switch> [host|device]"
		echo -e "\t$name set_role <role_switch>=[host|device]"
		return 1
	fi
	local input="$*"
	local role_switch
	local role
	# Use awk to parse the input
	echo "$input" | awk -F'[ =]' '{
		if (NF == 2) {
			role_switch = $1;
			role = $2;
		} else if (NF == 1) {
			role_switch = $1;
			role = "NONE";  # Default role
		} else if (NF >= 3) {
			role_switch = $1;
			role = $3;
			sub(/=[^=]+$/, "", role_switch);  # Remove the =part from role_switch
		}
		print role_switch, role
	}' | {
		read role_switch role
		if [[ "$role_switch" == *"-role-switch" ]]; then
			# It's a role-switch, verify its existence
			local role_switch_path="/sys/class/usb_role/$role_switch/role"
			if [ ! -e "$role_switch_path" ]; then
				gadget_info "Error: Role switch '$role_switch' does not exist."
				return 1
			fi
			if [[ "$role" == "NONE" ]]; then
				role=$(cat $role_switch_path)
				gadget_info "Role for role switch '$role_switch' is currently '$role'."
			else
				echo "$role" > "$role_switch_path"
				gadget_info "Role for'$role_switch' set to '$role'."
			fi
		else
			# It's a controller type, verify its existence
			local usb_controller_path="/sys/kernel/debug/usb/$role_switch/mode"
			if [ ! -e "$usb_controller_path" ]; then
				gadget_info "Error: controller support mode switch '$role_switch' does not exist."
				return 1
			fi
			if [[ "$role" == "NONE" ]]; then
				role=$(cat $usb_controller_path)
				gadget_info "Mode for '$role_switch' is currently '$role'."
			else
				echo "$role" > "$usb_controller_path"
				sleep 1
				role_after="$(cat $usb_controller_path)"
				if [[ "$role" != "$role_after" ]]; then
					gadget_info "Error: controller '$role_switch' doesn't support mode switch!!!"
					role="$(cat $usb_controller_path)"
					gadget_info "Mode for Controller '$role_switch' is currently '$role'."
				else
					gadget_info "Mode for controller '$role_switch' set to '$role'."
				fi
			fi
		fi
		print_role_switch_info
	}
}

print_info()
{
	echo "Ky gadget-setup tool $SCRIPT_VERSION"
	echo
	echo "Board Model: `tr -d '\000' < /proc/device-tree/model`"
	echo "Serial Number: $SERNUM_STR"
	echo "General Config Info: $VENDOR_ID/$PRODUC_ID/$MANUAF_STR/$PRODUC_STR."
	echo "Config File Path: $CONFIG_FILE"
	echo "MSC Ramdisk Path (selected from tmpfs mounting point): $RAMDISK_PATH"
	echo "UASP SCSI NAA: $NAA"
	echo "UASP Target Dir: $USB_GDIR"
	echo "Available UDCs: `ls  -1 /sys/class/udc/ |  tr '\n' ' '`"
	print_role_switch_info
	echo
}

## MAIN
case "$1" in
	stop|clean)
		gstop
		;;
	restart|reload)
		gstop
		parse_config
		gstart
		;;
	start)
		parse_config
		gstart $2
		;;
	pause|disconnect)
		no_udc
		;;
	resume|connect)
		USBDEV_IDX=$2
		echo_udc
		;;
	config)
		vi $CONFIG_FILE
		[ -e $CONFIG_FILE ] && gadget_info ".usb_config updated"
		;;
	help)
		usage
		;;
	info)
		print_info
		;;
	set_role|role_switch|role|rolesw|mode|switch|dr_mode)
		shift
		set_role "$@"
		;;
	[a-z]*)
		handle_select $1
		gstart $2
		;;
	*)
		usage
		;;
esac

exit $?
