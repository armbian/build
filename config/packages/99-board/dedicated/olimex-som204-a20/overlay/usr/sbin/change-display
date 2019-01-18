#!/bin/bash

# read in board info
[[ -f /etc/armbian-release ]] && source /etc/armbian-release
backtitle="OLinuXino display configurator for Armbian v${VERSION}"

bin_file="/boot/script.bin"
log_file="/var/log/change_display.log"

function change_parameters()
{
	local __parameters=("$@")
	local __fex_file=$(mktemp)
	local __total=${#__parameters[@]}
	local __i=0

	# Convert bin -> fex
	if ! bin2fex $bin_file $__fex_file 2>$log_file; then
		display_error_dialog "Something happened" "Failed converting configuration file!\n\n
Command: bin2fex $bin_file $__fex_file\n
Output:\n
$(cat $log_file)"
		exit 1
	fi

	( for par in "${__parameters[@]}"; do
		local __section=$(awk -F'[|=]' '{print $1}' <<< $par)
		local __parameter=$(awk -F'[|=]' '{print $2}' <<< $par)
		local __value=$(awk -F'[|=]' '{print $3}' <<< $par)

		# Calculate progress
		local __progress=$((100 * (++__i) / $__total))

		# Display progress
		cat << __EOF__
XXX
$__progress

[$__section]$__parameter=$__value
XXX
__EOF__
		# Find section start
		local __section_start=$(grep -m 1 -n "\[$__section]" $__fex_file | cut -d':' -f1)
		if [[ -z $__section_start ]]; then
			# If not found append it to the end of file
			echo -e "[$__section]\n">> $__fex_file
			__section_start=$(grep -m 1 -n "\[$__section]" $__fex_file | cut -d':' -f1)
		fi

		# Find section end
		local __section_end=$(tail -n +$__section_start $__fex_file | grep -n -m 1 "^$" | cut -d':' -f1)
		if [[ -z $__section_end ]]; then
			display_error_dialog "Converting error" "The end of \"$__section\" section is not found!"
		fi
		__section_end=$(($__section_end - 1))

		# Check if line exist in section.
		# If so execute sed, otherwise insert it to the bottom
		if tail -n +$__section_start $__fex_file | head -n $__section_end | grep -q "$__parameter ="; then
			sed -i "$__section_start,+$__section_end s/$__parameter =.*/$__parameter = $__value/" $__fex_file
		else
			sed -i "$(($__section_start + $__section_end)) i $__parameter = $__value" $__fex_file
		fi

	# done )
	done ) | dialog --title "Converting configuration" --backtitle "$backtitle" --gauge "Please wait..." 7 70 0

	# Convert back to bin file
	if ! fex2bin $__fex_file $bin_file 2>$log_file; then
		display_error_dialog "Something happened" "Failed converting configuration file!\n\n
Command: fex2bin $__fex_file $bin_file\n
Output:\n
$(cat $log_file)"
		exit 1
	fi
}

function display_reboot_dialog()
{
	dialog --title "Almost done" --backtitle "$backtitle" --yes-label "Reboot" --no-label "Exit" --yesno "\nAll done. \n
Board must be rebooted to apply changes." 7 70
	[[ $? -ne 0 ]] && exit 0
	reboot
}

function display_error_dialog()
{
	dialog --title "$1" --backtitle "$backtitle" --msgbox "\n$2" 0 0
	exit 1
}
function dispaly_comfirm_dialog()
{
	dialog --title "Confirmation" --backtitle "$backtitle" --yesno "\n$1" 7 74
	[[ $? -ne 0 ]] && exit 1
}

function enable_ts()
{
	sed -i "/a20_tp/d" /etc/modules
	! grep -q "sun4i_ts" /etc/modules && echo "sun4i_ts" >> /etc/modules
}

function disable_ts()
{
	sed -i "/sun4i_ts/d" /etc/modules
	! grep -q "a20_tp" /etc/modules && echo "a20_tp" >> /etc/modules
}

function set_hdmi_resolution()
{
	options=(
		0 "480i"
		1 "576i"
		2 "480p"
		3 "576p"
		4 "720p50"
		5 "720p60"
		6 "1080i50"
		7 "1080i60"
		8 "1080p24"
		9 "1080p50"
		10 "1080p60"
		11 "pal"
		14 "ntsc")

	cmd=(dialog --title "Configure HDMI output" --backtitle "$backtitle" --menu "\nSelect HDMI resolution: \n" 21 60 14)
	choices=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)
	[[ $? -ne 0 ]] && exit 1

	for choice in $choices; do
		fex_mode=$choice
		for i in "${!options[@]}"; do
			if [[ "${options[$i]}" == "$choice" ]]; then
				fex_desc=${options[$(($i + 1))]}
				break
			fi
		done
	done

	dispaly_comfirm_dialog "Set HDMI resolution to \"$fex_desc\"?"

	# Set parameters
	hdmi_parameters=(
		"disp_init|screen0_output_type=3"
		"disp_init|screen1_output_type=0"
		"disp_init|screen0_output_mode=$fex_mode"
		"lcd0_para|lcd_used=0"
		"lcd1_para|lcd_used=0"
		"olinuxino_lcd_para|olinuxino_lcd_used=0")

	# Execute parameter change
	change_parameters "${hdmi_parameters[@]}"

	# Remove olinuxino-lcd module and service
	systemctl disable olinuxino-lcd.service 2>/dev/null
	sed -i "/olinuxino-lcd/d" /etc/modules

	disable_ts
}

