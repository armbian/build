bootpart=1:1
bootdir=
finduuid=part uuid \${boot} 1:2 uuid
check_beaglebadge=if test "${fdtfile}" = "ti/k3-am62l3-badge.dtb"; then rdaddr=0x84900000; name_overlays=ti/k3-am62l3-badge-eink-gdey042t81.dtbo; fi
name_rd=uInitrd
get_rd_mmc=load mmc ${bootpart} ${rdaddr} ${bootdir}/${name_rd}

uenvcmd=run check_beaglebadge; run get_rd_${boot}; env set rd_spec ${rdaddr}:${filesize}; setexpr fdtfile sub ti/ti ti; run bootcmd_ti_mmc

optargs=vt.global_cursor_default=0
