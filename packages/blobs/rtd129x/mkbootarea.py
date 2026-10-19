#!/usr/bin/env python3
# Assemble the Realtek RTD129x eMMC boot area: a size table and its SHA-256,
# then hwsetting,
# U-Boot, FSBL, TEE and BL31. Each part is followed by SHA-256 padding and
# the SHA-256 of its data; parts after U-Boot start on 512-byte boundaries.
# The result goes to the eMMC user area at byte 0x20000.
# Usage: mkbootarea.py <blob dir> <u-boot.bin> <output>
import hashlib
import struct
import sys

UBOOT_DATA = 0x93780    # the U-Boot part size the factory layout uses


def part(data):
    pad = b"\x80" + b"\0" * ((55 - len(data)) % 64) + struct.pack(">Q", len(data) * 8)
    return data + pad, hashlib.sha256(data).digest()


blobs, uboot_bin, out = sys.argv[1:4]
uboot = open(uboot_bin, "rb").read()
if len(uboot) > UBOOT_DATA:
    sys.exit("u-boot.bin is larger than 0x%x bytes" % UBOOT_DATA)
parts = [open(blobs + "/hwsetting.bin", "rb").read(), uboot.ljust(UBOOT_DATA, b"\0")]
parts += [open(blobs + "/%s.bin" % n, "rb").read() for n in ("fsbl", "tee", "bl31")]
padded = [part(p) for p in parts]

hdr = struct.pack("<8I", *([len(p) for p, _ in padded] + [0, 0, 0])).ljust(0x40, b"\0")
img = bytearray(hdr + hashlib.sha256(hdr).digest())
for i, (p, sha) in enumerate(padded):
    if i >= 2:
        img += b"\0" * (-len(img) % 512)
    img += p + sha
img += b"\0" * (-len(img) % 512)
open(out, "wb").write(img)