function set_vga_resolution()
{
	options=(
		0 "1680x1050"
		1 "1440x900"
		2 "1360x768"
		3 "1280x1024"
		4 "1024x768"
		5 "800x600"
		6 "640x480"
		10 "1920x1080"
		11 "1280x720")

	cmd=(dialog --title "Configure VGA output" --backtitle "$backtitle" --menu "\nSelect VGA resolution: \n" 18 60 14)
	choices=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)
	[[ $? -ne 0 ]] && exit 1

	for choice in $choices; do
		fex_mode=$choice
		for i in "${!options[@]}"; do
			if [[ "${options[$i]}" == "$choice" ]]; then
				fex_desc=${options[$(($i + 1))]}
				break
			fi
		done
	done

	dispaly_comfirm_dialog "Set HDMI resolution to \"$fex_desc\"?"

	# Set parameters
	vga_parameters=(
		"disp_init|screen0_output_type=4"
		"disp_init|screen1_output_type=0"
		"disp_init|screen0_output_mode=$fex_mode"
		"lcd0_para|lcd_used=0"
		"lcd1_para|lcd_used=0"
		"olinuxino_lcd_para|olinuxino_lcd_used=0")

	# Execute parameter change
	change_parameters "${vga_parameters[@]}"

	# Remove olinuxino-lcd module and service
	systemctl disable olinuxino-lcd.service 2>/dev/null
	sed -i "/olinuxino-lcd/d" /etc/modules

	disable_ts
}

function disable_output()
{
	dispaly_comfirm_dialog "Disable all display outputs?"

	none_parameters=(
	"disp_init|screen0_output_type=0"
	"disp_init|screen1_output_type=0"
	"lcd0_para|lcd_used=0"
	"lcd1_para|lcd_used=0"
	"olinuxino_lcd_para|olinuxino_lcd_used=0"
	)

	# Execute parameter change
	change_parameters "${none_parameters[@]}"

	# Remove olinuxino-lcd module and service
	systemctl disable olinuxino-lcd.service 2>/dev/null
	sed -i "/olinuxino-lcd/d" /etc/modules

	disable_ts
}

