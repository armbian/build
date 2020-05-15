#!/bin/bash

# LaBriqueInternet HyperCube Installer
# Copyright (C) 2016 Julien Vaubourg <julien@vaubourg.com>
# Contribute at https://github.com/labriqueinternet/build.labriqueinter.net
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
# 
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# Packages: jq udisks-glue php5-fpm ntfs-3g
# TODO: Send dkim dns txt record by mail?

set -E
set -o pipefail


###############
### HELPERS ###
###############

function log() {
  echo "$(date +'%F %R'): ${1}" | tee -a "$log_filepath/$log_mainfile"
}

function info() {
  log "[INFO] ${1}"
}

function warn() {
  log "[WARN] ${1}"
}

function err() {
  log "[ERR] ${1}"
}

function logfile() {
  (( log_fileindex++ )) || true
  log_file="${log_filepath}/$(printf %02d "${log_fileindex}")-${1}.log"
}

function logfilter() {
  while read line; do
    local passwords=(\
      "${settings[vpnclient,login_passphrase]}" \
      "${settings[hotspot,wifi_passphrase]}" \
      "${settings[yunohost,password]}" \
      "${settings[yunohost,user_password]}" \
      "${settings[unix,root_password]}" \
      "$(cat /etc/yunohost/mysql 2> /dev/null || true)"\
    )

    IFS=$'\n'
    local passwords_sorted=($(perl -ne 'push @a, $_; END { print reverse sort { length $a <=> length $b } @a }' <<< "$(printf "%s\n" "${passwords[@]}")"))

    for i in $(printf "%s\n" "${passwords_sorted[@]}"); do
      i=$(echo "${i}" | tr '@' '#')
      local i_echoed=${i/\'/\'\'\'}

      line=$(echo "${line}" | tr '@' '#')
      line=$(echo "${line}" | perl -pe "s@\Q${i}\E@/removed/@g")
      line=$(echo "${line}" | perl -pe "s@\Q${i_echoed}\E@/removed/@g")
    done

    echo "${line}" >> $log_file
  done
}

function exit_error() {
  err "${1}"
  err "Installation aborted"

  exit_status=1
  cleaning
}

function urlencode() {
  php -r "echo urlencode('${1/\'/\\\'}');"
}


#################
### FUNCTIONS ###
#################

function cleaning_error() {
  err "There was an error on line $1"
  err "Installation aborted"

  exit_status=1
  cleaning
}

function cleaning() {
  trap - EXIT ERR
  set +E

  if [ -d "${tmp_dir}" ]; then
    rm -r "${tmp_dir}" || {
      warn "Unable to remove ${tmp_dir}"
    }
  fi

  if $keep_debugging; then
    local usb=$(find /media/ -mindepth 1 -maxdepth 1)

    if [ -z "${usb}" ]; then
      info "No USB stick detected for log copying"
    else
      if [ $exit_status -eq 0 ]; then
        info "Please, wait 2 minutes for log copying..."
        sleep 2m
      fi

      for i in $usb; do
        rm -fr "${i}/hypercube_logs/" || {
          err "Unable to remove ${i}/hypercube_logs/"
        }
  
        cp -fr $log_filepath "${i}/hypercube_logs/" || {
          err "Unable to copy $log_filepath to ${i}/hypercube_logs/"
        }

        sync

        info "All logs have been copied to the USB stick - you can remove it"
      done
    fi

    info "4 hours (without reboot) before disabling this interface"
    info "Please, save this page with Ctrl+S"

    sync
    sleep 4h
  
    info "Time's up!"
    warn "This page will be disconnected"
    info "Shutting down the debugging webserver..."
  fi

  sleep 5

  if [ ! -z "${webserver_pid}" ]; then
    kill "${webserver_pid}"
  fi

  if iptables -w -nL INPUT | grep -q 2468; then
    iptables -w -D INPUT -p tcp -s 10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,169.254.0.0/16 --dport 2468 -j ACCEPT || {
      err "Unable to delete the netfilter rule"
    }
  fi

  exit $exit_status
}

function set_logpermissions() {
  mkdir -p "${log_filepath}"
  chown root: "${log_filepath}"
  chmod 0700 "${log_filepath}"
}

function start_logwebserver() {
  pushd "${log_filepath}" &> /dev/null
  python -m SimpleHTTPServer 2468 &> /dev/null &
  popd &> /dev/null

  webserver_pid=$(
    (while true; do
      if ! iptables -w -nL INPUT | grep -q 2468; then
        iptables -w -I INPUT 1 -p tcp -s 10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,169.254.0.0/16 --dport 2468 -j ACCEPT || true
      fi
      sleep 1
    done &> /dev/null &
    echo $!) | { read pid; echo $pid; }
  )
}

function find_hypercubefile() {
  logfile ${FUNCNAME[0]}

  info "Detecting USB sticks..."
  udiskie-mount -a || true
  sleep 10
  
  local file_found=$(find /media/ -mindepth 2 -maxdepth 3 -regex '.*/install\.hypercube\(\.txt\)?$' | head -n1)

  if [ -z "${file_found}" ]; then
    file_found=$(find /root/ -mindepth 1 -maxdepth 1 -regex '.*/install\.hypercube\(\.txt\)?$' | head -n1)
  fi

  if [ ! -z "${file_found}" ]; then
    info "HyperCube file found"

    echo "DETECTED FILE: ${file_found}" >> $log_file
    echo "MIME/CHARSET: $(file -bi "${file_found}")" >> $log_file

    iconv -f "$(file -bi "${file_found}" | cut -d= -f2)" -t UTF-8 "${file_found}" -o "${hypercube_file}" &>> $log_file
  else
    err "No install.hypercube(.txt) file found"
  fi
}

function load_json() {
  logfile ${FUNCNAME[0]}

  json=$(jq -r 'to_entries|map("\(.key)=\(.value|tostring)")|.[]' "${hypercube_file}" 2>> $log_file)

  if [ -z "$json" ]; then
    exit_error "Empty HyperCube (or JSON syntax error)"
  else
    echo SUCCESS >> $log_file
  fi
}

function extract_settings() {
  logfile "${FUNCNAME[0]}-${1}"

  local subjson=$(echo "${json}" | grep "^${1}=" | cut -d= -f2-)
  local vars=$(echo "${subjson}" | jq -r 'to_entries|map("\(.key)=\(.value|tostring)")|.[]' 2>> $log_file)

  if [ -z "$vars" ]; then
    exit_error "${1} settings not found (or JSON syntax error)"
  fi

  IFS=$'\n'; for i in $vars; do
    local key=$(echo "${i}" | cut -d= -f1)
    local value=$(echo "${i}" | cut -d= -f2-)

    settings[$1,$key]="${value}"

    if [[ ! -z "$value" && ( "$key" =~ ^crt_ || "$key" =~ pass(word|phrase) ) ]]; then
      echo "settings[${1},${key}]=/removed/" >> $log_file
    else
      echo "settings[${1},${key}]=${value}" >> $log_file
    fi
  done
}

function extract_dotcube() {
  local subjson=$(echo "${json}" | grep "^vpnclient=" | cut -d= -f2-)

  if [ -z "$subjson" ]; then
    exit_error "vpnclient settings not found"
  fi

  echo "${subjson}" >> "${tmp_dir}/config.cube"
}


######################
### CORE FUNCTIONS ###
######################

function detect_wifidevice() {
  logfile ${FUNCNAME[0]}
  local ynh_wifi_device=$(yunohost app setting hotspot wifi_device 2> /dev/null)

  if [ -z "$ynh_wifi_device" ]; then

    ynh_wifi_device=$(iw_devices | awk -F\| '{ print $1 }')
    echo -n 'WIFI DEVICES: ' >> $log_file
    iw_devices &>> $log_file

    if [ ! -z "${ynh_wifi_device}" ]; then
      info "Wifi device correctly detected after rebooting"
      echo -e "\nSELECTED: ${ynh_wifi_device}" >> $log_file

      systemctl stop ynh-hotspot &>> $log_file
      yunohost app setting hotspot wifi_device -v "${ynh_wifi_device}" &>> $log_file
      yunohost app setting hotspot service_enabled -v 1 &>> $log_file
      systemctl start ynh-hotspot &>> $log_file
    else
      info "No wifi device detected :("
    fi
  else
    info "Wifi device already detected, nothing to do"
    echo "SELECTED WIFI DEVICE: ${ynh_wifi_device}" >> $log_file
  fi
}

function deb_changepassword() {
  echo "root:${settings[unix,root_password]}" | /usr/sbin/chpasswd
}

function deb_upgrade() {
  logfile ${FUNCNAME[0]}

  apt-get update &>> $log_file
  apt-get dist-upgrade -o Dpkg::Options::='--force-confold' -y --force-yes &>> $log_file || true
  apt-get autoremove -y --force-yes &>> $log_file || true
  if [ -f "/var/run/.reboot_required" ] ; then reboot ; fi
}

function deb_changehostname() {
  hostnamectl --static set-hostname "${settings[yunohost,domain]}"
  hostnamectl --transient set-hostname "${settings[yunohost,domain]}"
  hostnamectl --pretty set-hostname "La Brique Internet (${settings[yunohost,domain]})"
}

function deb_updatehosts() {
  logfile ${FUNCNAME[0]}

  if ! grep -q "::1 ${settings[yunohost,domain]}" /etc/hosts; then
    echo "127.0.0.1 ${settings[yunohost,domain]}" >> /etc/hosts
    echo "::1 ${settings[yunohost,domain]}" >> /etc/hosts
  fi

  cat /etc/hosts &>> $log_file
}

function deb_setlocales_and_tz() {
  sed -i "s/^# fr_FR.UTF-8 UTF-8/fr_FR.UTF-8 UTF-8/" /etc/locale.gen
  sed -i "s/^# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/" /etc/locale.gen

  locale-gen en_US.UTF-8

  # Update timezone
  echo 'Europe/Paris' > $TARGET_DIR/etc/timezone
  dpkg-reconfigure -f noninteractive tzdata
  
  case "${settings[unix,lang]}" in
    fr) echo 'LC_ALL="fr_FR.UTF-8"' > /etc/environment ;;
    *) echo 'LC_ALL="en_US.UTF-8"' > /etc/environment
  esac
}

