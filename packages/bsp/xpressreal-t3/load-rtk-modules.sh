#!/bin/bash

modules=(
	rtk_fw_remoteproc
	rpmsg_rtk
	rtk_rpc_mem
	rtk_krpc_agent
	rtk_urpc_service
	snd_soc_hifi_realtek
	snd_soc_realtek
	rtk_drm
	rtkve1
	rtkve2
)

for module in "${modules[@]}"; do
	echo "Install $module"
	modprobe $module
done
