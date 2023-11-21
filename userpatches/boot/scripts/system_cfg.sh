#!/bin/bash

SYSTEM_CFG_PATH="/boot/system.cfg"
source ${SYSTEM_CFG_PATH}

grep -e "^hostname" ${SYSTEM_CFG_PATH} > /dev/null
STATUS=$?
if [ ${STATUS} -eq 0 ]; then
    cur_name=$(nmcli general hostname)
    if [[ ${cur_name} != ${hostname} ]]; then
        sudo nmcli general hostname ${hostname}
        sudo systemctl restart systemd-hostnamed
        sudo systemctl restart avahi-daemon.service
    fi
fi

grep -e "^TimeZone" ${SYSTEM_CFG_PATH} > /dev/null
STATUS=$?
if [ ${STATUS} -eq 0 ]; then
    sudo timedatectl set-timezone ${TimeZone}
fi

#######################################################
grep -e "^ks_angle" ${SYSTEM_CFG_PATH} > /dev/null
STATUS=$?
if [ ${STATUS} -eq 0 ]; then
    if [[ ${ks_angle} == "normal" ]]; then
        i=0
    elif [[ ${ks_angle} == "left" ]]; then
        i=1
    elif [[ ${ks_angle} == "inverted" ]]; then
        i=2
    elif [[ ${ks_angle} == "right" ]]; then
        i=3
    else
        i=0
    fi

    ks_restart=0

    DISPLAY_CONFIG_OPTION="Option \"Rotate\" "
    DISPLAY_DIR_OPTIONS=(
        "\"normal\""
        "\"left\""
        "\"inverted\""
        "\"right\""
    )
    DISPLAY_CONFIG_PATH="/usr/share/X11/xorg.conf.d"
    DISPLAY_CONFIG="/usr/share/X11/xorg.conf.d/90-monitor.conf"
    DISPLAY_MONITOR="Identifier \"HDMI-1\""
    DISPLAY_DIR_LINE="${DISPLAY_DIR_OPTIONS[$i]}"
    if [ -e "${DISPLAY_CONFIG}" ]; then
        grep -e "^\    ${DISPLAY_CONFIG_OPTION}${DISPLAY_DIR_LINE}" ${DISPLAY_CONFIG} > /dev/null
        STATUS=$?
        if [ $STATUS -eq 1 ]; then
            sudo sed -i "/${DISPLAY_CONFIG_OPTION}/d" ${DISPLAY_CONFIG}
            sudo sed -i "/${DISPLAY_MONITOR}/a\    ${DISPLAY_CONFIG_OPTION}${DISPLAY_DIR_LINE}" ${DISPLAY_CONFIG}
            ks_restart=1
        fi
    else
        if [ -d "${DISPLAY_CONFIG_PATH}" ]; then
            sudo touch ${DISPLAY_CONFIG}
            sudo bash -c "echo 'Section \"Monitor\"' > ${DISPLAY_CONFIG} "
            sudo bash -c "echo '    Identifier \"HDMI-1\"' >> ${DISPLAY_CONFIG} "
            sudo bash -c "echo 'EndSection' >> ${DISPLAY_CONFIG} "
            sudo sed -i "/${DISPLAY_MONITOR}/a\    ${DISPLAY_CONFIG_OPTION}${DISPLAY_DIR_LINE}" ${DISPLAY_CONFIG}
            ks_restart=1
        fi
    fi

    CONFIG_OPTION="Option \"CalibrationMatrix\" "
    CALIB_OPTIONS=(
        "\"1 0 0 0 1 0 0 0 1\""
        "\"0 -1 1 1 0 0 0 0 1\""
        "\"-1 0 1 0 -1 1 0 0 1\""
        "\"0 1 0 -1 0 1 0 0 1\""
    )
    CONFIG="/usr/share/X11/xorg.conf.d/40-libinput.conf"
    INPUT_CLASS="Identifier \"libinput touchscreen catchall\""
    CONFIG_LINE="${CALIB_OPTIONS[$i]}"
    if [ -e "${CONFIG}" ]; then
        grep -e "^\        ${CONFIG_OPTION}${CONFIG_LINE}" ${CONFIG} > /dev/null
        STATUS=$?
        if [ $STATUS -eq 1 ]; then
            sudo sed -i "/${CONFIG_OPTION}/d" ${CONFIG}
            sudo sed -i "/${INPUT_CLASS}/a\        ${CONFIG_OPTION}${CONFIG_LINE}" ${CONFIG}
            ks_restart=1
        fi
    fi

    if [ ${ks_restart} -eq 1 ];then
        sudo service KlipperScreen restart
    fi
fi

#######################################################
if [[ ${BTT_PAD7} == "ON" ]]; then
    # Toggle status light color
    sudo /boot/scripts/set_rgb 0x000001 0x000001

    # Automatic brightness adjustment
    [[ ${AUTO_BRIGHTNESS} == "ON" ]] && /boot/scripts/auto_brightness &

    SRC_FILE=/boot/scripts/ks_click.sh

    [[ -e "${SRC_FILE}" ]] && sudo rm ${SRC_FILE} -fr

    touch ${SRC_FILE} && chmod +x ${SRC_FILE}
    echo "#!/bin/bash" >> ${SRC_FILE}

    if [[ ${TOUCH_VIBRATION} == "ON" ]]; then
        RUN_FILE="${RUN_FILE}vibration"
    fi
    if [[ ${TOUCH_SOUND} == "ON" ]]; then
        RUN_FILE="${RUN_FILE}sound"
    fi

    if [ -n "${RUN_FILE}" ]; then
        if [[ ${RUN_FILE} =~ "vibration" ]]; then
            sudo chmod 666 /sys/class/gpio/export
            echo 79 > /sys/class/gpio/export
            cd /sys/class/gpio/gpio79
            sudo chmod 666 direction value
            echo out > /sys/class/gpio/gpio79/direction
        fi

        if [[ ${RUN_FILE} =~ "sound" ]]; then
            export AUDIODRIVER=alsa
        fi

        [[ -z "${RUN_FILE}" ]] || echo "/boot/scripts/${RUN_FILE}.sh &" >> ${SRC_FILE}
    fi
fi

#######################################################

