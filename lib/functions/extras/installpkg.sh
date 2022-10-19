# Installing debian packages or package files in the armbian build system.
# The function accepts four optional parameters:
# autoupdate - If the installation list is not empty then update first.
# upgrade, clean - the same name for apt
# verbose - detailed log for the function
#
# list="pkg1 pkg2 pkg3 pkgbadname pkg-1.0 | pkg-2.0 pkg5 (>= 9)"
# or list="pkg1 pkg2 /path-to/output/debs/file-name.deb"
# install_pkg_deb upgrade verbose $list
# or
# install_pkg_deb autoupdate $list
#
# If the package has a bad name, we will see it in the log file.
# If there is an LOG_OUTPUT_FILE variable and it has a value as
# the full real path to the log file, then all the information will be there.
#
# The LOG_OUTPUT_FILE variable must be defined in the calling function
# before calling the install_pkg_deb function and unset after.
#
install_pkg_deb() {
	local list=""
	local listdeb=""
	local log_file
	local add_for_install
	local for_install
	local need_autoup=false
	local need_upgrade=false
	local need_clean=false
	local need_verbose=false
	local _line=${BASH_LINENO[0]}
	local _function=${FUNCNAME[1]}
	local _file=$(basename "${BASH_SOURCE[1]}")
	local tmp_file=$(mktemp /tmp/install_log_XXXXX)
	export DEBIAN_FRONTEND=noninteractive

	if [ -d $(dirname $LOG_OUTPUT_FILE) ]; then
		log_file=${LOG_OUTPUT_FILE}
	else
		log_file="${SRC}/output/${LOG_SUBPATH}/install.log"
	fi

	for p in $*; do
		case $p in
			autoupdate)
				need_autoup=true
				continue
				;;
			upgrade)
				need_upgrade=true
				continue
				;;
			clean)
				need_clean=true
				continue
				;;
			verbose)
				need_verbose=true
				continue
				;;
			\| | \(* | *\)) continue ;;
			*[.]deb)
				listdeb+=" $p"
				continue
				;;
			*) list+=" $p" ;;
		esac
	done

	# This is necessary first when there is no apt cache.
	if $need_upgrade; then
		apt-get -q update || echo "apt cannot update" >> $tmp_file
		apt-get -y upgrade || echo "apt cannot upgrade" >> $tmp_file
	fi

	# Install debian package files
	if [ -n "$listdeb" ]; then
		for f in $listdeb; do
			# Calculate dependencies for installing the package file
			add_for_install=" $(
				dpkg-deb -f $f Depends | awk '{gsub(/[,]/, "", $0); print $0}'
			)"

			echo -e "\nfile $f depends on:\n$add_for_install" >> $log_file
			install_pkg_deb $add_for_install
			dpkg -i $f 2>> $log_file
			dpkg-query -W \
				-f '${binary:Package;-27} ${Version;-23}\n' \
				$(dpkg-deb -f $f Package) >> $log_file
		done
	fi

	# If the package is not installed, check the latest
	# up-to-date version in the apt cache.
	# Exclude bad package names and send a message to the log.
	for_install=$(
		for p in $list; do
			if $(dpkg-query -W -f '${db:Status-Abbrev}' $p |& awk '/ii/{exit 1}'); then
				apt-cache show $p -o APT::Cache::AllVersions=no |&
					awk -v p=$p -v tmp_file=$tmp_file \
						'/^Package:/{print $2} /^E:/{print "Bad package name: ",p >>tmp_file}'
			fi
		done
	)

	# This information should be logged.
	if [ -s $tmp_file ]; then
		echo -e "\nInstalling packages in function: $_function" "[$_file:$_line]" \
			>> $log_file
		echo -e "\nIncoming list:" >> $log_file
		printf "%-30s %-30s %-30s %-30s\n" $list >> $log_file
		echo "" >> $log_file
		cat $tmp_file >> $log_file
	fi

	if [ -n "$for_install" ]; then
		if $need_autoup; then
			apt-get -q update
			apt-get -y upgrade
		fi
		apt-get install -qq -y --no-install-recommends $for_install
		echo -e "\nPackages installed:" >> $log_file
		dpkg-query -W \
			-f '${binary:Package;-27} ${Version;-23}\n' \
			$for_install >> $log_file

	fi

	# We will show the status after installation all listed
	if $need_verbose; then
		echo -e "\nstatus after installation:" >> $log_file
		dpkg-query -W \
			-f '${binary:Package;-27} ${Version;-23} [ ${Status} ]\n' \
			$list >> $log_file
	fi

	if $need_clean; then apt-get clean; fi
	rm $tmp_file
}
