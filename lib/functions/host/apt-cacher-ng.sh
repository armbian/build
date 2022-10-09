# Management of apt-cacher-ng aka acng

function acng_configure_and_restart_acng() {
	if ! armbian_is_host_running_systemd; then return 0; fi                   # do nothing if host is not running systemd
	[[ $NO_APT_CACHER == yes ]] && return 0                                   # don't if told not to. NO_something=yes is very confusing, but kept for historical reasons
	[[ "${APT_PROXY_ADDR:-localhost:3142}" != "localhost:3142" ]] && return 0 # also not if acng not local to builder machine

	display_alert "Preparing acng configuration" "apt-cacher-ng" "info"

	run_host_command_logged systemctl stop apt-cacher-ng || true # ignore errors, it might already be stopped.

	[[ ! -f /etc/apt-cacher-ng/acng.conf.orig.pre.armbian ]] && cp /etc/apt-cacher-ng/acng.conf /etc/apt-cacher-ng/acng.conf.orig.pre.armbian

	cat <<- ACNG_CONFIG > /etc/apt-cacher-ng/acng.conf
		CacheDir: ${APT_CACHER_NG_CACHE_DIR:-/var/cache/apt-cacher-ng}
		LogDir: /var/log/apt-cacher-ng
		SupportDir: /usr/lib/apt-cacher-ng
		LocalDirs: acng-doc /usr/share/doc/apt-cacher-ng
		ReportPage: acng-report.html
		ExThreshold: 4

		# Remapping is disabled, many times we hit broken mirrors due to this.
		#Remap-debrep: file:deb_mirror*.gz /debian ; file:backends_debian # Debian Archives
		#Remap-uburep: file:ubuntu_mirrors /ubuntu ; file:backends_ubuntu # Ubuntu Archives

		# Turn debug logging and verbosity
		Debug: 7
		VerboseLog: 1

		# Connections tuning.
		MaxStandbyConThreads: 10
		DlMaxRetries: 50
		NetworkTimeout: 60
		FastTimeout: 20
		ConnectProto: v4 v6
		RedirMax: 15
		ReuseConnections: 1

		# Allow HTTPS CONNECT, although this is not ideal, since packages are not actually cached.
		# Enabled, since PPA's require this.
		PassThroughPattern: .*
	ACNG_CONFIG

	# Ensure correct permissions on the directories
	mkdir -p "${APT_CACHER_NG_CACHE_DIR:-/var/cache/apt-cacher-ng}" /var/log/apt-cacher-ng
	chown apt-cacher-ng:apt-cacher-ng "${APT_CACHER_NG_CACHE_DIR:-/var/cache/apt-cacher-ng}" /var/log/apt-cacher-ng

	if [[ "${APT_CACHER_NG_CLEAR_LOGS}" == "yes" ]]; then
		display_alert "Clearing acng logs" "apt-cacher-ng logs cleaning" "debug"
		run_host_command_logged rm -rfv /var/log/apt-cacher-ng/*
	fi

	run_host_command_logged systemctl start apt-cacher-ng
	run_host_command_logged systemctl status apt-cacher-ng
}

function acng_check_status_or_restart() {
	[[ $NO_APT_CACHER == yes ]] && return 0                                   # don't if told not to
	[[ "${APT_PROXY_ADDR:-localhost:3142}" != "localhost:3142" ]] && return 0 # also not if acng not local to builder machine

	if ! systemctl -q is-active apt-cacher-ng.service; then
		display_alert "ACNG systemd service is not active" "restarting apt-cacher-ng" "warn"
		acng_configure_and_restart_acng
	fi

	if ! wget -q --timeout=10 --output-document=/dev/null http://localhost:3142/acng-report.html; then
		display_alert "ACNG is not correctly listening for requests" "restarting apt-cacher-ng" "warn"
		acng_configure_and_restart_acng
		if ! wget -q --timeout=10 --output-document=/dev/null http://localhost:3142/acng-report.html; then
			exit_with_error "ACNG is not correctly listening for requests" "apt-cacher-ng NOT WORKING"
		fi
	fi

	display_alert "apt-cacher-ng running correctly" "apt-cacher-ng OK" "debug"

}
