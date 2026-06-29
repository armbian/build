#!/usr/bin/env bash

# squid must be configured to do ssl-bumping
# Also a self-signed cert with ca needs to be created
# the ca needs to be stored as "squid-self-signed.crt" in userpatches/

# to do
# check if https_proxy/HTTPS_PROXY are set and then if cert is available.

# HOST
# if a cert file is there copy into docker container or host machine and enable it
function post_family_config__prepare_host_for_https_proxy() {
    if [ -f ${USERPATCHES_PATH}/squid-self-signed.crt ]; then
        display_alert "Found cert file: ${USERPATCHES_PATH}/squid-self-signed.crt" "${EXTENSION}" "info"
        run_host_command_logged mkdir -p /usr/share/ca-certificates/extra/
        run_host_command_logged cp ${USERPATCHES_PATH}/squid-self-signed.crt /usr/share/ca-certificates/extra/squid-self-signed.crt
        run_host_command_logged echo "extra/squid-self-signed.crt" >> /etc/ca-certificates.conf
        run_host_command_logged update-ca-certificates
        display_alert "Host/Docker prepared for https proxy" "${EXTENSION}" "info"
    else
        display_alert "Cert file not found" "${EXTENSION}" "error"
        exit 1
    fi
}

# CHROOT
# Add cert into chroot before customization so customization won't fail on https downloads
function pre_customize_image__prepare_https_proxy_inside_chroot() {
    display_alert "Found cert file" "${EXTENSION}" "info"
    chroot_sdcard mkdir -p /usr/share/ca-certificates/extra/ 
    run_host_command_logged cp ${USERPATCHES_PATH}/squid-self-signed.crt "${SDCARD}"/usr/share/ca-certificates/extra/squid-self-signed.crt
    run_host_command_logged echo "extra/squid-self-signed.crt" >> "${SDCARD}"/etc/ca-certificates.conf
    chroot_sdcard cat /etc/ca-certificates.conf
    chroot_sdcard update-ca-certificates
}

# CHROOT
# Remove cert after "apt_lists_copy_from_host_to_image_and_update" has been executed
function pre_umount_final_image__unprepare_https_proxy_inside_chroot() {
    chroot_sdcard rm /usr/share/ca-certificates/extra/squid-self-signed.crt
    run_host_command_logged sed -i "'/extra\/squid-self-signed.crt/d'" "${SDCARD}/etc/ca-certificates.conf"
    chroot_sdcard update-ca-certificates
}

# HOST
# remove 
#function post_umount_final_image__unprepare_host_for_https_proxy() {
#    if [ -f /usr/share/ca-certificates/extra/squid-self-signed.crt ]; then
#        display_alert "Found cert file: /usr/share/ca-certificates/extra/squid-self-signed.crt. Removing..." "${EXTENSION}" "info"
#        run_host_command_logged rm /usr/share/ca-certificates/extra/squid-self-signed.crt
#        run_host_command_logged sed -i "'/extra\/squid-self-signed.crt/d'" /etc/ca-certificates.conf
#        run_host_command_logged update-ca-certificates
#        display_alert "Host unprepared for https proxy" "${EXTENSION}" "info"
#    else
#        display_alert "Cert file not found" "${EXTENSION}" "error"
#        exit 1
#    fi
#}
# removing cert casuses log upload to fail