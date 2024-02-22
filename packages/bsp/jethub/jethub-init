#!/bin/bash

declare -g GPIOS
declare -g LEDS

set -e

RP=$(realpath "${0}")
SCRIPTPATH=$(dirname "${RP}")

# shellcheck source=/dev/null
source "${SCRIPTPATH}/libjethubconfig.sh"

# Enable legacy sysfs gpio export. Will be disabled in future releases

ENABLESYSFS=${JETHUB_SYSFS_ENABLE:-true}

GPIOSET=${GPIOSET:-/usr/bin/gpioset}

### define functions

configure_gpiobase()
{
    declare -g GPIOBASE
    declare -g GPIOCHIP
    declare -g -A GPIOCHIPBASE
    for gpiochipsys in /sys/class/gpio/gpiochip*/; do
        gpiochipsys=${gpiochipsys%*/}
        gpiochiptemp=$(find "${gpiochipsys}"/device/gpiochip* -type d | head -n 1)
        GPIOCHIP=${gpiochiptemp##*/}
        GPIOBASE=$(cat "${gpiochipsys}/base")
        GPIOCHIPBASE["$(echo "${GPIOCHIP}" | tr -d -c 0-9)"]=${GPIOBASE}
    done
    if [[ -z "${GPIOBASE}" ]]; then
        echo Can not find gpiochip and base number
        exit 1
    fi
}

gpio_set()
{
    gpiochip="${1}"
    GPIOL=${2}
    VALUE=${3}
    LOW=${4}
    echo "${0}: GPIOSET: gpiochip=${gpiochip} line=${GPIOL} val=${VALUE} low=${LOW} base=$((GPIOCHIPBASE[${gpiochip}]))"
    if [[ "${ENABLESYSFS}" == "true" ]]; then
        GPIOLINE=$((GPIOCHIPBASE[${gpiochip}]+GPIOL))
        echo "${VALUE}" > /sys/class/gpio/gpio${GPIOLINE}/value
    else
        if [ "${LOW}" == "${GPIO_ACTIVE_LOW}" ]; then
            LOW="-l"
        else
            LOW=""
        fi
        ${GPIOSET} "${LOW}" "${gpiochip}" "${GPIOL}=${VALUE}"
    fi

}


unexport_sysfs()
{
    for i in /sys/class/gpio/gpio* ; do
        if ! echo "$i" | grep -q chip ; then
	        ii=$(echo "${i##*/}"| tr -d -c 0-9)
	        echo "$ii" > /sys/class/gpio/unexport
	fi
    done
}


configure_gpio() {
  # Get base
  GPIOCHIP=${1}
  GPIOL=${2}
  GPIOLINE=$((GPIOCHIPBASE[${GPIOCHIP}]+GPIOL))
  DIRECTION=${3}
  ACTIVELEVEL=${4}
  echo "${0}: Export GPIO to sysfs: gpio=${GPIOLINE} (${GPIOL}), direction=${DIRECTION}, active_level=${ACTIVELEVEL}"
  if [ ! -d /sys/class/gpio/gpio${GPIOLINE} ]; then
    echo ${GPIOLINE} > /sys/class/gpio/export
    if [ ! -d /sys/class/gpio/gpio${GPIOLINE} ]; then
      echo "${0}: *** Error: Failed to configure GPIO ${GPIOLINE}"
      exit 1
    fi
  fi

  if [ "${DIRECTION}" == "${GPIO_DIRECTION_OUTPUT}" ]; then
    echo "out" > /sys/class/gpio/gpio${GPIOLINE}/direction
  else
    echo "in" > /sys/class/gpio/gpio${GPIOLINE}/direction
  fi

  if [ "${ACTIVELEVEL}" == "${GPIO_ACTIVE_LOW}" ]; then
    echo 1 > /sys/class/gpio/gpio${GPIOLINE}/active_low
  fi
}

configure_led() {
  echo "${0}: Configure: gpiochip=${1} led=${2}, state=${3}, active_level=${4}"
  gpio_set "${1}" "${2}" "${3}" "${4}"
}

### end define functions

### begin

echo "${0}: Unexport gpio from sysfs"
unexport_sysfs

if [[ "${ENABLESYSFS}" = "true" ]]; then
    echo "${0}: Configure GPIOs as sysfs ..."

    configure_gpiobase

    for gpio_parameters in "${GPIOS[@]}"
    do
        # shellcheck disable=SC2086
        configure_gpio ${gpio_parameters}
    done
else
    echo "${0}: Configure GPIOs for gpiod"
fi

echo "${0}: Configure LEDs ..."
for leds_parameters in "${LEDS[@]}"
do
    # shellcheck disable=SC2086
    configure_led ${leds_parameters}
done

if [[ -n "${ADDITIONALFUNC}" ]]; then
    for func in ${ADDITIONALFUNC}; do
        echo "${0}: Start additional init function ${func}"
        ${func}
    done
fi

echo "${0}: Initialization done"

exit 0
