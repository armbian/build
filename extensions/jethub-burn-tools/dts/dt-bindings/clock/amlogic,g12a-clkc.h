/*
 * include/dt-bindings/clock/g12a-clkc.h
 *
 * Copyright (C) 2017 Amlogic, Inc. All rights reserved.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
 * more details.
 *
 */

#ifndef __G12A_CLKC_H
#define __G12A_CLKC_H

/*
 * CLKID index values
 */

#define CLKID_SYS_PLL           0
#define CLKID_FIXED_PLL         1
#define CLKID_FCLK_DIV2         2
#define CLKID_FCLK_DIV3         3
#define CLKID_FCLK_DIV4         4
#define CLKID_FCLK_DIV5         5
#define CLKID_FCLK_DIV7         6
#define CLKID_GP0_PLL           7
#define CLKID_HIFI_PLL          8
#define CLKID_MPEG_SEL          9
#define CLKID_MPEG_DIV          10
#define CLKID_CLK81             11
#define CLKID_MPLL0             12
#define CLKID_MPLL1             13
#define CLKID_MPLL2             14
#define CLKID_MPLL3             15
#define CLKID_CPU_FCLK_P00      16
#define CLKID_CPU_FCLK_P01      17
#define CLKID_CPU_FCLK_P0       18
#define CLKID_CPU_FCLK_P10      19
#define CLKID_CPU_FCLK_P11      20
#define CLKID_CPU_FCLK_P1       21
#define CLKID_CPU_FCLK_P        22
#define CLKID_CPU_CLK           23
#define CLKID_PCIE_PLL          24
#define CLKID_PCIE_MUX          25
#define CLKID_PCIE_REF          26
#define CLKID_PCIE_INPUT_GATE   27
#define CLKID_PCIE_CML_EN0      28
#define CLKID_PCIE_CML_EN1      29
#define CLKID_MIPI_ENABLE_GATE  30
#define CLKID_MIPI_BANDGAP_GATE 31
#define CLKID_FCLK_DIV2P5       32

/*HHI_GCLK_MPEG0: 0x50*/
#define GATE_BASE0              33
#define CLKID_DDR               (GATE_BASE0 + 0)
#define CLKID_DOS               (GATE_BASE0 + 1)
#define CLKID_AUDIO_LOCKER      (GATE_BASE0 + 2)
#define CLKID_MIPI_DSI_HOST     (GATE_BASE0 + 3)
#define CLKID_ETH_PHY           (GATE_BASE0 + 4)
#define CLKID_ISA               (GATE_BASE0 + 5)
#define CLKID_PL301             (GATE_BASE0 + 6)
#define CLKID_PERIPHS           (GATE_BASE0 + 7)
#define CLKID_SPICC0            (GATE_BASE0 + 8)
#define CLKID_I2C               (GATE_BASE0 + 9)
#define CLKID_SANA              (GATE_BASE0 + 10)
#define CLKID_SD                (GATE_BASE0 + 11)
#define CLKID_RNG0              (GATE_BASE0 + 12)
#define CLKID_UART0             (GATE_BASE0 + 13)
#define CLKID_SPICC1            (GATE_BASE0 + 14)
#define CLKID_HIU_REG           (GATE_BASE0 + 15)
#define CLKID_MIPI_DSI_PHY      (GATE_BASE0 + 16)
#define CLKID_ASSIST_MISC       (GATE_BASE0 + 17)
#define CLKID_SD_EMMC_A         (GATE_BASE0 + 18)
#define CLKID_SD_EMMC_B         (GATE_BASE0 + 19)
#define CLKID_SD_EMMC_C         (GATE_BASE0 + 20)
#define CLKID_ACODEC            (GATE_BASE0 + 21)

