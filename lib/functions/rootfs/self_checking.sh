#!/bin/bash

sleep 2
clear='\033[0m'
red='\033[31m'
green='\033[32m'
yellow='\033[33m'

network_timeout=15

hdmi_status="$red ERROR! $clear"
ov5647_status="$red ERROR! $clear"
manta_usb_status="$red No Manta USB! $clear"
ext_usb_status="$red No ext USB USB! $clear"
wifi_status="$red ERROR! $clear"
phy_status="$red ERROR! $clear"
ram_status="$red ERROR! $clear"
emmc_status="$red ERROR! $clear"

cfg_file=/boot/system.cfg
log_file=/etc/scripts/wifi.log
IFS=\"

wifi_path="/etc/NetworkManager/system-connections/"
source "/boot/armbianEnv.txt"
function connect_wifi() {
    # whether there is configured wifi in the history
    if [[ `sudo nmcli c s | grep wifi |  awk '{ for(i=NF-2; i<=NF; i++){ $i="" }; print $0 }'` =~ "${WIFI_SSID}" ]] ; then
        set_wifi_path="${wifi_path}${WIFI_SSID}.nmconnection"
        if [[ -e ${set_wifi_path} ]]; then               #awk 的 F参数用于指定字段的分隔符
            psk=`sudo cat ${set_wifi_path} | grep ^psk | awk -F '=' '{print $2}'`
            if [[ ${psk} == $WIFI_PASSWD ]]; then
                # both ssid & passwd matched.                                           NF  指的是当前记录中的字段数量
                sys_now_wifi=`sudo nmcli c s --active | grep wlan0 | awk '{ for(i=NF-2; i<=NF; i++){ $i="" }; print $0 }' | awk '{t=length($0)}END{print substr($0, 0, t-3)}'`
                if [[ ${sys_now_wifi} != $WIFI_SSID ]]; then
                    sudo nmcli c up ${WIFI_SSID}
                    echo " ===> SSID & PSK is same as history, switch to: $WIFI_SSID " >> $log_file
                fi
                echo " ===> Now is: $WIFI_SSID, need not to do anything" >> $log_file
                return 0
            else
                # psk don't match, remove and reconnect.
                sudo nmcli c delete ${WIFI_SSID}
                echo " ===> Remove all: $WIFI_SSID " >> $log_file
            fi
        else
            # remove all WIFI_SSID info (Theoretically, never execute to here).
            sudo nmcli c delete ${WIFI_SSID}
            echo " ===> Remove all: $WIFI_SSID " >> $log_file
        fi
    fi

    # connect to the new wifi  #扫描 wifi设备   右侧是否是左侧的子集即$WIFI_SSID是否是的扫描出来的wifi子集？
    if [[ `sudo nmcli device wifi list` =~ $WIFI_SSID ]]
    then          #连接wifi设备  连接成功返回0
        if [[ ! `sudo nmcli dev wifi connect $WIFI_SSID password $WIFI_PASSWD ifname $wlan` =~ "successfully" ]]
        then
            echo " ===> Specify the WPA encryption method: $WIFI_SSID " >> $log_file
            sudo nmcli c modify $WIFI_SSID wifi-sec.key-mgmt wpa-psk
            sudo nmcli dev wifi connect $WIFI_SSID password $WIFI_PASSWD ifname $wlan
        fi
    else
        echo " ===> Hide wifi_ssid: $WIFI_SSID " >> $log_file
        sudo nmcli c add type wifi con-name $WIFI_SSID ifname $wlan ssid $WIFI_SSID
        sudo nmcli c modify $WIFI_SSID wifi-sec.key-mgmt wpa-psk wifi-sec.psk $WIFI_PASSWD
        sudo nmcli c up $WIFI_SSID
    fi
}