function set_lcd_resolution()
{
	options=(
		1 "LCD-OLinuXino-4.3|480x272"
		2 "LCD-OLinuXino-5|800x480"
		3 "LCD-OLinuXino-7|800x480"
		4 "LCD-OLinuXino-10-Rev.A|1024x600"
		5 "LCD-OLinuXino-10-Rev.B|1024x600"
		6 "LCD-OLinuXino-15.6|1366x768"
		7 "LCD-OLinuXino-15.6FHD|1920x1080")

	cmd=(dialog --title "Configure LCD output" --backtitle "$backtitle" --column-separator "|" --menu "\nSelect LCD panel: \n" 15 60 14)
	choices=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)
	[[ $? -ne 0 ]] && exit 1

	for choice in $choices; do
		fex_mode=$choice
		for i in "${!options[@]}"; do
			if [[ "${options[$i]}" == "$choice" ]]; then
				fex_desc=$(cut -d"|" -f1 <<< ${options[$(($i + 1))]} )
				break
			fi
		done
	done

	dispaly_comfirm_dialog "Select \"$fex_desc\"?"

	for choice in $choices
	do
		case $choice in
			1)
				lcd_parameters=(
					"clock|pll3="

					"disp_init|disp_mode=0"
					"disp_init|screen0_output_type=1"
					"disp_init|screen1_output_type=0"
					"disp_init|fb0_scaler_mode_enable=0"

					"lcd0_para|lcd_used=1"
					"lcd0_para|lcd_x=480"
					"lcd0_para|lcd_y=272"
					"lcd0_para|lcd_dclk_freq=12"
					"lcd0_para|lcd_pwm_not_used=0"
					"lcd0_para|lcd_if=0"
					"lcd0_para|lcd_hbp=2"
					"lcd0_para|lcd_ht=525"
					"lcd0_para|lcd_vbp=2"
					"lcd0_para|lcd_vt=572"
					"lcd0_para|lcd_hv_vspw=10"
					"lcd0_para|lcd_hv_hspw=41"
					"lcd0_para|lcd_hv_if=0"
					"lcd0_para|lcd_lvds_ch=0"
					"lcd0_para|lcd_lvds_mode=0"
					"lcd0_para|lcd_lvds_bitwidth=0"
					"lcd0_para|lcd_frm=1"
					"lcd0_para|lcd_io_cfg0=268435456"
					"lcd0_para|lcd_bl_en_used=0"
					"lcd0_para|lcd_pwm_used=1"

					"lcd0_para|lcdd0=port:PD00<2><0><default><default>"
					"lcd0_para|lcdd1=port:PD01<2><0><default><default>"
					"lcd0_para|lcdd2=port:PD02<2><0><default><default>"
					"lcd0_para|lcdd3=port:PD03<2><0><default><default>"
					"lcd0_para|lcdd4=port:PD04<2><0><default><default>"
					"lcd0_para|lcdd5=port:PD05<2><0><default><default>"
					"lcd0_para|lcdd6=port:PD06<2><0><default><default>"
					"lcd0_para|lcdd7=port:PD07<2><0><default><default>"
					"lcd0_para|lcdd8=port:PD08<2><0><default><default>"
					"lcd0_para|lcdd9=port:PD09<2><0><default><default>"
					"lcd0_para|lcdd10=port:PD10<2><0><default><default>"
					"lcd0_para|lcdd11=port:PD11<2><0><default><default>"
					"lcd0_para|lcdd12=port:PD12<2><0><default><default>"
					"lcd0_para|lcdd13=port:PD13<2><0><default><default>"
					"lcd0_para|lcdd14=port:PD14<2><0><default><default>"
					"lcd0_para|lcdd15=port:PD15<2><0><default><default>"
					"lcd0_para|lcdd16=port:PD16<2><0><default><default>"
					"lcd0_para|lcdd17=port:PD17<2><0><default><default>"
					"lcd0_para|lcdd18=port:PD18<2><0><default><default>"
					"lcd0_para|lcdd19=port:PD19<2><0><default><default>"
					"lcd0_para|lcdd20=port:PD20<2><0><default><default>"
					"lcd0_para|lcdd21=port:PD21<2><0><default><default>"
					"lcd0_para|lcdd22=port:PD22<2><0><default><default>"
					"lcd0_para|lcdd23=port:PD23<2><0><default><default>"
					"lcd0_para|lcdclk=port:PD24<2><0><default><default>"
					"lcd0_para|lcdde=port:PD25<2><0><default><default>"
					"lcd0_para|lcdhsync=port:PD26<2><0><default><default>"
					"lcd0_para|lcdvsync=port:PD27<2><0><default><default>"

					"pwm0_para|pwm_used=1"

					"olinuxino_lcd_para|olinuxino_lcd_used=0"
					)
			;;

			2)
				lcd_parameters=(
					"clock|pll3="

					"disp_init|disp_mode=0"
					"disp_init|screen0_output_type=1"
					"disp_init|screen1_output_type=0"
					"disp_init|fb0_scaler_mode_enable=0"

					"lcd0_para|lcd_used=1"
					"lcd0_para|lcd_x=800"
					"lcd0_para|lcd_y=480"
					"lcd0_para|lcd_dclk_freq=33"
					"lcd0_para|lcd_pwm_not_used=0"
					"lcd0_para|lcd_if=0"
					"lcd0_para|lcd_hbp=46"
					"lcd0_para|lcd_ht=1055"
					"lcd0_para|lcd_vbp=23"
					"lcd0_para|lcd_vt=1050"
					"lcd0_para|lcd_hv_vspw=1"
					"lcd0_para|lcd_hv_hspw=30"
					"lcd0_para|lcd_hv_if=0"
					"lcd0_para|lcd_lvds_ch=0"
					"lcd0_para|lcd_lvds_mode=0"
					"lcd0_para|lcd_lvds_bitwidth=0"
					"lcd0_para|lcd_frm=1"
					"lcd0_para|lcd_io_cfg0=268435456"
					"lcd0_para|lcd_bl_en_used=0"
					"lcd0_para|lcd_pwm_used=1"

					"lcd0_para|lcdd0=port:PD00<2><0><default><default>"
					"lcd0_para|lcdd1=port:PD01<2><0><default><default>"
					"lcd0_para|lcdd2=port:PD02<2><0><default><default>"
					"lcd0_para|lcdd3=port:PD03<2><0><default><default>"
					"lcd0_para|lcdd4=port:PD04<2><0><default><default>"
					"lcd0_para|lcdd5=port:PD05<2><0><default><default>"
					"lcd0_para|lcdd6=port:PD06<2><0><default><default>"
					"lcd0_para|lcdd7=port:PD07<2><0><default><default>"
					"lcd0_para|lcdd8=port:PD08<2><0><default><default>"
					"lcd0_para|lcdd9=port:PD09<2><0><default><default>"
					"lcd0_para|lcdd10=port:PD10<2><0><default><default>"
					"lcd0_para|lcdd11=port:PD11<2><0><default><default>"
					"lcd0_para|lcdd12=port:PD12<2><0><default><default>"
					"lcd0_para|lcdd13=port:PD13<2><0><default><default>"
					"lcd0_para|lcdd14=port:PD14<2><0><default><default>"
					"lcd0_para|lcdd15=port:PD15<2><0><default><default>"
					"lcd0_para|lcdd16=port:PD16<2><0><default><default>"
					"lcd0_para|lcdd17=port:PD17<2><0><default><default>"
					"lcd0_para|lcdd18=port:PD18<2><0><default><default>"
					"lcd0_para|lcdd19=port:PD19<2><0><default><default>"
					"lcd0_para|lcdd20=port:PD20<2><0><default><default>"
					"lcd0_para|lcdd21=port:PD21<2><0><default><default>"
					"lcd0_para|lcdd22=port:PD22<2><0><default><default>"
					"lcd0_para|lcdd23=port:PD23<2><0><default><default>"
					"lcd0_para|lcdclk=port:PD24<2><0><default><default>"
					"lcd0_para|lcdde=port:PD25<2><0><default><default>"
					"lcd0_para|lcdhsync=port:PD26<2><0><default><default>"
					"lcd0_para|lcdvsync=port:PD27<2><0><default><default>"

					"pwm0_para|pwm_used=1"

					"olinuxino_lcd_para|olinuxino_lcd_used=0"
					)
			;;

			3)
				lcd_parameters=(
					"clock|pll3="

					"disp_init|disp_mode=0"
					"disp_init|screen0_output_type=1"
					"disp_init|screen1_output_type=0"
					"disp_init|fb0_scaler_mode_enable=0"

					"lcd0_para|lcd_used=1"
					"lcd0_para|lcd_x=800"
					"lcd0_para|lcd_y=480"
					"lcd0_para|lcd_dclk_freq=33"
					"lcd0_para|lcd_pwm_not_used=0"
					"lcd0_para|lcd_if=0"
					"lcd0_para|lcd_hbp=46"
					"lcd0_para|lcd_ht=1055"
					"lcd0_para|lcd_vbp=23"
					"lcd0_para|lcd_vt=1050"
					"lcd0_para|lcd_hv_vspw=1"
					"lcd0_para|lcd_hv_hspw=30"
					"lcd0_para|lcd_hv_if=0"
					"lcd0_para|lcd_lvds_ch=0"
					"lcd0_para|lcd_lvds_mode=0"
					"lcd0_para|lcd_lvds_bitwidth=0"
					"lcd0_para|lcd_frm=1"
					"lcd0_para|lcd_io_cfg0=268435456"
					"lcd0_para|lcd_bl_en_used=0"
					"lcd0_para|lcd_pwm_used=1"

					"lcd0_para|lcdd0=port:PD00<2><0><default><default>"
					"lcd0_para|lcdd1=port:PD01<2><0><default><default>"
					"lcd0_para|lcdd2=port:PD02<2><0><default><default>"
					"lcd0_para|lcdd3=port:PD03<2><0><default><default>"
					"lcd0_para|lcdd4=port:PD04<2><0><default><default>"
					"lcd0_para|lcdd5=port:PD05<2><0><default><default>"
					"lcd0_para|lcdd6=port:PD06<2><0><default><default>"
					"lcd0_para|lcdd7=port:PD07<2><0><default><default>"
					"lcd0_para|lcdd8=port:PD08<2><0><default><default>"
					"lcd0_para|lcdd9=port:PD09<2><0><default><default>"
					"lcd0_para|lcdd10=port:PD10<2><0><default><default>"
					"lcd0_para|lcdd11=port:PD11<2><0><default><default>"
					"lcd0_para|lcdd12=port:PD12<2><0><default><default>"
					"lcd0_para|lcdd13=port:PD13<2><0><default><default>"
					"lcd0_para|lcdd14=port:PD14<2><0><default><default>"
					"lcd0_para|lcdd15=port:PD15<2><0><default><default>"
					"lcd0_para|lcdd16=port:PD16<2><0><default><default>"
					"lcd0_para|lcdd17=port:PD17<2><0><default><default>"
					"lcd0_para|lcdd18=port:PD18<2><0><default><default>"
					"lcd0_para|lcdd19=port:PD19<2><0><default><default>"
					"lcd0_para|lcdd20=port:PD20<2><0><default><default>"
					"lcd0_para|lcdd21=port:PD21<2><0><default><default>"
					"lcd0_para|lcdd22=port:PD22<2><0><default><default>"
					"lcd0_para|lcdd23=port:PD23<2><0><default><default>"
					"lcd0_para|lcdclk=port:PD24<2><0><default><default>"
					"lcd0_para|lcdde=port:PD25<2><0><default><default>"
					"lcd0_para|lcdhsync=port:PD26<2><0><default><default>"
					"lcd0_para|lcdvsync=port:PD27<2><0><default><default>"

					"pwm0_para|pwm_used=1"

					"olinuxino_lcd_para|olinuxino_lcd_used=0"
					)
			;;

			4)
				lcd_parameters=(
					"clock|pll3="

					"disp_init|disp_mode=0"
					"disp_init|screen0_output_type=1"
					"disp_init|screen1_output_type=0"
					"disp_init|fb0_scaler_mode_enable=0"

					"lcd0_para|lcd_used=1"
					"lcd0_para|lcd_x=1024"
					"lcd0_para|lcd_y=600"
					"lcd0_para|lcd_dclk_freq=45"
					"lcd0_para|lcd_pwm_not_used=0"
					"lcd0_para|lcd_if=0"
					"lcd0_para|lcd_hbp=160"
					"lcd0_para|lcd_ht=1200"
					"lcd0_para|lcd_vbp=23"
					"lcd0_para|lcd_vt=1250"
					"lcd0_para|lcd_hv_vspw=2"
					"lcd0_para|lcd_hv_hspw=10"
					"lcd0_para|lcd_hv_if=0"
					"lcd0_para|lcd_lvds_ch=0"
					"lcd0_para|lcd_lvds_mode=0"
					"lcd0_para|lcd_lvds_bitwidth=0"
					"lcd0_para|lcd_frm=1"
					"lcd0_para|lcd_io_cfg0=268435456"
					"lcd0_para|lcd_bl_en_used=0"
					"lcd0_para|lcd_pwm_used=1"

					"lcd0_para|lcdd0=port:PD00<2><0><default><default>"
					"lcd0_para|lcdd1=port:PD01<2><0><default><default>"
					"lcd0_para|lcdd2=port:PD02<2><0><default><default>"
					"lcd0_para|lcdd3=port:PD03<2><0><default><default>"
					"lcd0_para|lcdd4=port:PD04<2><0><default><default>"
					"lcd0_para|lcdd5=port:PD05<2><0><default><default>"
					"lcd0_para|lcdd6=port:PD06<2><0><default><default>"
					"lcd0_para|lcdd7=port:PD07<2><0><default><default>"
					"lcd0_para|lcdd8=port:PD08<2><0><default><default>"
					"lcd0_para|lcdd9=port:PD09<2><0><default><default>"
					"lcd0_para|lcdd10=port:PD10<2><0><default><default>"
					"lcd0_para|lcdd11=port:PD11<2><0><default><default>"
					"lcd0_para|lcdd12=port:PD12<2><0><default><default>"
					"lcd0_para|lcdd13=port:PD13<2><0><default><default>"
					"lcd0_para|lcdd14=port:PD14<2><0><default><default>"
					"lcd0_para|lcdd15=port:PD15<2><0><default><default>"
					"lcd0_para|lcdd16=port:PD16<2><0><default><default>"
					"lcd0_para|lcdd17=port:PD17<2><0><default><default>"
					"lcd0_para|lcdd18=port:PD18<2><0><default><default>"
					"lcd0_para|lcdd19=port:PD19<2><0><default><default>"
					"lcd0_para|lcdd20=port:PD20<2><0><default><default>"
					"lcd0_para|lcdd21=port:PD21<2><0><default><default>"
					"lcd0_para|lcdd22=port:PD22<2><0><default><default>"
					"lcd0_para|lcdd23=port:PD23<2><0><default><default>"
					"lcd0_para|lcdclk=port:PD24<2><0><default><default>"
					"lcd0_para|lcdde=port:PD25<2><0><default><default>"
					"lcd0_para|lcdhsync=port:PD26<2><0><default><default>"
					"lcd0_para|lcdvsync=port:PD27<2><0><default><default>"

					"pwm0_para|pwm_used=1"

					"olinuxino_lcd_para|olinuxino_lcd_used=0"
					)
			;;

			5)
				lcd_parameters=(
					"clock|pll3="

					"disp_init|disp_mode=0"
					"disp_init|screen0_output_type=1"
					"disp_init|screen1_output_type=0"
					"disp_init|fb0_scaler_mode_enable=0"

					"lcd0_para|lcd_used=1"
					"lcd0_para|lcd_x=1024"
					"lcd0_para|lcd_y=600"
					"lcd0_para|lcd_dclk_freq=45"
					"lcd0_para|lcd_pwm_not_used=0"
					"lcd0_para|lcd_if=0"
					"lcd0_para|lcd_hbp=160"
					"lcd0_para|lcd_ht=1200"
					"lcd0_para|lcd_vbp=23"
					"lcd0_para|lcd_vt=1250"
					"lcd0_para|lcd_hv_vspw=2"
					"lcd0_para|lcd_hv_hspw=10"
					"lcd0_para|lcd_hv_if=0"
					"lcd0_para|lcd_lvds_ch=0"
					"lcd0_para|lcd_lvds_mode=0"
					"lcd0_para|lcd_lvds_bitwidth=0"
					"lcd0_para|lcd_frm=1"
					"lcd0_para|lcd_io_cfg0=0"
					"lcd0_para|lcd_bl_en_used=0"
					"lcd0_para|lcd_pwm_used=1"

					"lcd0_para|lcdd0=port:PD00<2><0><default><default>"
					"lcd0_para|lcdd1=port:PD01<2><0><default><default>"
					"lcd0_para|lcdd2=port:PD02<2><0><default><default>"
					"lcd0_para|lcdd3=port:PD03<2><0><default><default>"
					"lcd0_para|lcdd4=port:PD04<2><0><default><default>"
					"lcd0_para|lcdd5=port:PD05<2><0><default><default>"
					"lcd0_para|lcdd6=port:PD06<2><0><default><default>"
					"lcd0_para|lcdd7=port:PD07<2><0><default><default>"
					"lcd0_para|lcdd8=port:PD08<2><0><default><default>"
					"lcd0_para|lcdd9=port:PD09<2><0><default><default>"
					"lcd0_para|lcdd10=port:PD10<2><0><default><default>"
					"lcd0_para|lcdd11=port:PD11<2><0><default><default>"
					"lcd0_para|lcdd12=port:PD12<2><0><default><default>"
					"lcd0_para|lcdd13=port:PD13<2><0><default><default>"
					"lcd0_para|lcdd14=port:PD14<2><0><default><default>"
					"lcd0_para|lcdd15=port:PD15<2><0><default><default>"
					"lcd0_para|lcdd16=port:PD16<2><0><default><default>"
					"lcd0_para|lcdd17=port:PD17<2><0><default><default>"
					"lcd0_para|lcdd18=port:PD18<2><0><default><default>"
					"lcd0_para|lcdd19=port:PD19<2><0><default><default>"
					"lcd0_para|lcdd20=port:PD20<2><0><default><default>"
					"lcd0_para|lcdd21=port:PD21<2><0><default><default>"
					"lcd0_para|lcdd22=port:PD22<2><0><default><default>"
					"lcd0_para|lcdd23=port:PD23<2><0><default><default>"
					"lcd0_para|lcdclk=port:PD24<2><0><default><default>"
					"lcd0_para|lcdde=port:PD25<2><0><default><default>"
					"lcd0_para|lcdhsync=port:PD26<2><0><default><default>"
					"lcd0_para|lcdvsync=port:PD27<2><0><default><default>"

					"pwm0_para|pwm_used=1"

					"olinuxino_lcd_para|olinuxino_lcd_used=0"
					)
			;;

			6)

				lcd_parameters=(
					"clock|pll3=297"

					"disp_init|disp_mode=0"
					"disp_init|screen0_output_type=1"
					"disp_init|screen1_output_type=0"
					"disp_init|fb0_scaler_mode_enable=1"

					"lcd0_para|lcd_used=1"
					"lcd0_para|lcd_x=1366"
					"lcd0_para|lcd_y=768"
					"lcd0_para|lcd_dclk_freq=70"
					"lcd0_para|lcd_pwm_not_used=1"
					"lcd0_para|lcd_if=3"
					"lcd0_para|lcd_hbp=54"
					"lcd0_para|lcd_ht=1440"
					"lcd0_para|lcd_vbp=23"
					"lcd0_para|lcd_vt=1616"
					"lcd0_para|lcd_hv_vspw=0"
					"lcd0_para|lcd_hv_hspw=0"
					"lcd0_para|lcd_hv_if=0"
					"lcd0_para|lcd_lvds_ch=0"
					"lcd0_para|lcd_lvds_mode=0"
					"lcd0_para|lcd_lvds_bitwidth=1"
					"lcd0_para|lcd_frm=1"
					"lcd0_para|lcd_io_cfg0=268435456"
					"lcd0_para|lcd_bl_en_used=1"
					"lcd0_para|lcd_pwm_used=0"

					"lcd0_para|lcdd0=port:PD00<3><0><default><default>"
					"lcd0_para|lcdd1=port:PD01<3><0><default><default>"
					"lcd0_para|lcdd2=port:PD02<3><0><default><default>"
					"lcd0_para|lcdd3=port:PD03<3><0><default><default>"
					"lcd0_para|lcdd4=port:PD04<3><0><default><default>"
					"lcd0_para|lcdd5=port:PD05<3><0><default><default>"
					"lcd0_para|lcdd6=port:PD06<3><0><default><default>"
					"lcd0_para|lcdd7=port:PD07<3><0><default><default>"
					"lcd0_para|lcdd8=port:PD08<3><0><default><default>"
					"lcd0_para|lcdd9=port:PD09<3><0><default><default>"
					"lcd0_para|lcdd10=port:PD10<3><0><default><default>"
					"lcd0_para|lcdd11=port:PD11<3><0><default><default>"
					"lcd0_para|lcdd12=port:PD12<3><0><default><default>"
					"lcd0_para|lcdd13=port:PD13<3><0><default><default>"
					"lcd0_para|lcdd14=port:PD14<3><0><default><default>"
					"lcd0_para|lcdd15=port:PD15<3><0><default><default>"
					"lcd0_para|lcdd16=port:PD16<3><0><default><default>"
					"lcd0_para|lcdd17=port:PD17<3><0><default><default>"
					"lcd0_para|lcdd18=port:PD18<3><0><default><default>"
					"lcd0_para|lcdd19=port:PD19<3><0><default><default>"
					"lcd0_para|lcdd20=port:PD20<3><0><default><default>"
					"lcd0_para|lcdd21=port:PD21<3><0><default><default>"
					"lcd0_para|lcdd22="
					"lcd0_para|lcdd23="
					"lcd0_para|lcdclk="
					"lcd0_para|lcdde="
					"lcd0_para|lcdhsync="
					"lcd0_para|lcdvsync="

					"pwm0_para|pwm_used=0"

					"olinuxino_lcd_para|olinuxino_lcd_used=1"
					"olinuxino_lcd_para|backlight_pin=port:PD23<0><default><default><default>"
					"olinuxino_lcd_para|contrast_pin=port:PD24<0><default><default><default>"
				)
			;;

			7)
				lcd_parameters=(
					"clock|pll3=297"

					"disp_init|disp_mode=0"
					"disp_init|screen0_output_type=1"
					"disp_init|screen1_output_type=0"
					"disp_init|fb0_scaler_mode_enable=1"

					"lcd0_para|lcd_used=1"
					"lcd0_para|lcd_x=1920"
					"lcd0_para|lcd_y=1080"
					"lcd0_para|lcd_dclk_freq=152"
					"lcd0_para|lcd_pwm_not_used=1"
					"lcd0_para|lcd_if=3"
					"lcd0_para|lcd_hbp=100"
					"lcd0_para|lcd_ht=2226"
					"lcd0_para|lcd_vbp=23"
					"lcd0_para|lcd_vt=2284"
					"lcd0_para|lcd_hv_vspw=0"
					"lcd0_para|lcd_hv_hspw=0"
					"lcd0_para|lcd_hv_if=1"
					"lcd0_para|lcd_lvds_ch=1"
					"lcd0_para|lcd_lvds_mode=0"
					"lcd0_para|lcd_lvds_bitwidth=1"
					"lcd0_para|lcd_frm=1"
					"lcd0_para|lcd_io_cfg0=268435456"
					"lcd0_para|lcd_bl_en_used=1"
					"lcd0_para|lcd_pwm_used=0"

					"lcd0_para|lcdd0=port:PD00<3><0><default><default>"
					"lcd0_para|lcdd1=port:PD01<3><0><default><default>"
					"lcd0_para|lcdd2=port:PD02<3><0><default><default>"
					"lcd0_para|lcdd3=port:PD03<3><0><default><default>"
					"lcd0_para|lcdd4=port:PD04<3><0><default><default>"
					"lcd0_para|lcdd5=port:PD05<3><0><default><default>"
					"lcd0_para|lcdd6=port:PD06<3><0><default><default>"
					"lcd0_para|lcdd7=port:PD07<3><0><default><default>"
					"lcd0_para|lcdd8=port:PD08<3><0><default><default>"
					"lcd0_para|lcdd9=port:PD09<3><0><default><default>"
					"lcd0_para|lcdd10=port:PD10<3><0><default><default>"
					"lcd0_para|lcdd11=port:PD11<3><0><default><default>"
					"lcd0_para|lcdd12=port:PD12<3><0><default><default>"
					"lcd0_para|lcdd13=port:PD13<3><0><default><default>"
					"lcd0_para|lcdd14=port:PD14<3><0><default><default>"
					"lcd0_para|lcdd15=port:PD15<3><0><default><default>"
					"lcd0_para|lcdd16=port:PD16<3><0><default><default>"
					"lcd0_para|lcdd17=port:PD17<3><0><default><default>"
					"lcd0_para|lcdd18=port:PD18<3><0><default><default>"
					"lcd0_para|lcdd19=port:PD19<3><0><default><default>"
					"lcd0_para|lcdd20=port:PD20<3><0><default><default>"
					"lcd0_para|lcdd21=port:PD21<3><0><default><default>"
					"lcd0_para|lcdd22="
					"lcd0_para|lcdd23="
					"lcd0_para|lcdclk="
					"lcd0_para|lcdde="
					"lcd0_para|lcdhsync="
					"lcd0_para|lcdvsync="

					"pwm0_para|pwm_used=0"

					"olinuxino_lcd_para|olinuxino_lcd_used=1"
					"olinuxino_lcd_para|backlight_pin=port:PD23<0><default><default><default>"
					"olinuxino_lcd_para|contrast_pin=port:PD24<0><default><default><default>"
				)
			;;
		esac
	done

	# Enable touchscreen
	if [[ $fex_desc != "LCD-OLinuXino-15.6"* ]]; then
		dialog --title "Configure touchscreen" --backtitle "$backtitle" --yesno "\nEnable touchscreen?\nThis will disable core temperature monitor!" 7 74
		if [[ $? -eq 0 ]]; then

			if [[ $fex_desc == "LCD-OLinuXino-5" ]]; then
				lcd_parameters+=("ctp_para|ctp_used=1")
				lcd_parameters+=("rtp_para|rtp_used=0")
				disable_ts
			else
				lcd_parameters+=("ctp_para|ctp_used=0")
				lcd_parameters+=("rtp_para|rtp_used=1")
				enable_ts
			fi

		else
			lcd_parameters+=("ctp_para|ctp_used=0")
			lcd_parameters+=("rtp_para|rtp_used=0")
			disable_ts
		fi

		# Disable olinuxino-lcd module and service
		sed -i "/olinuxino-lcd/d" /etc/modules
		systemctl disable olinuxino-lcd.service 2>/dev/null
	else
		# LCD-OLinuXino-15.6 doesn't support TS
		lcd_parameters+=("ctp_para|ctp_used=0")
		lcd_parameters+=("rtp_para|rtp_used=0")
		disable_ts

		# Enable olinuxino-lcd module and service
		! grep -q "olinuxino-lcd" /etc/modules && echo "olinuxino-lcd" >> /etc/modules
		if [[ $fex_desc == "LCD-OLinuXino-15.6FHD" ]]; then
			systemctl enable olinuxino-lcd.service 2>/dev/null
		fi
	fi

	# Execute parameter change
	change_parameters "${lcd_parameters[@]}"
}

function main()
{
	# This tool must run under root
	if [[ $EUID -ne 0 ]]; then
		echo "This tool must run as root. Exiting ..." >&2
		exit 1
	fi

	# This tool is working with default branch only
	if [[ $BRANCH != default ]]; then
		echo "This tool work with default branch only. Exiting ..." >&2
		exit 1
	fi

	# Set options
	options=(1 "Enable HDMI display output" 2 "Enable VGA display output" 3 "Enable LCD display output" 4 "Disable all display outputs")

	cmd=(dialog --title "Configure display output" --backtitle "$backtitle" --menu "\nChoose an option: \n" 14 60 7)
	choices=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)
	[[ $? -ne 0 ]] && exit 1

	for choice in $choices
	do
		case $choice in
			1)
				set_hdmi_resolution
			;;

			2)
				set_vga_resolution
			;;

			3)
				set_lcd_resolution
			;;

			4)
				disable_output
			;;
		esac
	done

	display_reboot_dialog
}
main "$@"
