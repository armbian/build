# overlays fixup script
# implements (or rather substitutes) overlay arguments functionality
# using u-boot scripting, environment variables and "fdt" command

setenv decompose_pin 'setexpr tmp_pinctrl sub "GPIO(0|1|2|3|4)_\\S\\d+" "\\1";
setexpr tmp_bank sub "GPIO\\d_(\\S)\\d+" "\\1";
test "${tmp_bank}" = "A" && setenv tmp_bank 0;
test "${tmp_bank}" = "B" && setenv tmp_bank 1;
test "${tmp_bank}" = "C" && setenv tmp_bank 2;
test "${tmp_bank}" = "D" && setenv tmp_bank 3;
setexpr tmp_pin sub "GPIO\\d_\\S(\\d+)" "\\1";
setexpr tmp_bank ${tmp_bank} * 8;
setexpr tmp_pin ${tmp_bank} + ${tmp_pin}'


if test -n "${param_spinor_spi_bus}"; then
	test "${param_spinor_spi_bus}" = "0" && setenv tmp_spi_path "spi@ff1c0000"
	test "${param_spinor_spi_bus}" = "1" && setenv tmp_spi_path "spi@ff1d0000"
	test "${param_spinor_spi_bus}" = "2" && setenv tmp_spi_path "spi@ff1e0000"
	test "${param_spinor_spi_bus}" = "3" && setenv tmp_spi_path "spi@ff1f0000"
	fdt set /${tmp_spi_path} status "okay"
	fdt set /${tmp_spi_path}/spiflash@0 status "okay"
	if test -n "${param_spinor_max_freq}"; then
		fdt set /${tmp_spi_path}/spiflash@0 spi-max-frequency "<${param_spinor_max_freq}>"
	fi
	if test "${param_spinor_spi_cs}" = "1"; then
		fdt set /${tmp_spi_path}/spiflash@0 reg "<1>"
	fi
	env delete tmp_spi_path
fi

if test -n "${param_spidev_spi_bus}"; then
	test "${param_spidev_spi_bus}" = "0" && setenv tmp_spi_path "spi@ff1c0000"
	test "${param_spidev_spi_bus}" = "1" && setenv tmp_spi_path "spi@ff1d0000"
	test "${param_spidev_spi_bus}" = "2" && setenv tmp_spi_path "spi@ff1e0000"
	test "${param_spidev_spi_bus}" = "3" && setenv tmp_spi_path "spi@ff1f0000"
	fdt set /${tmp_spi_path} status "okay"
	fdt set /${tmp_spi_path}/spidev status "okay"
	if test -n "${param_spidev_max_freq}"; then
		fdt set /${tmp_spi_path}/spidev spi-max-frequency "<${param_spidev_max_freq}>"
	fi
	if test "${param_spidev_spi_cs}" = "1"; then
		fdt set /${tmp_spi_path}/spidev reg "<1>";
	fi
fi

if test -n "${param_w1_pin}"; then
	setenv tmp_pinctrl "${param_w1_pin}"
	setenv tmp_bank "${param_w1_pin}"
	setenv tmp_pin "${param_w1_pin}"
	run decompose_pin
	#echo "${param_w1_pin} ---> pinctrl = ${tmp_pinctrl}"
	#echo "${param_w1_pin} ---> bank = ${tmp_bank}"
	#echo "${param_w1_pin} ---> pin = ${tmp_pin}"
	fdt get value tmp_pinctrl /__symbols__	gpio${tmp_pinctrl}
	#echo "${param_w1_pin} ---> tmp_pinctrl = ${tmp_pinctrl}"
	fdt get value tmp_phandle ${tmp_pinctrl} phandle
	#echo "${param_w1_pin} ---> tmp_phandle = ${tmp_phandle}"
	fdt set /onewire@0 gpios "<${tmp_phandle} 0x000000${tmp_pin} 0 0>"
	env delete tmp_pinctrl tmp_bank tmp_pin tmp_phandle
fi

