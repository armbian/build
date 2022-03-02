#!/bin/bash

# Remove log file passed in argument
# Script is executed by rsyslogd when log file size limit is reached

LOGS_ROTATE_DEBUG=
LOGS_ROTATE_DEBUG_FILE=/tmp/$(basename "$0").log
LOG_FILE=$1

if [ -f "$LOG_FILE" ]; then
  if [ -n "$LOGS_ROTATE_DEBUG" ]; then
    date > "$LOGS_ROTATE_DEBUG_FILE"
    rm -fv "$LOG_FILE" >> "$LOGS_ROTATE_DEBUG_FILE"
  else
    rm -f "$LOG_FILE"
  fi
fi
