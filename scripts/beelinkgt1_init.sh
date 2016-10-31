#!/bin/sh

for x in $(cat /proc/cmdline); do
        case ${x} in
                m_bpp=*) export bpp=${x#*=} ;;
                hdmimode=*) export mode=${x#*=} ;;
        esac
done

HPD_STATE=/sys/class/amhdmitx/amhdmitx0/hpd_state
DISP_CAP=/sys/class/amhdmitx/amhdmitx0/disp_cap
DISP_MODE=/sys/class/display/mode

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
}

case $mode in
		480*)
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
		1920x1200p60hz*)
			export X=1920
			export Y=1200
			;;
esac

common_display_setup

# Console unblack
echo 0 > /sys/class/graphics/fb0/blank
#echo 0 > /sys/class/graphics/fb1/blank

