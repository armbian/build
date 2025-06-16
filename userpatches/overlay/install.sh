#!/bin/bash
#
# Web3 Pi Staking OS install script
#
echo "[install.sh] - start at $(date '+%Y-%m-%d %H:%M:%S')"

SWAPFILE_SIZE=16384
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

# STORAGE-RELATED SECTION

get_best_disk() {
  if stat $DEV_NVME >/dev/null 2>&1; then
    W3P_DRIVE=$DEV_NVME
  elif stat $DEV_USB >/dev/null 2>&1; then
    W3P_DRIVE=$DEV_USB
  else
    W3P_DRIVE="NA"
    echolog "No suitable disk found"
    set_error "[install.sh] - No suitable disk found"
    sleep 2
    terminateScript
    #kill -9 $$
  fi
}

verify_size() {
  local part_size="$(lsblk -b -o NAME,SIZE | grep ${1:5})"
  local loc_array=($part_size)

  if [[ ${#loc_array[@]} != 2 ]]; then
    echolog "Unexpected error while reading disk size"
    set_error "[install.sh] - Unexpected error while reading disk size"
    sleep 2
    terminateScript
    #kill -9 $$
  fi

  if [[ ${loc_array[1]} -lt $MIN_VALID_DISK_SIZE ]]; then
    return 1
  fi

  return 0
}

prepare_disk() {
  local DISK="$1"
  local proceed_with_format=true
  local num_of_partitions=$(( $(partx -g ${DISK} | wc -l) ))

  # Different partition naming conventions for potential drives (either "/dev/nvme0n1" or "/dev/sda")
  if [[ "$DISK" == "$DEV_NVME" ]]; then
    local PARTITION="${DISK}p1"
  else
    local PARTITION="${DISK}1"
  fi

  if [[ $num_of_partitions != 1 ]]; then
    echolog "$DISK contains $num_of_partitions partitions (exactly one allowed). Formating."
  else
    # Verify that the provided disk is large enough to store at least part of the swap file and least significant part of consensus client state 
    if ! verify_size $PARTITION; then
      echolog "Disk to small to proceed with installation"
      set_error "[install.sh] - Disk to small to proceed with installation"
      sleep 2
      terminateScript
      #kill -9 $$
    fi

    # Mount disk if it exists and is a Linux partition
    if  [[ -b "$PARTITION" && $(file -s "$PARTITION" | grep -oP 'Linux.*filesystem') ]]; then
      local TMP_DIR=$(mktemp -d)
      mount "$PARTITION" "$TMP_DIR"
    fi

    # Check if the .ethereum exists on the mounted disk
    if [ -d "$TMP_DIR/.ethereum" ]; then
      set_status "[install.sh] - .ethereum already exists on the disk"
      echolog ".ethereum already exists on the disk."

      # Check if the format_me or format_storage file exists
      if [ -f "/boot/firmware/format_storage" ]; then
        echolog "The format_storage file was found. Formatting and mounting..."
        set_status "[install.sh] - The format_storage file was found. Formatting and mounting..."
        rm /boot/firmware/format_storage
      elif [ -f "$TMP_DIR/format_me" ]; then
        echolog "The format_me file was found. Formatting and mounting..."
        set_status "[install.sh] - The format_me file was found. Formatting and mounting..."
      elif [ -f "$TMP_DIR/.format_me" ]; then # for compatibility with prev releases
        echolog "The .format_me file was found. Formatting and mounting..."
        set_status "[install.sh] - The .format_me file was found. Formatting and mounting..."
      else
        echolog "The format flag file was not found. Skipping formatting."
        set_status "[install.sh] - The format flag file was not found. Skipping formatting."
        proceed_with_format=false
      fi

    else
      echolog "The .ethereum does not exist on the disk. Formatting and mounting..."
      set_status "[install.sh] - The .ethereum does not exist on the disk. Formatting and mounting..."
    fi

    # Unmount the disk from the temporary directory
    if mountpoint -q "$TMP_DIR"; then
      umount "$TMP_DIR"
      rm -r "$TMP_DIR"
    fi
  fi

  if [ "$proceed_with_format" = true ]; then
    # Create a new partition and format it as ext4
    echolog "Creating new partition and formatting disk: $DISK..."
    set_status "[install.sh] - Creating new partition and formatting disk: $DISK..."

    wipefs -a "$DISK"
    sgdisk -n 0:0:0 "$DISK"
    mkfs.ext4 -F "$PARTITION" || {
      echolog "Unable to format $PARTITION"
      set_error "[install.sh] - Unable to format $PARTITION"
      sleep 2
      return 1
    }

    echolog "Removing FS reserved blocks on partion $PARTITION"
    set_status "[install.sh] - Removing FS reserved blocks on partion $PARTITION"
    tune2fs -m 0 $PARTITION
  fi

  echolog "Mounting $PARTITION as /mnt/storage"
  set_status "[install.sh] - Mounting $PARTITION as /mnt/storage"
  mkdir /mnt/storage
  echo "$PARTITION /mnt/storage ext4 defaults,noatime 0 2" >> /etc/fstab
  sleep 2
  mount /mnt/storage

  set_status "[install.sh] - Storage is ready"
}

# Firmware updates
if [ "$(get_install_stage)" -eq 1 ]; then
  
  /opt/web3pi/rpi-eeprom/test/install -b

  output_reu=""
  # Detect SoC version
  if [ -f /proc/device-tree/compatible ]; then
      SOC_COMPATIBLE=$(tr -d '\0' < /proc/device-tree/compatible)

      if echo "$SOC_COMPATIBLE" | grep -q "brcm,bcm2711"; then
          set_status "[install.sh] - Detected SoC: BCM2711 (e.g., Raspberry Pi 4/400/CM4)"
          set_status "[install.sh] - Check for firmware updates for the Raspberry Pi SBC"
          output_reu=$(rpi-eeprom-update -a)
          echolog "cmd: rpi-eeprom-update -a \n${output_reu}"
      elif echo "$SOC_COMPATIBLE" | grep -q "brcm,bcm2712"; then
          set_status "[install.sh] - Detected SoC: BCM2712 (e.g., Raspberry Pi 5/500/CM5)"
          set_status "[install.sh] - Check for firmware updates for the Raspberry Pi SBC"
          # Run the firmware update command
          output_reu=$(rpi-eeprom-update -a)
          echolog "${output_reu}"
      else
          set_error "[install.sh] - Detected another model (not BCM2711 or BCM2712)."
          terminateScript
      fi
  else
      set_error "[install.sh] - No /proc/device-tree/compatible file found — cannot detect SoC this way."
      terminateScript
  fi

  rebootReq=false
  # Check if the output contains the message indicating a reboot is needed
  if echo "$output_reu" | grep -q "EEPROM updates pending. Please reboot to apply the update."; then
      rebootReq=true
      set_status "[install.sh] - Firmware will be updated after reboot. rebootReq=true"
      set_status "[install.sh] - Change the stage to 2"
      set_install_stage 2
  elif echo "$output_reu" | grep -q "UPDATE SUCCESSFUL"; then
      rebootReq=true
      set_status "[install.sh] - Firmware updated with flashrom. rebootReq=true"
      set_status "[install.sh] - Change the stage to 2"
      set_install_stage 2
  fi

  # Check the value of rebootReq
  if [ "$rebootReq" = true ]; then
      echo "[install.sh] - EEPROM update requires a reboot. Restarting the device..."
      set_status "[install.sh] - Rebooting after rpi-eeprom-update"
      sleep 5
      reboot
      exit 1
  else
      echo "[install.sh] - No firmware update required"
      set_status "[install.sh] - No firmware update required"
      sleep 3
  fi

  set_status "[install.sh] - Change the stage to 2"
  set_install_stage 2
fi

# MAIN install.sh part
if [ "$(get_install_stage)" -eq 2 ]; then

set_status "[install.sh] - Main installation part"

## STORAGE SETUP ##########################################################################
# Prepare drive to mount /mnt/storage
set_status "[install.sh] - Looking for a valid drive for Blockchain copy"
get_best_disk
echolog "W3P_DRIVE=$W3P_DRIVE"

# Check if /boot/firmware is mounted
mount_point=$(mount | grep ' /boot/firmware ' | awk '{print $1}')

# Check if the mount point starts with $DEV_NVME or $DEV_USB
if [[ $mount_point == $DEV_NVME* ]]; then
    set_status "[install.sh] - /boot/firmware is mounted on an NVMe device: $mount_point"
elif [[ $mount_point == $DEV_USB* ]]; then
    set_status "[install.sh] - /boot/firmware is mounted on a USB device: $mount_point"
else
    set_status "[install.sh] - /boot/firmware is mounted on device: $mount_point"
    set_status "[install.sh] - Preparing $W3P_DRIVE for installation"
    prepare_disk $W3P_DRIVE
fi
#--------------------------------------------------------------------------------------------

## SWAP SPACE CONFIGURATION ###################################################################
set_status "[install.sh] - SWAP configuration"

# Configure swap file location and size
sed -i "s|#CONF_SWAPFILE=.*|CONF_SWAPFILE=/mnt/storage/swapfile|" /etc/dphys-swapfile
sed -i "s|#CONF_SWAPSIZE=.*|CONF_SWAPSIZE=$SWAPFILE_SIZE|" /etc/dphys-swapfile
sed -i "s|#CONF_MAXSWAP=.*|CONF_MAXSWAP=$SWAPFILE_SIZE|" /etc/dphys-swapfile

# Check total RAM in kB
total_ram=$(grep MemTotal /proc/meminfo | awk '{print $2}')
set_status "[install.sh] - Detected RAM: ${total_ram} kB"

# Conditions
if [ "$total_ram" -lt 7000000 ]; then
    set_error "[install.sh] - Not enough RAM for Web3 Pi. Minimum required is 8 GB"
elif [ "$total_ram" -ge 15000000 ]; then
    set_status "[install.sh] - Setting vm.swappiness to 10"
    # Enable dphys-swapfile service
    systemctl enable dphys-swapfile
    {
    echo "vm.min_free_kbytes=65536"
    echo "vm.swappiness=10"
    echo "vm.vfs_cache_pressure=100"
    echo "vm.dirty_background_ratio=10"
    echo "vm.dirty_ratio=20"
    } >> /etc/sysctl.conf
    sysctl -p
elif [ "$total_ram" -ge 7000000 ]; then
    set_status "[install.sh] - Setting vm.swappiness to 80"
    # Enable dphys-swapfile service
    systemctl enable dphys-swapfile
    {
    echo "vm.min_free_kbytes=65536"
    echo "vm.swappiness=80"
    echo "vm.vfs_cache_pressure=500"
    echo "vm.dirty_background_ratio=1"
    echo "vm.dirty_ratio=50"
    } >> /etc/sysctl.conf
    sysctl -p
else
    set_error "[install.sh] - RAM does not match expected specifications."
fi
#--------------------------------------------------------------------------------------------

set_status "[install.sh] - Change the stage to 100"
set_install_stage 100

set_status "[install.sh] - Write rc.local logs to ${RC_LOG}"
grep "rc.local" /var/log/syslog >> $RC_LOG

set_status "[install.sh] - Rebooting..."
sleep 3
reboot
fi

# Print the IP address
_IP=$(hostname -I) || true
if [ "$_IP" ]; then
  printf "\n\n\nRaspberry Pi IP address is %s\n\n\n" "$_IP"
fi

echo "[install.sh] - exit 0 at $(date '+%Y-%m-%d %H:%M:%S')"
exit 0