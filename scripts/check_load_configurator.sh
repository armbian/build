#!/bin/bash
[[ $EUID == 0 && -f /usr/bin/armbian-config ]] && echo "" && read -n 1 -s -p "Press any key to load armbian-config or CTRL-C to use shell." && echo "" && armbian-config