function ynh_postinstall() {
  logfile ${FUNCNAME[0]}

  yunohost tools postinstall -d "${settings[yunohost,domain]}" -p "${settings[yunohost,password]}" &>> $log_file
}

function check_dyndns_list() {
  logfile ${FUNCNAME[0]}

  local domains_file="${tmp_dir}/domains"
  curl https://dyndns.yunohost.org/domains > $domains_file 2>> $log_file

  local vars=$(jq -r 'to_entries|map("\(.key)=\(.value|tostring)")|.[]' ${domains_file} 2>> $log_file)

  IFS=$'\n'; for i in $vars; do
    local domain=$(echo "${i}" | cut -d= -f2-)
    echo "dyndns_domain: ${domain}" >> $log_file

    if [[ "${settings[yunohost,domain]}" =~ "${domain}"$ ]]; then
      is_dyndns_useful=true
      echo "DynDNS is useful: ${domain}" >> $log_file
    fi
  done
}

function is_dyndns_available() {
  logfile ${FUNCNAME[0]}

  local dyndns=$(curl -s -o /dev/null -I -w '%{http_code}' "https://dyndns.yunohost.org/test/${settings[yunohost,domain]}" 2>> $log_file || true)
  echo "STATUS CODE: ${dyndns}" >> $log_file

  if [ "${dyndns}" -ne 200 ]; then
    return 1
  fi

  return 0
}