/*HHI_GCLK_MPEG1: 0x51*/
#define GATE_BASE1              (GATE_BASE0 + 22)
#define CLKID_AUDIO             (GATE_BASE1 + 0)
#define CLKID_ETH_CORE          (GATE_BASE1 + 1)
#define CLKID_DEMUX             (GATE_BASE1 + 2)
#define CLKID_AIFIFO            (GATE_BASE1 + 3)
#define CLKID_ADC               (GATE_BASE1 + 4)
#define CLKID_UART1             (GATE_BASE1 + 5)
#define CLKID_G2D               (GATE_BASE1 + 6)
#define CLKID_RESET             (GATE_BASE1 + 7)
#define CLKID_PCIE_COMB         (GATE_BASE1 + 8)
#define CLKID_DOS_PARSER        (GATE_BASE1 + 9)
#define CLKID_USB_GENERAL       (GATE_BASE1 + 10)
#define CLKID_PCIE_PHY          (GATE_BASE1 + 11)
#define CLKID_AHB_ARB0          (GATE_BASE1 + 12)

/*HHI_GCLK_MPEG2: 0x52*/
#define GATE_BASE2              (GATE_BASE1 + 13)
#define CLKID_AHB_DATA_BUS      (GATE_BASE2 + 0)
#define CLKID_AHB_CTRL_BUS      (GATE_BASE2 + 1)
#define CLKID_HTX_HDCP22        (GATE_BASE2 + 2)
#define CLKID_HTX_PCLK          (GATE_BASE2 + 3)
#define CLKID_BT656             (GATE_BASE2 + 4)
#define CLKID_USB1_TO_DDR       (GATE_BASE2 + 5)
#define CLKID_MMC_PCLK          (GATE_BASE2 + 6)
#define CLKID_UART2             (GATE_BASE2 + 7)
#define CLKID_VPU_INTR          (GATE_BASE2 + 8)
#define CLKID_GIC               (GATE_BASE2 + 9)

/*HHI_GCLK_OTHER: 0x54*/
#define GATE_BASE3              (GATE_BASE2 + 10)
#define CLKID_VCLK2_VENCI0      (GATE_BASE3 + 0)
#define CLKID_VCLK2_VENCI1      (GATE_BASE3 + 1)
#define CLKID_VCLK2_VENCP0      (GATE_BASE3 + 2)
#define CLKID_VCLK2_VENCP1      (GATE_BASE3 + 3)
#define CLKID_VCLK2_VENCT0      (GATE_BASE3 + 4)
#define CLKID_VCLK2_VENCT1      (GATE_BASE3 + 5)
#define CLKID_VCLK2_OTHER       (GATE_BASE3 + 6)
#define CLKID_VCLK2_ENCI        (GATE_BASE3 + 7)
#define CLKID_VCLK2_ENCP        (GATE_BASE3 + 8)
#define CLKID_DAC_CLK           (GATE_BASE3 + 9)
#define CLKID_AOCLK_GATE        (GATE_BASE3 + 10)
#define CLKID_IEC958_GATE       (GATE_BASE3 + 11)
#define CLKID_ENC480P           (GATE_BASE3 + 12)
#define CLKID_RNG1              (GATE_BASE3 + 13)
#define CLKID_VCLK2_ENCT        (GATE_BASE3 + 14)
#define CLKID_VCLK2_ENCL        (GATE_BASE3 + 15)
#define CLKID_VCLK2_VENCLMMC    (GATE_BASE3 + 16)
#define CLKID_VCLK2_VENCL       (GATE_BASE3 + 17)
#define CLKID_VCLK2_OTHER1      (GATE_BASE3 + 18)

/*HHI_GCLK_SP_MPEG: 0x55*/
#define GATE_BASE4              (GATE_BASE3 + 19)
#define CLKID_EFUSE             (GATE_BASE4 + 0)

#define GATE_AO_BASE            (GATE_BASE4 + 1)
#define CLKID_AO_MEDIA_CPU      (GATE_AO_BASE + 0)
#define CLKID_AO_AHB_SRAM       (GATE_AO_BASE + 1)
#define CLKID_AO_AHB_BUS        (GATE_AO_BASE + 2)
#define CLKID_AO_IFACE          (GATE_AO_BASE + 3)
#define CLKID_AO_I2C            (GATE_AO_BASE + 4)

