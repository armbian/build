#!/bin/sh

# disable for mainline kernel
[ -f /boot/.next ] && exit

for x in $(cat /proc/cmdline); do
	case ${x} in
		m_bpp=*) export bpp=${x#*=} ;;
		hdmimode=*) export mode=${x#*=} ;;
		modeline=*) export modeline=${x#*=} ;;
	esac
done

HPD_STATE=/sys/class/amhdmitx/amhdmitx0/hpd_state
DISP_CAP=/sys/class/amhdmitx/amhdmitx0/disp_cap
DISP_MODE=/sys/class/display/mode

# if setenv nographics "1" in boot.ini then this needs to fail
if [ ! -f $DISP_MODE ]; then
	exit 0
fi

echo $mode > $DISP_MODE

common_display_setup() {
	M="0 0 $(($X - 1)) $(($Y - 1))"
	Y_VIRT=$(($Y * 2))
	fbset -fb /dev/fb0 -g $X $Y $X $Y_VIRT $bpp
	fbset -fb /dev/fb1 -g 32 32 32 32 32
	echo $mode > /sys/class/display/mode
	echo 0 > /sys/class/graphics/fb0/free_scale
	echo 1 > /sys/class/graphics/fb0/freescale_mode
	echo $M > /sys/class/graphics/fb0/free_scale_axis
	echo $M > /sys/class/graphics/fb0/window_axis
	echo 0 > /sys/class/graphics/fb1/free_scale
	echo 1 > /sys/class/graphics/fb1/freescale_mode
}

case $mode in
	custombuilt*)
		export X=$(echo $modeline | cut -f1 -d",")
		export Y=$(echo $modeline | cut -f2 -d",")
		;;
	480x320*)
		export X=480
		export Y=320
		;;
	480x800*)
		export X=480
		export Y=800
		;;
	480i* | 480p*)
		export X=720
		export Y=480
		;;
	576*)
		export X=720
		export Y=576
		;;
	720p*)
		export X=1280
		export Y=720
		;;
	1080*)
		export X=1920
		export Y=1080
		;;
	2160p*)
		export X=3840
		export Y=2160
		;;
	smpte24hz*)
		export X=3840
		export Y=2160
		;;
	640x480p60hz*)
		export X=640
		export Y=480
		;;
	800x480p60hz*)
		export X=800
		export Y=480
		;;
	800x600p60hz*)
		export X=800
		export Y=600
		;;
	1024x600p60hz*)
		export X=1024
		export Y=600
		;;
	1024x768p60hz*)
		export X=1024
		export Y=768
		;;
	1280x800p60hz*)
		export X=1280
		export Y=800
		;;
	1280x1024p60hz*)
		export X=1280
		export Y=1024
		;;
	1360x768p60hz*)
		export X=1360
		export Y=768
		;;
	1366x768p60hz*)
		export X=1366
		export Y=768
		;;
	1440x900p60hz*)
		export X=1440
		export Y=900
		;;
	1600x900p60hz*)
		export X=1600
		export Y=900
		;;
	1680x1050p60hz*)
		export X=1680
		export Y=1050
		;;
	1600x1200p60hz*)
		export X=1600
		export Y=1200
		;;
	1920x1200p60hz*)
		export X=1920
		export Y=1200
		;;
	2560x1080p60hz*)
		export X=2560
		export Y=1080
		;;
	2560x1440p60hz*)
		export X=2560
		export Y=1440
		;;
	2560x1600p60hz*)
		export X=2560
		export Y=1600
		;;
	3440x1440p60hz*)
		export X=3440
		export Y=1440
		;;
esac

# force 16bpp for 4k
[ "$Y" = "2160" ] && bpp=16

common_display_setup

# Console unblack
case $mode in
	*cvbs* | 480i* | 576i* | 1080i*)
		echo 0 > /sys/class/graphics/fb0/blank
		echo 1 > /sys/class/graphics/fb1/blank
		;;
	*)
		echo 0 > /sys/class/graphics/fb0/blank
		echo 0 > /sys/class/graphics/fb1/blank
		;;
esac