function ynh_removedyndns() {
  rm -f /etc/cron.d/yunohost-dyndns
}

function ynh_createuser() {
  logfile ${FUNCNAME[0]}

  yunohost user create "${settings[yunohost,user]}" -f "${settings[yunohost,user_firstname]}"\
    -l "${settings[yunohost,user_lastname]}" -m "${settings[yunohost,user]}@${settings[yunohost,domain]}"\
    -q 0 -p "${settings[yunohost,user_password]}" &>> $log_file
}

function install_vpnclient() {
  logfile ${FUNCNAME[0]}

  yunohost app install vpnclient --force \
    --args "domain=$(urlencode "${settings[yunohost,domain]}")&path=/vpnadmin" &>> $log_file
}

function install_hotspot() {
  logfile ${FUNCNAME[0]}

  if [[ ${settings[hotspot,enabled]} == false ]]; then
    touch "${log_filepath}/hotspot_disabled"
    echo "The hotspot app won't be installed as set in the hypercube file" >> $log_file
  else
    yunohost app install hotspot --force \
      --args "domain=$(urlencode "${settings[yunohost,domain]}")&path=/wifiadmin&wifi_ssid=$(urlencode "${settings[hotspot,wifi_ssid]}")&wifi_passphrase=$(urlencode "${settings[hotspot,wifi_passphrase]}")&firmware_nonfree=$(urlencode "${settings[hotspot,firmware_nonfree]}")" &>> $log_file
fi
}