#define OTHER_BASE              (GATE_AO_BASE + 5)
#define CLKID_SD_EMMC_A_P0_MUX  (OTHER_BASE + 0)
#define CLKID_SD_EMMC_A_P0_DIV  (OTHER_BASE + 1)
#define CLKID_SD_EMMC_A_P0_GATE (OTHER_BASE + 2)
#define CLKID_SD_EMMC_A_P0_COMP (OTHER_BASE + 3)
#define CLKID_SD_EMMC_B_P0_MUX  (OTHER_BASE + 4)
#define CLKID_SD_EMMC_B_P0_DIV  (OTHER_BASE + 5)
#define CLKID_SD_EMMC_B_P0_GATE (OTHER_BASE + 6)
#define CLKID_SD_EMMC_B_P0_COMP (OTHER_BASE + 7)
#define CLKID_SD_EMMC_C_P0_MUX  (OTHER_BASE + 8)
#define CLKID_SD_EMMC_C_P0_DIV  (OTHER_BASE + 9)
#define CLKID_SD_EMMC_C_P0_GATE (OTHER_BASE + 10)
#define CLKID_SD_EMMC_C_P0_COMP (OTHER_BASE + 11)
#define CLKID_SD_EMMC_B_MUX     (OTHER_BASE + 12)
#define CLKID_SD_EMMC_B_DIV     (OTHER_BASE + 13)
#define CLKID_SD_EMMC_B_GATE    (OTHER_BASE + 14)
#define CLKID_SD_EMMC_B_COMP    (OTHER_BASE + 15)
#define CLKID_SD_EMMC_C_MUX     (OTHER_BASE + 16)
#define CLKID_SD_EMMC_C_DIV     (OTHER_BASE + 17)
#define CLKID_SD_EMMC_C_GATE    (OTHER_BASE + 18)
#define CLKID_SD_EMMC_C_COMP    (OTHER_BASE + 19)

#define CLKID_GPU_BASE          (OTHER_BASE + 20)
#define CLKID_GPU_P0_MUX        (CLKID_GPU_BASE + 0)
#define CLKID_GPU_P0_DIV        (CLKID_GPU_BASE + 1)
#define CLKID_GPU_P0_GATE       (CLKID_GPU_BASE + 2)
#define CLKID_GPU_P0_COMP       (CLKID_GPU_BASE + 3)
#define CLKID_GPU_P1_MUX        (CLKID_GPU_BASE + 4)
#define CLKID_GPU_P1_DIV        (CLKID_GPU_BASE + 5)
#define CLKID_GPU_P1_GATE       (CLKID_GPU_BASE + 6)
#define CLKID_GPU_P1_COMP       (CLKID_GPU_BASE + 7)
#define CLKID_GPU_MUX           (CLKID_GPU_BASE + 8)

