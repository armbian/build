#!/bin/sh

. /etc/armbian-release

echo "update-initramfs: Converting to u-boot FIT image" >&2
kernel_f=$(mktemp)
initrd_f="/boot/initrd.img-$1"

lzma -c -9e /boot/vmlinuz-$1 > $kernel_f

mkimage -f - /boot/espressobin.itb <<EOF
/dts-v1/;

/ {
    description = "EspressoBIN 3720 FIT Image";
    #address-cells = <1>;

    images {
        kernel {
            description = "Vanilla Linux kernel";
            data = /incbin/("$kernel_f");
            type = "kernel";
            arch = "arm64";
            os = "linux";
            compression = "lzma";
            load = <0x07000000>;
            entry = <0x07000000>;
            hash {
                algo = "sha1";
            };
        };
        ramdisk {
            description = "Boot ramdisk";
            data = /incbin/("$initrd_f");
            type = "ramdisk";
            arch = "arm64";
            os = "linux";
            hash {
                algo = "sha1";
            };
        };
        fdtv5 {
            description = "Flattened Device Tree ebinv5";
            data = /incbin/("/boot/dtb/marvell/armada-3720-espressobin.dtb");
            type = "flat_dt";
            arch = "arm64";
            compression = "none";
            load = <0x06f00000>;
            entry = <0x06f00000>;
            hash {
                algo = "sha1";
            };
        };
        fdtv7 {
            description = "Flattened Device Tree ebinv7";
            data = /incbin/("/boot/dtb/marvell/armada-3720-espressobin-v7.dtb");
            type = "flat_dt";
            arch = "arm64";
            compression = "none";
            load = <0x06f00000>;
            entry = <0x06f00000>;
            hash {
                algo = "sha1";
            };
        };
    };

    configurations {
        default = "v5";
        v5 {
            description = "Standard Boot ebinv5";
            kernel = "kernel";
            ramdisk = "ramdisk";
            fdt = "fdtv5";
            hash {
                algo = "sha1";
            };
        };
        v7 {
            description = "Standard Boot ebinv7";
            kernel = "kernel";
            ramdisk = "ramdisk";
            fdt = "fdtv7";
            hash {
                algo = "sha1";
            };
        };
    };
};
EOF
