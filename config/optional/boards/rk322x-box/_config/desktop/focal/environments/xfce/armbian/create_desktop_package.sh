# set slick-greeter to be enabled as default (workaround for https://armbian.atlassian.net/browse/AR-632)
mkdir -p "${destination}/etc/armbian/lightdm/lightdm.conf.d"
echo -e "[SeatDefaults]\ngreeter-session=slick-greeter\n" > "${destination}"/etc/armbian/lightdm/lightdm.conf.d/10-slick-greeter.conf
