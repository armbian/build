# S922X hexa core 2GB/4GB RAM SoC eMMC GBE USB3 SPI
BOARD_NAME="Odroid N2"
BOARDFAMILY="odroidn2"
BOOTCONFIG="odroidn2_config"
#
MODULES="media_clock firmware"
if [[ $BUILD_DESKTOP == 'yes' ]]; then
  MODULES+=" decoder_common stream_input amvdec_avs amvdec_h264 amvdec_h264_4k2k amvdec_mh264 amvdec_h264mvc amvdec_h265 amvdec_mjpeg amvdec_mmjpeg amvdec_mpeg12 amvdec_mpeg4 amvdec_mmpeg4 amvdec_real amvdec_vc1 amvdec_vp9"
fi

MODULES_NEXT=""
#
KERNEL_TARGET="default,dev"
CLI_TARGET="buster,bionic:default"
DESKTOP_TARGET="buster,bionic:default"
#
CLI_BETA_TARGET=""
DESKTOP_BETA_TARGET=""
