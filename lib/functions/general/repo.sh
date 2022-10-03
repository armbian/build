adding_packages()
{
# add deb files to repository if they are not already there

	display_alert "Checking and adding to repository $release" "$3" "ext"
	for f in "${DEB_STORAGE}${2}"/*.deb
	do
		local name version arch
		name=$(dpkg-deb -I "${f}" | grep Package | awk '{print $2}')
		version=$(dpkg-deb -I "${f}" | grep Version | awk '{print $2}')
		arch=$(dpkg-deb -I "${f}" | grep Architecture | awk '{print $2}')
		# add if not already there
		aptly repo search -architectures="${arch}" -config="${SCRIPTPATH}config/${REPO_CONFIG}" "${1}" 'Name (% '${name}'), $Version (='${version}'), $Architecture (='${arch}')' &>/dev/null
		if [[ $? -ne 0 ]]; then
			display_alert "Adding ${1}" "$name" "info"
			aptly repo add -force-replace=true -config="${SCRIPTPATH}config/${REPO_CONFIG}" "${1}" "${f}" &>/dev/null
		fi
	done

}

addtorepo()
{
# create repository
# parameter "remove" dumps all and creates new
# parameter "delete" remove incoming directory if publishing is succesful
# function: cycle trough distributions

	local distributions=("stretch" "bionic" "buster" "bullseye" "focal" "hirsute" "impish" "jammy" "sid")
	#local distributions=($(grep -rw config/distributions/*/ -e 'supported' | cut -d"/" -f3))
	local errors=0

	for release in "${distributions[@]}"; do

		ADDING_PACKAGES="false"
		if [[ -d "config/distributions/${release}/" ]]; then
			[[ -n "$(cat config/distributions/${release}/support | grep "csc\|supported" 2>/dev/null)" ]] && ADDING_PACKAGES="true"
		else
			display_alert "Skipping adding packages (not supported)" "$release" "wrn"
			continue
		fi

		local forceoverwrite=""

		# let's drop from publish if exits
		if [[ -n $(aptly publish list -config="${SCRIPTPATH}config/${REPO_CONFIG}" -raw | awk '{print $(NF)}' | grep "${release}") ]]; then
			aptly publish drop -config="${SCRIPTPATH}config/${REPO_CONFIG}" "${release}" > /dev/null 2>&1
		fi

		# create local repository if not exist
		if [[ -z $(aptly repo list -config="${SCRIPTPATH}config/${REPO_CONFIG}" -raw | awk '{print $(NF)}' | grep "${release}") ]]; then
			display_alert "Creating section" "main" "info"
			aptly repo create -config="${SCRIPTPATH}config/${REPO_CONFIG}" -distribution="${release}" -component="main" \
			-comment="Armbian main repository" "${release}" >/dev/null
		fi

		if [[ -z $(aptly repo list -config="${SCRIPTPATH}config/${REPO_CONFIG}" -raw | awk '{print $(NF)}' | grep "^utils") ]]; then
			aptly repo create -config="${SCRIPTPATH}config/${REPO_CONFIG}" -distribution="${release}" -component="utils" \
			-comment="Armbian utilities (backwards compatibility)" utils >/dev/null
		fi
		if [[ -z $(aptly repo list -config="${SCRIPTPATH}config/${REPO_CONFIG}" -raw | awk '{print $(NF)}' | grep "${release}-utils") ]]; then
			aptly repo create -config="${SCRIPTPATH}config/${REPO_CONFIG}" -distribution="${release}" -component="${release}-utils" \
			-comment="Armbian ${release} utilities" "${release}-utils" >/dev/null
		fi
		if [[ -z $(aptly repo list -config="${SCRIPTPATH}config/${REPO_CONFIG}" -raw | awk '{print $(NF)}' | grep "${release}-desktop") ]]; then
			aptly repo create -config="${SCRIPTPATH}config/${REPO_CONFIG}" -distribution="${release}" -component="${release}-desktop" \
			-comment="Armbian ${release} desktop" "${release}-desktop" >/dev/null
		fi


		# adding main
		if find "${DEB_STORAGE}"/ -maxdepth 1 -type f -name "*.deb" 2>/dev/null | grep -q .; then
			[[ "${ADDING_PACKAGES}" == true ]] && adding_packages "$release" "" "main"
		else
			aptly repo add -config="${SCRIPTPATH}config/${REPO_CONFIG}" "${release}" "${SCRIPTPATH}config/templates/example.deb" >/dev/null
		fi

		local COMPONENTS="main"

		# adding main distribution packages
		if find "${DEB_STORAGE}/${release}" -maxdepth 1 -type f -name "*.deb" 2>/dev/null | grep -q .; then
			[[ "${ADDING_PACKAGES}" == true ]] && adding_packages "${release}-utils" "/${release}" "release packages"
		else
			# workaround - add dummy package to not trigger error
			aptly repo add -config="${SCRIPTPATH}config/${REPO_CONFIG}" "${release}" "${SCRIPTPATH}config/templates/example.deb" >/dev/null
		fi

		# adding release-specific utils
		if find "${DEB_STORAGE}/extra/${release}-utils" -maxdepth 1 -type f -name "*.deb" 2>/dev/null | grep -q .; then
			[[ "${ADDING_PACKAGES}" == true ]] && adding_packages "${release}-utils" "/extra/${release}-utils" "release utils"
		else
			aptly repo add -config="${SCRIPTPATH}config/${REPO_CONFIG}" "${release}-utils" "${SCRIPTPATH}config/templates/example.deb" >/dev/null
		fi
		COMPONENTS="${COMPONENTS} ${release}-utils"

		# adding desktop
		if find "${DEB_STORAGE}/extra/${release}-desktop" -maxdepth 1 -type f -name "*.deb" 2>/dev/null | grep -q .; then
			[[ "${ADDING_PACKAGES}" == true ]] && adding_packages "${release}-desktop" "/extra/${release}-desktop" "desktop"
		else
			# workaround - add dummy package to not trigger error
			aptly repo add -config="${SCRIPTPATH}config/${REPO_CONFIG}" "${release}-desktop" "${SCRIPTPATH}config/templates/example.deb" >/dev/null
		fi
		COMPONENTS="${COMPONENTS} ${release}-desktop"

		local mainnum utilnum desknum
		mainnum=$(aptly repo show -with-packages -config="${SCRIPTPATH}config/${REPO_CONFIG}" "${release}" | grep "Number of packages" | awk '{print $NF}')
		utilnum=$(aptly repo show -with-packages -config="${SCRIPTPATH}config/${REPO_CONFIG}" "${release}-desktop" | grep "Number of packages" | awk '{print $NF}')
		desknum=$(aptly repo show -with-packages -config="${SCRIPTPATH}config/${REPO_CONFIG}" "${release}-utils" | grep "Number of packages" | awk '{print $NF}')

		if [ $mainnum -gt 0 ] && [ $utilnum -gt 0 ] && [ $desknum -gt 0 ]; then

			# publish
			aptly publish \
			-acquire-by-hash \
			-passphrase="${GPG_PASS}" \
			-origin="Armbian" \
			-label="Armbian" \
			-config="${SCRIPTPATH}config/${REPO_CONFIG}" \
			-component="${COMPONENTS// /,}" \
			-distribution="${release}" repo "${release}" ${COMPONENTS//main/} >/dev/null

			if [[ $? -ne 0 ]]; then
				display_alert "Publishing failed" "${release}" "err"
				errors=$((errors+1))
				exit 0
			fi
		else
			errors=$((errors+1))
			local err_txt=": All components must be present: main, utils and desktop for first build"
		fi

	done

	# cleanup
	display_alert "Cleaning repository" "${DEB_STORAGE}" "info"
	aptly db cleanup -config="${SCRIPTPATH}config/${REPO_CONFIG}"

	# display what we have
	echo ""
	display_alert "List of local repos" "local" "info"
	(aptly repo list -config="${SCRIPTPATH}config/${REPO_CONFIG}") | grep -E packages

	# remove debs if no errors found
	if [[ $errors -eq 0 ]]; then
		if [[ "$2" == "delete" ]]; then
			display_alert "Purging incoming debs" "all" "ext"
			find "${DEB_STORAGE}" -name "*.deb" -type f -delete
		fi
	else
		display_alert "There were some problems $err_txt" "leaving incoming directory intact" "err"
	fi

}

