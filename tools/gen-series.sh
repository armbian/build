#!/bin/bash
# Generate *.series and series.conf from existing patches.* directories

LOG_VERBOSE=0

function print_usage() {

	TOOL=$(basename $0)

	echo -e "Naive tool to create .series and series.conf file from existing local directories"
	echo -e "Usage:"
	echo -e "\t$TOOL [-v] <directory...>"
	echo -e ""
	echo -e "Flags:"
	echo -e "\t-v - enable verbose output"
	echo -e ""
	echo -e "Example:"
	echo -e "\t$TOOL -v patches.libreelec patches.armbian"

}

function log() {

	[[ $LOG_VERBOSE -ne 1 ]] && return

	echo -e "$1"

}

function log_error() {

	echo -e "$1"

}

for arg in "$@"; do
  shift
  case $arg in
    (-v) : ;LOG_VERBOSE=1;;
    (*) set -- "$@" "$arg" ;;
  esac
done

DIRECTORIES=$@

if [[ -z "$DIRECTORIES" ]]; then
	print_usage
	exit 0
fi

for DIR in $@; do

	SERIE=$(echo $DIR | cut -d "." -f 2- | tr -d "/")
	if [[ -z "$SERIE" ]]; then
		log_error "Invalid series directory $DIR"
		exit 1
	fi
	log "Evaluating directory $DIR - $SERIE series"
	
	FILES=$(find "$DIR" -type f -printf "\t%p\n" | sort -g)
	if [[ $? -ne 0 ]]; then
		log_error "Error while evaluating $DIR"
		exit 1
	fi
	log "$FILES"

	echo "# Series from $DIR" > "$SERIE.series"
	echo "$FILES" >> "$SERIE.series"

done

# Zeroes series.conf file, creates it if does not exist
truncate --size 0 "series.conf"
if [[ $? -ne 0 ]]; then
	log_error "Could not truncate file series.conf"
	exit 1
fi

# Concatenate the *.series files into series.conf file with respect to
# the order of the series directories specified on the command line
for DIR in $@; do
	SERIE=$(echo $DIR | cut -d "." -f 2- | tr -d "/")
	cat "$SERIE.series" >> "series.conf"
	if [[ $? -ne 0 ]]; then
		log_error "Error while writing $SERIE.series to series.conf"
		exit 1
	fi
done

exit 0
