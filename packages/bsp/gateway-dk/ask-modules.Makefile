# NXP ASK modules — parent Kbuild for Armbian's IN-TREE build (descends into
# the module dirs). Armbian-specific glue; ASK's other integrations build out-of-tree.
#
# As of ASK 1.1.0 the data plane is one consolidated cdx/ dir whose own Kbuild
# emits both cdx.ko and ask_flowtable.ko under CONFIG_ASK_CDX. Board-specific
# module lines (sfp_led, leds_lp5812) are appended by the extension.
obj-$(CONFIG_ASK_CDX)		+= cdx/
