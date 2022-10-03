run_on_sdcard()
{

	# Lack of quotes allows for redirections and pipes easily.
	chroot "${SDCARD}" /bin/bash -c "${@}" >> "${DEST}"/${LOG_SUBPATH}/install.log

}
