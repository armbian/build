# NXP ASK modules — parent Kbuild for Armbian's IN-TREE build (descends into the module dirs).
# Armbian-specific glue; OpenWrt/Yocto build the modules out-of-tree and never needed it.
# Board-specific module lines (sfp_led, leds_lp5812) are appended by the extension.
obj-$(CONFIG_ASK_CDX)		+= cdx/
obj-$(CONFIG_ASK_FCI)		+= fci/
obj-$(CONFIG_ASK_AUTO_BRIDGE)	+= auto_bridge/
