#!/bin/bash
#
# Web3 Pi Staking OS install script
#
echo "[install.sh] - start at $(date '+%Y-%m-%d %H:%M:%S')"

DEV_NVME="/dev/nvme0n1"
DEV_USB="/dev/sda"
W3P_DRIVE="NA"
MIN_VALID_DISK_SIZE=$((150 * 1024 * 1024 * 1024))
RC_LOG="/opt/web3pi/logs/rc.local.txt"
E_LOG="/opt/web3pi/logs/elog.txt"

# Function: echolog
# Description: Logs messages with a timestamp prefix. If no arguments are provided,
#              reads from stdin and logs each line. Outputs to console and appends to $LOGI file.
LOGI="/opt/web3pi/logs/web3pi.log"
echolog(){
    if [ $# -eq 0 ]
    then cat - | while read -r message
        do
                echo "$(date +"[%F %T %Z] -") $message" | tee -a $LOGI
            done
    else
        echo -n "$(date +'[%F %T %Z]') - " | tee -a $LOGI
        echo $* | tee -a $LOGI
    fi
}

echolog " "
echolog "Web3 Pi install.sh START - Web3 Pi install.sh START - Web3 Pi install.sh START - Web3 Pi install.sh START - Web3 Pi install.sh START"
echolog " "
timedatectl | echolog


# Function: set_install_stage
# Description: A function that saves the installation stage to the file /root/.install_stage. The file stores a number as text. The beginning of the installation is marked by 0, and the higher the number, the further along the installation process is. A value of 100 indicates the installation is complete.
set_install_stage() {
  local number=$1
  echo $number > /root/.install_stage
}


# If the installation stage file does not exist, create it and initialize it with the value "0".
if [ ! -f "/root/.install_stage" ]; then
  echolog "/root/.install_stage not exist"
  touch /root/.install_stage
  set_install_stage "0" # initial value
  echolog "/root/.install_stage file created and initialized to 0"
fi

# Function: get_install_stage
# Description: A function that retrieves the installation stage from the file /root/.install_stage.
get_install_stage() {
    local file_path=$1
    if [ -f "/root/.install_stage" ]; then
        local number=$(cat "/root/.install_stage")
        echo $number
    else
        echolog "File /root/.install_stage does not exist."
        return 0
    fi
}

# Function: set_status_jlog
# Function to write a string to a file with status
STATUS_FILE="/opt/web3pi/status.jlog"
set_status_jlog() {
  local status="$1"
  local level="$2"
  jq -n -c\
    --arg status "$status"\
    --arg stage "$(get_install_stage)"\
    --arg time "$(date +"%Y-%m-%dT%H:%M:%S%z")"\
    --arg level "$([ "$level" = "" ] && echo "INFO" || echo "$level")"\
    '{"time": $time, "status": $status, "level": $level, "stage": $stage}' | tee -a $STATUS_FILE
  #echolog " " 
  #echolog "STAGE $(get_install_stage): $status" 
  #echolog " " 
}

# Function: set_status
# Function to write a string to a file with status
set_status() {
  local status="$1"  # Assign the first argument to a local variable
  echo "STAGE $(get_install_stage): $status" > /opt/web3pi/status.txt  # Write the string to the file
  echolog " " 
  echolog "STAGE $(get_install_stage): $status" 
  echolog " " 
  set_status_jlog "$status" INFO
}

set_status "[install.sh] - Script started"

set_error() {
  local status="$1"
  set_status_jlog "$status" "ERROR"
}

# Terminate the script with saving logs
terminateScript()
{
  echolog "terminateScript()"
  touch $E_LOG
  grep "rc.local" /var/log/syslog >> $E_LOG 
  exit 1
}

# Read custom config flags from /boot/firmware/config.txt
config_read_file() {
    (grep -E "^${2}=" -m 1 "${1}" 2>/dev/null || echo "VAR=UNDEFINED") | head -n 1 | cut -d '=' -f 2-;
}

config_get() {
    val="$(config_read_file /boot/firmware/config.txt "${1}")";
    printf -- "%s" "${val}";
}
# use example 
# echo "$(config_get lighthouse)";


echo "[install.sh] - exit 0 at $(date '+%Y-%m-%d %H:%M:%S')"
exit 0