#define CLKID_MEDIA_BASE        (CLKID_GPU_BASE + 9)
#define CLKID_VPU_P0_MUX        (CLKID_MEDIA_BASE + 0)
#define CLKID_VPU_P0_DIV        (CLKID_MEDIA_BASE + 1)
#define CLKID_VPU_P0_GATE       (CLKID_MEDIA_BASE + 2)
#define CLKID_VPU_P0_COMP       (CLKID_MEDIA_BASE + 3)
#define CLKID_VPU_P1_MUX        (CLKID_MEDIA_BASE + 4)
#define CLKID_VPU_P1_DIV        (CLKID_MEDIA_BASE + 5)
#define CLKID_VPU_P1_GATE       (CLKID_MEDIA_BASE + 6)
#define CLKID_VPU_P1_COMP       (CLKID_MEDIA_BASE + 7)
#define CLKID_VPU_MUX           (CLKID_MEDIA_BASE + 8)
#define CLKID_VAPB_P0_MUX       (CLKID_MEDIA_BASE + 9)
#define CLKID_VAPB_P0_DIV       (CLKID_MEDIA_BASE + 10)
#define CLKID_VAPB_P0_GATE      (CLKID_MEDIA_BASE + 11)
#define CLKID_VAPB_P0_COMP      (CLKID_MEDIA_BASE + 12)
#define CLKID_VAPB_P1_MUX       (CLKID_MEDIA_BASE + 13)
#define CLKID_VAPB_P1_DIV       (CLKID_MEDIA_BASE + 14)
#define CLKID_VAPB_P1_GATE      (CLKID_MEDIA_BASE + 15)
#define CLKID_VAPB_P1_COMP      (CLKID_MEDIA_BASE + 16)
#define CLKID_VAPB_MUX          (CLKID_MEDIA_BASE + 17)
#define CLKID_GE2D_GATE         (CLKID_MEDIA_BASE + 18)
#define CLKID_DSI_MEAS_MUX      (CLKID_MEDIA_BASE + 19)
#define CLKID_DSI_MEAS_DIV      (CLKID_MEDIA_BASE + 20)
#define CLKID_DSI_MEAS_GATE     (CLKID_MEDIA_BASE + 21)
#define CLKID_DSI_MEAS_COMP     (CLKID_MEDIA_BASE + 22)
#define CLKID_VPU_CLKB_TMP_COMP (CLKID_MEDIA_BASE + 23)
#define CLKID_VPU_CLKB_COMP     (CLKID_MEDIA_BASE + 24)
#define CLKID_VDEC_P0_MUX       (CLKID_MEDIA_BASE + 25)
#define CLKID_VDEC_P0_DIV       (CLKID_MEDIA_BASE + 26)
#define CLKID_VDEC_P0_GATE      (CLKID_MEDIA_BASE + 27)
#define CLKID_VDEC_P0_COMP      (CLKID_MEDIA_BASE + 28)
#define CLKID_VDEC_P1_MUX       (CLKID_MEDIA_BASE + 29)
#define CLKID_VDEC_P1_DIV       (CLKID_MEDIA_BASE + 30)
#define CLKID_VDEC_P1_GATE      (CLKID_MEDIA_BASE + 31)
#define CLKID_VDEC_P1_COMP      (CLKID_MEDIA_BASE + 32)
#define CLKID_VDEC_MUX          (CLKID_MEDIA_BASE + 33)
#define CLKID_HCODEC_P0_MUX     (CLKID_MEDIA_BASE + 34)
#define CLKID_HCODEC_P0_DIV     (CLKID_MEDIA_BASE + 35)
#define CLKID_HCODEC_P0_GATE    (CLKID_MEDIA_BASE + 36)
#define CLKID_HCODEC_P0_COMP    (CLKID_MEDIA_BASE + 37)
#define CLKID_HCODEC_P1_MUX     (CLKID_MEDIA_BASE + 38)
#define CLKID_HCODEC_P1_DIV     (CLKID_MEDIA_BASE + 39)
#define CLKID_HCODEC_P1_GATE    (CLKID_MEDIA_BASE + 40)
#define CLKID_HCODEC_P1_COMP    (CLKID_MEDIA_BASE + 41)
#define CLKID_HCODEC_MUX        (CLKID_MEDIA_BASE + 42)
/*HEVCB_CLK*/
#define CLKID_HEVC_P0_MUX       (CLKID_MEDIA_BASE + 43)
#define CLKID_HEVC_P0_DIV       (CLKID_MEDIA_BASE + 44)
#define CLKID_HEVC_P0_GATE      (CLKID_MEDIA_BASE + 45)
#define CLKID_HEVC_P0_COMP      (CLKID_MEDIA_BASE + 46)
#define CLKID_HEVC_P1_MUX       (CLKID_MEDIA_BASE + 47)
#define CLKID_HEVC_P1_DIV       (CLKID_MEDIA_BASE + 48)
#define CLKID_HEVC_P1_GATE      (CLKID_MEDIA_BASE + 49)
#define CLKID_HEVC_P1_COMP      (CLKID_MEDIA_BASE + 50)
#define CLKID_HEVC_MUX          (CLKID_MEDIA_BASE + 51)
/*HEVCF_CLK*/
#define CLKID_HEVCF_P0_MUX       (CLKID_MEDIA_BASE + 52)
#define CLKID_HEVCF_P0_DIV       (CLKID_MEDIA_BASE + 53)
#define CLKID_HEVCF_P0_GATE      (CLKID_MEDIA_BASE + 54)
#define CLKID_HEVCF_P0_COMP      (CLKID_MEDIA_BASE + 55)
#define CLKID_HEVCF_P1_MUX       (CLKID_MEDIA_BASE + 56)
#define CLKID_HEVCF_P1_DIV       (CLKID_MEDIA_BASE + 57)
#define CLKID_HEVCF_P1_GATE      (CLKID_MEDIA_BASE + 58)
#define CLKID_HEVCF_P1_COMP      (CLKID_MEDIA_BASE + 59)
#define CLKID_HEVCF_MUX          (CLKID_MEDIA_BASE + 60)
#define CLKID_VPU_CLKC_P0_MUX    (CLKID_MEDIA_BASE + 61)
#define CLKID_VPU_CLKC_P0_DIV    (CLKID_MEDIA_BASE + 62)
#define CLKID_VPU_CLKC_P0_GATE   (CLKID_MEDIA_BASE + 63)
#define CLKID_VPU_CLKC_P0_COMP   (CLKID_MEDIA_BASE + 64)
#define CLKID_VPU_CLKC_P1_MUX    (CLKID_MEDIA_BASE + 65)
#define CLKID_VPU_CLKC_P1_DIV    (CLKID_MEDIA_BASE + 66)
#define CLKID_VPU_CLKC_P1_GATE   (CLKID_MEDIA_BASE + 67)
#define CLKID_VPU_CLKC_P1_COMP   (CLKID_MEDIA_BASE + 68)
#define CLKID_VPU_CLKC_MUX       (CLKID_MEDIA_BASE + 69)
#define CLKID_BT656_MUX		(CLKID_MEDIA_BASE + 70)
#define CLKID_BT656_DIV		(CLKID_MEDIA_BASE + 71)
#define CLKID_BT656_GATE	(CLKID_MEDIA_BASE + 72)
#define CLKID_BT656_COMP	(CLKID_MEDIA_BASE + 73)

