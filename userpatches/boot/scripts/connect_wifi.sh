#!/bin/bash    

cfg_file=/boot/system.cfg

WIFI_CFG=/home/biqu/control/wifi/conf/netinfo.txt
log_file=/boot/scripts/wifi.log

IFS=\"

sta_mount=0

wifi_path="/etc/NetworkManager/system-connections/"

function connect_wifi() {
    # whether there is configured wifi in the history
    if [[ `sudo nmcli c s | grep wifi |  awk '{ for(i=NF-2; i<=NF; i++){ $i="" }; print $0 }'` =~ "${WIFI_SSID}" ]] ; then
        set_wifi_path="${wifi_path}${WIFI_SSID}.nmconnection"
        if [[ -e ${set_wifi_path} ]]; then
            psk=`sudo cat ${set_wifi_path} | grep ^psk | awk -F '=' '{print $2}'`
            if [[ ${psk} == $WIFI_PASSWD ]]; then
                # both ssid & passwd matched.
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

    # connect to the new wifi
    if [[ `sudo nmcli device wifi list` =~ $WIFI_SSID ]]
    then
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

function Env_init() {
    exec 1> /dev/null
    # without check_interval set, we risk a 0 sleep = busy loop
    if [ ! "$check_interval" ]; then
        echo $(date)" ===> No check interval set!" >> $log_file
        exit 1
    fi

    # enable wlan
    [[ $(ifconfig | grep $wlan) == "" ]] && sudo nmcli radio wifi on

    connect_wifi

    sleep 6
}

function is_network() {
    if [ $# -eq 0 ]; then
        get_ip=`ip route | grep "$eth proto kernel" | awk '{print $9}'`
        if [ -n "${get_ip}" ]; then
            Result=yes
        else
            get_ip=`ip route | grep "$wlan proto kernel" | awk '{print $9}'`
        fi
    else
        get_ip=`ip route | grep "$1 proto kernel" | awk '{print $9}'`
    fi

    if [ -n "${get_ip}" ]; then
        Result=yes
    else
        Result=no
    fi

    echo $Result
}

function startWifi_sta() {
    sta_mount=`expr $sta_mount + 1`
    echo $(date)" .... sta connecting...$sta_mount..." >> $log_file

    sleep 2
}

function startWifi() {
    [[ $(ifconfig | grep $wlan) == "" ]] && nmcli radio wifi on  # 确保wlan连接启动了

    if [[ $sta_mount -le 2 ]]; then
        nmcli device connect $wlan      # 连接wifi
        echo $(date)" .... $wlan connecting..." >> $log_file
        sleep 2
        [[ $(is_network $wlan) == no ]] && startWifi_sta
        [[ $(is_network $wlan) == yes ]] && sta_mount=0 && echo $(date)" [O.K.] $wlan connected!" >> $log_file
    else
        echo $(date)" xxxx $wlan connection failure..." >> $log_file
    fi
}

source $cfg_file
grep -e "^WIFI_SSID" ${cfg_file} > /dev/null
STATUS=$?
if [ ${STATUS} -eq 0 ]; then
    Env_init
    sleep 20

    while [ 1 ]; do

        if [[ $(is_network) == no ]]; then      # 没有网络连接
            echo -e $(date)" ==== No network connection..." >> $log_file
            startWifi
            sleep 6    # 更改间隔时间，因为有些服务启动较慢，试验后，改的间隔长一点有用
        fi

        sleep $check_interval
    done
fi