function configure_hotspot() {
  logfile ${FUNCNAME[0]}
  local ynh_wifi_device=

  yunohost app addaccess hotspot -u "${settings[yunohost,user]}" &>> $log_file

  yunohost app setting hotspot ip6_dns0 -v "${settings[hotspot,ip6_dns0]}" &>> $log_file
  yunohost app setting hotspot ip6_dns1 -v "${settings[hotspot,ip6_dns1]}" &>> $log_file
  yunohost app setting hotspot ip4_dns0 -v "${settings[hotspot,ip4_dns0]}" &>> $log_file
  yunohost app setting hotspot ip4_dns1 -v "${settings[hotspot,ip4_dns1]}" &>> $log_file
  yunohost app setting hotspot ip4_nat_prefix -v "${settings[hotspot,ip4_nat_prefix]}" &>> $log_file

  ynh_wifi_device=$(yunohost app setting hotspot wifi_device 2> /dev/null)

  if [ "${ynh_wifi_device}" == none ]; then
    yunohost app setting hotspot service_enabled -v 1 &>> $log_file
  fi
}

function configure_vpnclient() {
  logfile ${FUNCNAME[0]}

  yunohost app addaccess vpnclient -u "${settings[yunohost,user]}" &>> $log_file

  yunohost app setting vpnclient service_enabled -v 1 &>> $log_file
  ynh-vpnclient-loadcubefile.sh -u "${settings[yunohost,user]}" -p "${settings[yunohost,user_password]}" -c "${tmp_dir}/config.cube" &>> $log_file || true
}

function execute_customscript() {
  logfile ${FUNCNAME[0]}

  bash "$custom_script" &>> $log_file
}

function monitoring_ip() {
  logfile ${FUNCNAME[0]}
  set +E

  for i in {1-6}; do
    tmplog=$(mktemp /tmp/hypercube-monitoring_ip-XXXX)

    date >> $tmplog
    echo -e "\n" >> $tmplog
    echo IP ADDRESS >> $tmplog
    echo ================= >> $tmplog
    ip addr &>> $tmplog
    echo -e "\n\n" >> $tmplog
    echo IP6 ROUTE >> $tmplog
    echo ================= >> $tmplog
    ip -6 route &>> $tmplog
    echo -e "\n\n" >> $tmplog
    echo IP4 ROUTE >> $tmplog
    echo ================= >> $tmplog
    ip route &>> $tmplog
    echo -e "\n\n" >> $tmplog
    echo RESOLV.CONF >> $tmplog
    echo ================= >> $tmplog
    cat /etc/resolv.conf &>> $tmplog
    echo -e "\n\n" >> $tmplog
    echo PING6 WIKIPEDIA.ORG >> $tmplog
    echo ================= >> $tmplog
    ping6 -c 3 wikipedia.org &>> $tmplog
    echo -e "\n\n" >> $tmplog
    echo PING4 WIKIPEDIA.ORG >> $tmplog
    echo ================= >> $tmplog
    ping -c 3 wikipedia.org &>> $tmplog
    echo -e "\n\n" >> $tmplog
    echo PING 2620:0:862:ed1a::1 >> $tmplog
    echo ================= >> $tmplog
    ping6 -c 3 2620:0:862:ed1a::1 &>> $tmplog
    echo -e "\n\n" >> $tmplog
    echo PING 91.198.174.192 >> $tmplog
    echo ================= >> $tmplog
    ping -c 3 91.198.174.192 &>> $tmplog
    echo -e "\n\n" >> $tmplog
    echo TRACEROUTE 2620:0:862:ed1a::1 >> $tmplog
    echo ================= >> $tmplog
    traceroute6 -n 2620:0:862:ed1a::1 &>> $tmplog
    echo -e "\n\n" >> $tmplog
    echo TRACEROUTE 91.198.174.192 >> $tmplog
    echo ================= >> $tmplog
    traceroute -n 91.198.174.192 &>> $tmplog
    if [ ! -f "${log_filepath}/hotspot_disabled" ]; then
      echo -e "\n\n" >> $tmplog
      echo IW DEV >> $tmplog
      echo ================= >> $tmplog
      iw dev &>> $tmplog
    fi

    mv $tmplog $log_file
    sleep 300
  done &
}