#define CLKID_MISC_BASE          (CLKID_MEDIA_BASE + 74)
#define CLKID_SPICC0_MUX         (CLKID_MISC_BASE + 0)
#define CLKID_SPICC0_DIV         (CLKID_MISC_BASE + 1)
#define CLKID_SPICC0_GATE        (CLKID_MISC_BASE + 2)
#define CLKID_SPICC0_COMP        (CLKID_MISC_BASE + 3)
#define CLKID_SPICC1_MUX         (CLKID_MISC_BASE + 4)
#define CLKID_SPICC1_DIV         (CLKID_MISC_BASE + 5)
#define CLKID_SPICC1_GATE        (CLKID_MISC_BASE + 6)
#define CLKID_SPICC1_COMP        (CLKID_MISC_BASE + 7)
#define CLKID_TS_COMP            (CLKID_MISC_BASE + 8)

/*gpio 12M/24M */
#define CLKID_24M               (CLKID_MISC_BASE + 9)
#define CLKID_12M_DIV           (CLKID_MISC_BASE + 10)
#define CLKID_12M_GATE          (CLKID_MISC_BASE + 11)
/* gen clock */
#define CLKID_GEN_CLK_SEL	(CLKID_MISC_BASE + 12)
#define	CLKID_GEN_CLK_DIV	(CLKID_MISC_BASE + 13)
#define CLKID_GEN_CLK		(CLKID_MISC_BASE + 14)

/*G12B clk*/
#define CLKID_G12B_ADD_BASE           (CLKID_MISC_BASE + 15)
#define CLKID_CPUB_FCLK_P             (CLKID_G12B_ADD_BASE + 0)
#define CLKID_CPUB_CLK                (CLKID_G12B_ADD_BASE + 1)
/*G12B gate*/
#define CLKID_CSI_DIG                 (CLKID_G12B_ADD_BASE + 2)
#define CLKID_VIPNANOQ                (CLKID_G12B_ADD_BASE + 3)
#define CLKID_GDC                     (CLKID_G12B_ADD_BASE + 4)
#define CLKID_MIPI_ISP                (CLKID_G12B_ADD_BASE + 5)
#define CLKID_CSI2_PHY1               (CLKID_G12B_ADD_BASE + 6)
#define CLKID_CSI2_PHY0               (CLKID_G12B_ADD_BASE + 7)