function tab_format(){
    f_name=$1
    [ $# == 1 ] && echo "$(printf "%-$1s" "")"
    [ $# == 2 ] && echo "$(printf "%-$2s" "$f_name")"
    unset f_name
}

function check_hdmi() {
    echo -e "$yellow ==== Checking HDMI... ====$clear"

    if [ -e "/dev/fb0" ]; then
        hdmi_status="$green OK! $clear"
    fi
    echo -e "HDMI:$hdmi_status "
}

function check_ov5647() {
    echo -e "$yellow ==== Checking OV5647... ====$clear"

    if [ -e "/dev/v4l-subdev3" ]; then
        ov5647_status="$green OK! $clear"
    fi
    echo -e "OV5647:$ov5647_status "
}

function check_usb() {
    echo -e "$yellow ==== Checking USB... ====$clear"

    manta_usb=0
    if [ -d "/dev/serial/by-id/" ]; then
        manta_id=`ls /dev/serial/by-id/`
        manta_usb=1
        echo -e "Manta USB ID: $manta_id"
        manta_usb_status="$green OK! $clear"
    fi

    usb_device=`lsusb | grep -v "Linux Foundation" | grep -v "Terminus"` # remove H616 usb hub(Linux Foundation) and onboard usb hub FE1.1s(Terminus Technology)
    usb_count=`lsusb | grep -v "Linux Foundation" | grep -v "Terminus" |  awk '{print NR}' | tail -n1`
    ext_usb_count=$[${usb_count}-${manta_usb}] # remove Manta USB because it display alone
    echo -e "${usb_device}"
    echo -e "Manta USB: $manta_usb_status"
    if [[ ${ext_usb_count} > 0 ]]; then
        ext_usb_status="$green $ext_usb_count $clear"
        echo -e "There is $green $ext_usb_count $clear ext USB device(not including Manta USB)"
    fi
}

function check_wlan0() {
    echo -e "$yellow ==== Checking WIFI... ====$clear"

    timeout=0
    while [ -z "`dmesg | grep 'wlan0: link becomes ready'`" ]; do
        echo "wlan0 wait for up"
        sleep 1
        timeout=`expr $timeout + 1`
        if [[ ${timeout} -eq ${network_timeout} ]]; then
            echo "wlan0 timeout..."
            break
        fi
    done

    sudo nmcli radio wifi on
    timeout=0
    while [ "`nmcli radio wifi`" != "enabled" ]; do
        sudo nmcli radio wifi on
        echo "wifi wait for on"
        sleep 1
        timeout=`expr $timeout + 1`
        if [[ ${timeout} -eq ${network_timeout} ]]; then
            echo "wifi timeout..."
            break
        fi
    done

    source $cfg_file
    connect_wifi
    timeout=0
    while [ 1 ]; do
        if [[ "`nmcli dev status | grep ${WIFI_SSID}`" =~ "connected" ]]; then
            break
        fi
        echo "wifi wait for connecting..."
        sleep 1
        timeout=`expr $timeout + 1`
        if [[ ${timeout} -eq ${network_timeout} ]]; then
            echo "wifi connecting timeout..."
            break
        fi
    done

    wlan0_ip=`ip route | grep "wlan0 proto kernel" | awk '{print $9}'`
    wlan0_route=`ip route | grep "wlan0 proto dhcp" | awk '{print $3}'`

    echo "wlan0 ip: ${wlan0_ip} route: ${wlan0_route}"
    if [ -n "${wlan0_route}" ]; then
        if [ -n "${wlan0_ip}" ]; then
            wifi_status="$green OK! $clear"
        fi
    fi
    echo -e "WIFI:$wifi_status"
}

function check_eth0() {
    echo -e "$yellow ==== Checking Eth0... ==== $clear"

    timeout=0
    while [ -z "`dmesg | grep 'eth0: Link is Up'`" ]; do
        echo "eth0 wait for up"
        sleep 1
        timeout=`expr $timeout + 1`
        if [[ ${timeout} -eq ${network_timeout} ]]; then
            echo "eth0 timeout..."
            break
        fi
    done

    eth0_ip=`ip route | grep "eth0 proto kernel" | awk '{print $9}'`
    eth0_route=`ip route | grep "eth0 proto dhcp" | awk '{print $3}'`

    echo "eth0 ip: ${eth0_ip} route: ${eth0_route}"
    if [ -n "${eth0_route}" ]; then
        if [ -n "${eth0_ip}" ]; then
            phy_status="$green OK! $clear"
        fi
    fi
    echo -e "Eth0:$phy_status"
}

function check_ram() {
    echo -e "$yellow ==== Checking RAM... ==== $clear"
    status=0                                                                 
    version=0

    ram=`free -m | awk "NR==2"| awk '{print $2}'`

    if [[ ${ram} -eq 483 ]]; then
        status=1
        version=512MB
    elif [[ ${ram} -eq 1982 ]]; then
        status=1
        version=2GB
    fi

    if [[ ${status} == 1 ]]; then
        ram_status="$green ${version}(${ram}) OK! $clear"
    else
        ram_status="$green ${ram}MB not 512M/1G ! $clear"
    fi
    echo -e "RAM:$ram_status"
}

function check_emmc() {
    echo -e "$yellow ==== Checking eMMC... ==== $clear"
    version=0

    eMMC=`fdisk -l | grep "Disk /dev/mmcblk0" | awk '{print $3 $4}'`

    if [ -n "${eMMC}" ]; then
        emmc_status="$green ${eMMC} OK! $clear"
    fi

    echo -e "eMMC:$emmc_status"
}

check_hdmi
check_ov5647
check_usb
check_wlan0
check_eth0
check_ram
check_emmc
#if [[ $fdtfile == "sun50i-h616-biqu-emmc" ]]; then
#    check_emmc
#fi

free -h --si

echo ""

echo -e "/=========== Self-checking Results ============\\"
echo -e "       HDMI   ---> $hdmi_status                  "
echo -e "       OV5647 ---> $ov5647_status                "
echo -e "  Manta USB   ---> $manta_usb_status             "
echo -e " USB Device   ---> $ext_usb_status               "
echo -e "       WIFI   ---> $wifi_status                  "
echo -e "       Eth0   ---> $phy_status                   "
echo -e "        RAM   ---> $ram_status                   "
echo -e "       eMMC   ---> $emmc_status				  "
echo -e "\==============================================/"