repo-manipulate()
{
# repository manipulation
# "show" displays packages in each repository
# "server" serve repository - useful for local diagnostics
# "unique" manually select which package should be removed from all repositories
# "update" search for new files in output/debs* to add them to repository
# "purge" leave only last 5 versions

	local DISTROS=("stretch" "bionic" "buster" "bullseye" "focal" "hirsute" "impish" "jammy" "sid")
	#local DISTROS=($(grep -rw config/distributions/*/ -e 'supported' | cut -d"/" -f3))

	case $@ in

		serve)
			# display repository content
			display_alert "Serving content" "common utils" "ext"
			aptly serve -listen=$(ip -f inet addr | grep -Po 'inet \K[\d.]+' | grep -v 127.0.0.1 | head -1):80 -config="${SCRIPTPATH}config/${REPO_CONFIG}"
			exit 0
			;;

		show)
			# display repository content
			for release in "${DISTROS[@]}"; do
				display_alert "Displaying repository contents for" "$release" "ext"
				aptly repo show -with-packages -config="${SCRIPTPATH}config/${REPO_CONFIG}" "${release}" | tail -n +7
				aptly repo show -with-packages -config="${SCRIPTPATH}config/${REPO_CONFIG}" "${release}-desktop" | tail -n +7
			done
			display_alert "Displaying repository contents for" "common utils" "ext"
			aptly repo show -with-packages -config="${SCRIPTPATH}config/${REPO_CONFIG}" utils | tail -n +7
			echo "done."
			exit 0
			;;

		unique)
			# which package should be removed from all repositories
			IFS=$'\n'
			while true; do
				LIST=()
				for release in "${DISTROS[@]}"; do
					LIST+=( $(aptly repo show -with-packages -config="${SCRIPTPATH}config/${REPO_CONFIG}" "${release}" | tail -n +7) )
					LIST+=( $(aptly repo show -with-packages -config="${SCRIPTPATH}config/${REPO_CONFIG}" "${release}-desktop" | tail -n +7) )
				done
				LIST+=( $(aptly repo show -with-packages -config="${SCRIPTPATH}config/${REPO_CONFIG}" utils | tail -n +7) )
				LIST=( $(echo "${LIST[@]}" | tr ' ' '\n' | sort -u))
				new_list=()
				# create a human readable menu
				for ((n=0;n<$((${#LIST[@]}));n++));
				do
					new_list+=( "${LIST[$n]}" )
					new_list+=( "" )
				done
				LIST=("${new_list[@]}")
				LIST_LENGTH=$((${#LIST[@]}/2));
				exec 3>&1
				TARGET_VERSION=$(dialog --cancel-label "Cancel" --backtitle "BACKTITLE" --no-collapse --title "Remove packages from repositories" --clear --menu "Delete" $((9+${LIST_LENGTH})) 82 65 "${LIST[@]}" 2>&1 1>&3)
				exitstatus=$?;
				exec 3>&-
				if [[ $exitstatus -eq 0 ]]; then
					for release in "${DISTROS[@]}"; do
						aptly repo remove -config="${SCRIPTPATH}config/${REPO_CONFIG}"  "${release}" "$TARGET_VERSION"
						aptly repo remove -config="${SCRIPTPATH}config/${REPO_CONFIG}"  "${release}-desktop" "$TARGET_VERSION"
					done
					aptly repo remove -config="${SCRIPTPATH}config/${REPO_CONFIG}" "utils" "$TARGET_VERSION"
				else
					exit 1
				fi
				aptly db cleanup -config="${SCRIPTPATH}config/${REPO_CONFIG}" > /dev/null 2>&1
			done
			;;

		update)
			# display full help test
			# run repository update
			addtorepo "update" ""
			# add a key to repo
			cp "${SCRIPTPATH}"config/armbian.key "${REPO_STORAGE}"/public/
			exit 0
			;;

		purge)
			for release in "${DISTROS[@]}"; do
				repo-remove-old-packages "$release" "armhf" "5"
				repo-remove-old-packages "$release" "arm64" "5"
				repo-remove-old-packages "$release" "amd64" "5"
				repo-remove-old-packages "$release" "all" "5"
				aptly -config="${SCRIPTPATH}config/${REPO_CONFIG}" -passphrase="${GPG_PASS}" publish update "${release}" > /dev/null 2>&1
			done
			exit 0
			;;

                purgeedge)
                        for release in "${DISTROS[@]}"; do
				repo-remove-old-packages "$release" "armhf" "3" "edge"
				repo-remove-old-packages "$release" "arm64" "3" "edge"
				repo-remove-old-packages "$release" "amd64" "3" "edge"
				repo-remove-old-packages "$release" "all" "3" "edge"
				aptly -config="${SCRIPTPATH}config/${REPO_CONFIG}" -passphrase="${GPG_PASS}" publish update "${release}" > /dev/null 2>&1
                        done
                        exit 0
                        ;;


		purgesource)
			for release in "${DISTROS[@]}"; do
				aptly repo remove -config="${SCRIPTPATH}config/${REPO_CONFIG}" "${release}" 'Name (% *-source*)'
				aptly -config="${SCRIPTPATH}config/${REPO_CONFIG}" -passphrase="${GPG_PASS}" publish update "${release}"  > /dev/null 2>&1
			done
			aptly db cleanup -config="${SCRIPTPATH}config/${REPO_CONFIG}" > /dev/null 2>&1
			exit 0
			;;
		*)

			echo -e "Usage: repository show | serve | unique | create | update | purge | purgesource\n"
			echo -e "\n show           = display repository content"
			echo -e "\n serve          = publish your repositories on current server over HTTP"
			echo -e "\n unique         = manually select which package should be removed from all repositories"
			echo -e "\n update         = updating repository"
			echo -e "\n purge          = removes all but last 5 versions"
			echo -e "\n purgeedge      = removes all but last 3 edge versions"
			echo -e "\n purgesource    = removes all sources\n\n"
			exit 0
			;;

	esac

}

# Removes old packages in the received repo
#
# $1: Repository
# $2: Architecture
# $3: Amount of packages to keep
# $4: Additional search pattern
repo-remove-old-packages() {
	local repo=$1
	local arch=$2
	local keep=$3
	for pkg in $(aptly repo search -config="${SCRIPTPATH}config/${REPO_CONFIG}" "${repo}" "Architecture ($arch)" | grep -v "ERROR: no results" | sort -t '.' -nk4 | grep -e "$4"); do
		local pkg_name
		count=0
		pkg_name=$(echo "${pkg}" | cut -d_ -f1)
		for subpkg in $(aptly repo search -config="${SCRIPTPATH}config/${REPO_CONFIG}" "${repo}" "Name ($pkg_name)"  | grep -v "ERROR: no results" | sort -rt '.' -nk4); do
			((count+=1))
			if [[ $count -gt $keep ]]; then
			pkg_version=$(echo "${subpkg}" | cut -d_ -f2)
			aptly repo remove -config="${SCRIPTPATH}config/${REPO_CONFIG}" "${repo}" "Name ($pkg_name), Version (= $pkg_version)"
			fi
		done
    done
}