function monitoring_firewalls() {
  logfile ${FUNCNAME[0]}
  set +E

  for i in {1-6}; do
    tmplog=$(mktemp /tmp/hypercube-monitoring_firewalls-XXXX)

    date >> $tmplog
    echo -e "\n" >> $tmplog
    echo IP6TABLES -nvL >> $tmplog
    echo ================= >> $tmplog
    ip6tables -nvL &>> $tmplog
    echo -e "\n\n" >> $tmplog
    echo IPTABLES -nvL >> $tmplog
    echo ================= >> $tmplog
    iptables -w -nvL &>> $tmplog
    echo -e "\n\n" >> $tmplog
    echo 'IPTABLES -t nat -nvL' >> $tmplog
    echo ================= >> $tmplog
    iptables -w -t nat -nvL &>> $tmplog

    mv $tmplog $log_file
    sleep 300
  done &
}

function monitoring_processes() {
  logfile ${FUNCNAME[0]}
  set +E

  for i in {1-6}; do
    tmplog=$(mktemp /tmp/hypercube-monitoring_processes-XXXX)

    date >> $tmplog
    echo -e "\n" >> $tmplog
    echo YNH-VPNCLIENT STATUS >> $tmplog
    echo ================= >> $tmplog
    ynh-vpnclient status &>> $tmplog
    if [ ! -f "${log_filepath}/hotspot_disabled" ]; then
      echo -e "\n\n" >> $tmplog
      echo YNH-HOTSPOT STATUS >> $tmplog
      echo ================= >> $tmplog
      ynh-hotspot status &>> $tmplog
    fi
    echo -e "\n\n" >> $tmplog
    echo 'PS AUX | GREP OPENVPN' >> $tmplog
    echo ================= >> $tmplog
    ps aux | grep openvpn &>> $tmplog
    echo -e "\n\n" >> $tmplog
    echo 'PS AUX | GREP DNSMASQ' >> $tmplog
    echo ================= >> $tmplog
    ps aux | grep dnsmasq &>> $tmplog
    if [ ! -f "${log_filepath}/hotspot_disabled" ]; then
      echo -e "\n\n" >> $tmplog
      echo 'PS AUX | GREP HOSTAPD' >> $tmplog
      echo ================= >> $tmplog
      ps aux | grep hostapd &>> $tmplog
    fi
    echo -e "\n\n" >> $tmplog
    echo 'NETSTAT -pnat' >> $tmplog
    echo ================= >> $tmplog
    netstat -pnat &>> $tmplog

    mv $tmplog $log_file
    sleep 300
  done &
}

function monitoring_yunohost() {
  logfile ${FUNCNAME[0]}
  set +E

  for i in {1-6}; do
    tmplog=$(mktemp /tmp/hypercube-monitoring_ynh-XXXX)

    date >> $tmplog
    echo -e "\n" >> $tmplog
    yunohost tools diagnosis &>> $tmplog

    mv $tmplog $log_file
    sleep 300
  done &
}

