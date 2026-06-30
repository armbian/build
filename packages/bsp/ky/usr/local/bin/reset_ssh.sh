#!/bin/bash

sudo rm /etc/ssh/ssh_host_*
sudo dpkg-reconfigure openssh-server
