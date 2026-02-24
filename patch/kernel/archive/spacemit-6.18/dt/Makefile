dtb-$(CONFIG_SOC_SPACEMIT_K1PRO) += k1-pro_sim.dtb k1-pro_fpga.dtb k1-pro_fpga_1x4.dtb \
				  k1-pro_fpga_2x2.dtb k1-pro_qemu.dtb k1-pro_verify.dtb
dtb-$(CONFIG_SOC_SPACEMIT_K1X) += k1-x_fpga.dtb k1-x_fpga_1x4.dtb k1-x_fpga_2x2.dtb k1-x_evb.dtb \
				  k1-x_deb2.dtb k1-x_deb1.dtb k1-x_hs450.dtb k1-x_kx312.dtb \
				  k1-x_MINI-PC.dtb k1-x_MUSE-N1.dtb k1-x_mingo.dtb \
				  k1-x_MUSE-Pi.dtb k1-x_milkv-jupiter.dtb m1-x_milkv-jupiter.dtb \
				  k1-x_MUSE-Book.dtb k1-x_lpi3a.dtb k1-x_MUSE-Card.dtb \
				  k1-x_MUSE-Paper.dtb k1-x_MUSE-Paper-mini-4g.dtb \
				  k1-x_baton-camera.dtb k1-x_FusionOne.dtb k1-x_orangepi-rv2.dtb \
				  k1-x_ZT001H.dtb k1-x_uav.dtb k1-x_bit-brick.dtb

obj-$(CONFIG_BUILTIN_DTB) += $(addsuffix .o, $(dtb-y))

dtb-$(CONFIG_SOC_SPACEMIT_K1X) += k1-bananapi-f3.dtb
dtb-$(CONFIG_SOC_SPACEMIT_K1X) += k1-musepi-pro.dtb
dtb-$(CONFIG_SOC_SPACEMIT_K1X) += x1_orangepi-r2s.dtb
dtb-$(CONFIG_SOC_SPACEMIT_K1X) += x1_orangepi-rv2.dtb

subdir-y += overlay