function end_installation() {
  log_fileindex=90

  if [ ! -f "${log_filepath}/hotspot_disabled" ]; then
    detect_wifidevice
  fi

  monitoring_ip
  monitoring_firewalls
  monitoring_processes
  monitoring_yunohost

  cp /var/log/openvpn-client.log "${log_filepath}/var_log_openvpn.log" || true
  cp /var/log/daemon.log "${log_filepath}/var_log_daemon.log"
  cp /var/log/syslog "${log_filepath}/var_log_syslog.log"

  info "Finished!"

  rm -f /root/install.hypercube
  systemctl disable hypercube
}


########################
### GLOBAL VARIABLES ###
########################

declare -A settings
tmp_dir=$(mktemp -dp /tmp/ labriqueinternet-installhypercube-XXXXX)
hypercube_file="${tmp_dir}/install.hypercube"
custom_script="/usr/local/bin/hypercube_custom.sh"
exit_status=0
webserver_pid=
is_dyndns_useful=false
log_filepath=/var/log/hypercube/
log_mainfile=install.log
log_fileindex=0
log_file=
keep_debugging=true
json=


##############
### SCRIPT ###
##############

trap cleaning EXIT
trap 'cleaning_error $LINENO' ERR

# YunoHost was installed without the HyperCube system
if [ -f /etc/yunohost/installed -a ! -f "${log_filepath}/enabled" ]; then
  info "YunoHost is already post-installed"
  info "Disabling HyperCube... Bye!"

  systemctl disable hypercube
  keep_debugging=false

  exit 0
fi

info "===== Start HyperCube Service ====="

set_logpermissions
start_logwebserver

# Second boot
if [ -f "${log_filepath}/enabled" ]; then
  info "Starting second step"
  end_installation

# First boot
else
  info "Looking for HyperCube file"
  find_hypercubefile
  
  if [ ! -r "${hypercube_file}" -o ! -s "${hypercube_file}" ]; then
    exit_error "Cannot continue without a usable HyperCube file"
  fi
  
  info "Loading JSON"
  load_json

  info "Extracting settings for Unix"
  extract_settings unix

  info "Extracting settings for YunoHost"
  extract_settings yunohost
  
  info "Extracting settings for Wifi Hotspot"
  extract_settings hotspot

  info "Extracting settings for VPN Client (logging)"
  extract_settings vpnclient
  
  info "Extracting .cube file for VPN Client"
  extract_dotcube

  info "Updating Debian root password"
  deb_changepassword

  info "Changing hostname"
  deb_changehostname

  info "Updating hosts file"
  deb_updatehosts

  info "Setting locales"
  deb_setlocales_and_tz

  info "Upgrading Debian/YunoHost..."
  deb_upgrade

  info "Check online DynDNS domains list"
  check_dyndns_list

  if $is_dyndns_useful; then
    info "Checking DynDNS domain availability"

    if ! is_dyndns_available; then
      exit_error "Unavailable DynDNS subdomain"
    fi
  fi

  # From this line, meeting an error means reflashing the sdcard before retrying
  touch "${log_filepath}/enabled"

  info "Doing YunoHost post-installation..."
  ynh_postinstall

  if ! $is_dyndns_useful; then
    info "Removing DynDNS cron"
    ynh_removedyndns
  fi

  info "Creating first user"
  ynh_createuser

  info "Installing VPN Client..."
  install_vpnclient
  
  info "Installing Wifi Hotspot..."
  install_hotspot

  info "Configuring VPN Client..."
  configure_vpnclient
  
  if [ ! -f "${log_filepath}/hotspot_disabled" ]; then
    info "Configuring Wifi Hotspot..."
    configure_hotspot
  fi
 
  if [ -f "$custom_script" ]; then
    info "Execute custom script..."
    execute_customscript
  fi

  info "Rebooting..."

  if [ -f /etc/crypttab ]; then
    warn "Once rebooted, you have to give the passphrase for uncrypting your Cube"
  fi

  sleep 5
  keep_debugging=false
  systemctl reboot
fi

exit 0
