###########################################
##
## Where are we running from ?
##
string=$(dmesg |grep root)
result=${string#"${string%%root=*}"}
result=`echo $result| cut -d' ' -f 1`
result="${result//root=/}"
SOURCE=$result;
##########################################

##########################################
##
## How much space do we use?
##
USAGE=$(df -BM | grep ^/dev | head -1 | awk '{print $3}')
USAGE=${USAGE%?}
#########################################

##########################################
##
## What are our possible destinations?
##
if [ "$(grep nand /proc/partitions)" != "" ]; then
        # We have nand, check size
        NAND_SIZE=$(awk 'BEGIN { printf "%.0f\n", '$(grep nand /proc/partitions | awk '{print $3}' | head -1)'/1024 }')
        NAND_ROOT_PART=/dev/nand2
fi
## 
if [ "$(grep sda /proc/partitions)" != "" ]; then
        # We have something as sd, check size
        SDA_SIZE=$(awk 'BEGIN { printf "%.0f\n", '$(grep sda /proc/partitions | awk '{print $3}' | head -1)'/1024 }')
        # Check if this is USB drive
        SDA_TYPE=$(udevadm info --query=all --name=sda | grep ID_BUS=)
        SDA_TYPE=${SDA_TYPE#*=}
        SDA_NAME=$(udevadm info --query=all --name=sda | grep ID_MODEL=)
        SDA_NAME=${SDA_NAME#*=}
        SDA_ROOT_PART=/dev/sda1
fi

if (( "$NAND" < "$NAND_MIN" )); then 
        echo "shit"
fi

TEXT="\nYour current root file-system is located on:\n\n$SOURCE.\n\nWhere to move your $USAGE MB of your root-filesystem and alter boot configuration?"
whiptail --title "ARM boards installer" --backtitle "(c) Igor Pecovnik, http://www.igorpecovnik.com" --menu "$TEXT" 19 60 2  \
"$NAND_ROOT_PART " "($NAND_SIZE MB) internal flash media" \
"$SDA_ROOT_PART  " "($SDA_SIZE MB) $SDA_TYPE drive $SDA_NAME"  2>results
DEST=$(<results)

if [[ -z $(cat /proc/partitions | grep $DEST) ]]; then 
        echo "Device $DEST not partitioned";
        exit 0
fi

toilet -f mono12 WARNING > test_textbox
echo "\nThis script will erase first partition of your hard drive ($MODEL) and copy content of SD card to it " >> test_textbox
#                  filename height width
whiptail --textbox test_textbox 32 74 --scrolltext