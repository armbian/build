#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2024 Armbian
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

# Validate the dts/dtb file against dt bindings found in "linux/Documentation/devicetree/bindings/"
# See slide 15 in https://elinux.org/images/1/17/How_to_Get_Your_DT_Schema_Bindings_Accepted_in_Less_than_10_Iterations_-_Krzysztof_Kozlowski%2C_Linaro_-_ELCE_2023.pdf
function validate_dts() {
	[[ -z "${BOOT_FDT_FILE}" ]] && exit_with_error "BOOT_FDT_FILE not set! No dts file to validate."
	display_alert "Validating dts/dtb file for selected board" "${BOOT_FDT_FILE} ; see output below" "info"

	# "make CHECK_DTBS=y" uses the pip modules "dtschema" and "yamllint"
	prepare_python_and_pip

	# Run "make CHECK_DTBS=y" for the selected board's dtb file
	run_kernel_make "CHECK_DTBS=y ${BOOT_FDT_FILE}"
}
