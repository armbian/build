bootpart=1:1
bootdir=
finduuid=part uuid \${boot} 1:2 uuid
name_rd=uInitrd
get_rd_mmc=load mmc ${bootpart} ${rdaddr} ${bootdir}/${name_rd}
name_fdt=dtb/ti/k3-am625-sk.dtb

uenvcmd=run init_${boot}; run get_kern_${boot}; run get_rd_${boot}; env set rd_spec ${rdaddr}:${filesize}; run get_fdt_${boot}; run run_kern