#define CLKID_GDC_CORE_CLK_COMP       (CLKID_G12B_ADD_BASE + 8)
#define CLKID_GDC_AXI_CLK_COMP        (CLKID_G12B_ADD_BASE + 9)
#define CLKID_VNANOQ_CORE_CLK_COMP    (CLKID_G12B_ADD_BASE + 10)
#define CLKID_VNANOQ_AXI_CLK_COMP     (CLKID_G12B_ADD_BASE + 11)
#define CLKID_VNANOQ_MUX              (CLKID_G12B_ADD_BASE + 12)
#define CLKID_MIPI_ISP_CLK_COMP       (CLKID_G12B_ADD_BASE + 13)
#define CLKID_MIPI_CSI_PHY_CLK0_COMP  (CLKID_G12B_ADD_BASE + 14)
#define CLKID_MIPI_CSI_PHY_CLK1_COMP  (CLKID_G12B_ADD_BASE + 15)
#define CLKID_MIPI_CSI_PHY_MUX        (CLKID_G12B_ADD_BASE + 16)
#define CLKID_SYS1_PLL                (CLKID_G12B_ADD_BASE + 17)

#define CLKID_SM1_ADD_BASE            (CLKID_G12B_ADD_BASE + 18)
#define CLKID_GP1_PLL                 (CLKID_SM1_ADD_BASE + 0)
#define CLKID_DSU_PRE_SRC0            (CLKID_SM1_ADD_BASE + 1)
#define CLKID_DSU_PRE_SRC1            (CLKID_SM1_ADD_BASE + 2)
#define CLKID_DSU_CLK_DIV0            (CLKID_SM1_ADD_BASE + 3)
#define CLKID_DSU_CLK_DIV1            (CLKID_SM1_ADD_BASE + 4)
#define CLKID_DSU_PRE_MUX0            (CLKID_SM1_ADD_BASE + 5)
#define CLKID_DSU_PRE_MUX1            (CLKID_SM1_ADD_BASE + 6)
#define CLKID_DSU_PRE_POST_MUX        (CLKID_SM1_ADD_BASE + 7)
#define CLKID_DSU_PRE_CLK             (CLKID_SM1_ADD_BASE + 8)
#define CLKID_DSU_CLK                 (CLKID_SM1_ADD_BASE + 9)
#define CLKID_CSI_DIG_CLK             (CLKID_SM1_ADD_BASE + 10)
#define CLKID_NNA_CLK                 (CLKID_SM1_ADD_BASE + 11)
#define CLKID_PARSER1_CLK             (CLKID_SM1_ADD_BASE + 12)
#define CLKID_CSI_HOST_CLK            (CLKID_SM1_ADD_BASE + 13)
#define CLKID_CSI_ADPAT_CLK           (CLKID_SM1_ADD_BASE + 14)
#define CLKID_TEMP_SENSOR_CLK         (CLKID_SM1_ADD_BASE + 15)
#define CLKID_CSI_PHY_CLK             (CLKID_SM1_ADD_BASE + 16)
#define CLKID_MIPI_CSI_PHY_CLK_COMP   (CLKID_SM1_ADD_BASE + 17)
#define CLKID_CSI_ADAPT_CLK_COMP      (CLKID_SM1_ADD_BASE + 18)

#define CLKID_AO_BASE           (CLKID_SM1_ADD_BASE + 19)
#define CLKID_AO_CLK81          (CLKID_AO_BASE + 0)
#define CLKID_SARADC_MUX        (CLKID_AO_BASE + 1)
#define CLKID_SARADC_DIV        (CLKID_AO_BASE + 2)
#define CLKID_SARADC_GATE       (CLKID_AO_BASE + 3)

#define NR_CLKS                 (CLKID_AO_BASE + 4)

#endif /* __G12A_CLKC_H */
