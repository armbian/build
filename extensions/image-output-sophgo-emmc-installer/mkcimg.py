#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/
#
# Wrap a raw image in the Sophgo/CVITEK "CIMG" container that the vendor U-Boot's
# cvi_update command flashes.
#
# The format is not documented anywhere; what follows was recovered from
# cmd/cvi_update.c in sophgo/u-boot-2021.10 and checked against the shipped
# milkv-duos-emmc-v1.1.4 package. Both halves matter, because the reader is
# stricter than the container looks.
#
# Global header, 64 bytes, read by _checkHeader():
#
#   off  size  field
#   0    4     magic, "CIMG"
#   4    4     version, 1
#   8    4     chunk header size, 64 (passed to _prgImage as chunk_header_size)
#   12   4     chunk count
#   16   4     payload size: every chunk header plus its data, i.e. filesize - 64
#   20   32    label, NUL-padded ("ROOTFS", "BOOT", ...); only the NAND path
#              reads it, as the partition name to erase
#   52   12    zero
#
# Chunk header, 64 bytes, read by _prgImage():
#
#   off  size  field
#   0    4     chunk type: 0 dont_care, 1 check_crc
#   4    4     data size in bytes
#   8    4     destination offset in bytes, absolute on the target device
#   12   4     min(partition size, bytes through the end of this chunk); only
#              the SPI-NOR path reads it, to size an "sf erase"
#   16   4     crc32 of the data (zlib crc32, i.e. the usual one)
#   20   44    zero
#
# That field 12 formula is not a guess: it reproduces all three vendor images
# exactly, boot.emmc and logo.jpg (one chunk each, where it equals the declared
# partition size rather than the much smaller data size) as well as the 48-chunk
# rootfs_ext4.emmc (where it climbs by 16MiB per chunk and then stops at the
# partition size). Verified with a repack that compares byte for byte.
#
# The awkward part is that _checkHeader does not walk the chunk headers. It
# computes each chunk's position in the file arithmetically:
#
#     load_size = file_sz > (MAX_LOADSIZE + chunk_sz) ? MAX_LOADSIZE + chunk_sz
#                                                     : file_sz;
#     fatload ... <load_size> <pos>;  pos += load_size;  file_sz -= load_size;
#
# so every chunk except the last must hold exactly MAX_LOADSIZE (16MiB) of data.
# A short chunk in the middle desynchronises every chunk after it. That also
# rules out the obvious size optimisation: skipping all-zero regions is
# impossible, because the stride is fixed rather than read from the file. Only
# the *offset* field is free, which is what lets Armbian write a whole MBR disk
# image starting at 0 instead of the vendor's four separate partition images.
#
# Two size ceilings, both from the u32 fields above and both well clear of the
# ~1.8GB Armbian produces: 4GiB for the payload, and FAT32's 4GiB per file.
#
# CONFIG_SUP_LARGE_PART_SIZE would move size/offset to u64 at different offsets.
# Armbian never sets it (it is gated on a make variable that
# sophgo_sg200x_cvitek_env_array() does not export), and the vendor's own images
# use this 32-bit layout, so only this layout is implemented.

import argparse
import binascii
import os
import struct
import sys

MAGIC = b"CIMG"
VERSION = 1
HEADER_SIZE = 64
# MAX_LOADSIZE in cmd/cvi_update.h. Not a tunable: _checkHeader assumes it.
CHUNK_DATA_SIZE = 16 * 1024 * 1024
CHUNK_TYPE_DONT_CARE = 0
CHUNK_TYPE_CHECK_CRC = 1
LABEL_SIZE = 32
U32_MAX = 0xFFFFFFFF


def build_global_header(chunk_count, payload_size, label):
    encoded = label.encode("ascii")
    if len(encoded) >= LABEL_SIZE:
        raise ValueError(
            "label %r is %d bytes, must be under %d including its NUL"
            % (label, len(encoded), LABEL_SIZE)
        )
    header = struct.pack(
        "<4sIIII",
        MAGIC,
        VERSION,
        HEADER_SIZE,
        chunk_count,
        payload_size,
    )
    header += encoded.ljust(LABEL_SIZE, b"\0")
    return header.ljust(HEADER_SIZE, b"\0")


def build_chunk_header(size, offset, part_size, crc, chunk_type):
    return struct.pack(
        "<IIIII", chunk_type, size, offset, part_size, crc
    ).ljust(HEADER_SIZE, b"\0")


def pack(src_path, dst_path, offset, label, chunk_type, part_size=None):
    src_size = os.path.getsize(src_path)
    if src_size == 0:
        raise ValueError("%s is empty" % src_path)

    # The region on the target this image is meant to fill. For Armbian that is
    # the whole disk and the image already spans it, so the image size is the
    # right default; the option exists so a vendor package can be reproduced,
    # where the declared partition is larger than the data written into it.
    if part_size is None:
        part_size = src_size
    if part_size < src_size:
        raise ValueError(
            "partition size %d is smaller than the %d byte image"
            % (part_size, src_size)
        )

    # Only reachable by hand - the extension always passes --offset 0.
    if offset < 0:
        raise ValueError("destination offset %d is negative" % offset)

    # _prgImage rounds each chunk up to a 512-byte sector before "mmc write",
    # so a ragged tail is written fine, but a ragged *destination* is not
    # expressible: offset is divided by SECTOR_SIZE with no remainder handling.
    if offset % 512:
        raise ValueError("destination offset %d is not a multiple of 512" % offset)

    chunk_count = (src_size + CHUNK_DATA_SIZE - 1) // CHUNK_DATA_SIZE
    payload_size = src_size + chunk_count * HEADER_SIZE
    total_size = payload_size + HEADER_SIZE

    if payload_size > U32_MAX:
        raise ValueError(
            "payload is %d bytes; the u32 size field in the CIMG header tops "
            "out at %d" % (payload_size, U32_MAX)
        )
    if offset + src_size > U32_MAX:
        raise ValueError(
            "image ends at byte %d on the target; the u32 offset field in the "
            "chunk header tops out at %d" % (offset + src_size, U32_MAX)
        )
    # Only bites a hand-passed --part-size: the field is written as
    # min(part_size, bytes through this chunk), and that second term only
    # reaches 4GiB once there are 256 chunks, i.e. an image over 255*16MiB.
    if part_size > U32_MAX:
        raise ValueError(
            "partition is %d bytes; the u32 partition size field in the chunk "
            "header tops out at %d" % (part_size, U32_MAX)
        )

    with open(src_path, "rb") as src, open(dst_path, "wb") as dst:
        dst.write(build_global_header(chunk_count, payload_size, label))

        written = 0
        for index in range(chunk_count):
            data = src.read(CHUNK_DATA_SIZE)
            if not data:
                raise ValueError(
                    "%s ended after %d of %d chunks; did it change while "
                    "being read?" % (src_path, index, chunk_count)
                )
            crc = binascii.crc32(data) & U32_MAX
            dst.write(
                build_chunk_header(
                    size=len(data),
                    offset=offset + index * CHUNK_DATA_SIZE,
                    part_size=min(part_size, (index + 1) * CHUNK_DATA_SIZE),
                    crc=crc,
                    chunk_type=chunk_type,
                )
            )
            dst.write(data)
            written += len(data)

        if written != src_size:
            raise ValueError(
                "read %d bytes from %s but it is %d bytes long"
                % (written, src_path, src_size)
            )

    return chunk_count, total_size


def main():
    parser = argparse.ArgumentParser(
        description="Wrap a raw image in a Sophgo CIMG container for cvi_update."
    )
    parser.add_argument("input", help="raw image to wrap")
    parser.add_argument("output", help="CIMG file to write")
    parser.add_argument(
        "--offset",
        type=lambda v: int(v, 0),
        default=0,
        help="destination byte offset on the target device (default: 0, the "
        "start of the eMMC user area, i.e. the MBR)",
    )
    parser.add_argument(
        "--label",
        default="ROOTFS",
        help="partition label recorded in the header; only the NAND flash path "
        "reads it (default: ROOTFS)",
    )
    parser.add_argument(
        "--part-size",
        type=lambda v: int(v, 0),
        default=None,
        help="size of the target region, for the partition-size field in each "
        "chunk header (default: the image size). Only needed to reproduce a "
        "vendor package, where the partition is larger than its contents.",
    )
    parser.add_argument(
        "--no-crc",
        action="store_true",
        help="record chunks as type dont_care instead of check_crc. The crc32 "
        "is written either way; the current vendor U-Boot has its verification "
        "commented out, so this only changes what a future one would do.",
    )
    args = parser.parse_args()

    try:
        chunks, total = pack(
            args.input,
            args.output,
            args.offset,
            args.label,
            CHUNK_TYPE_DONT_CARE if args.no_crc else CHUNK_TYPE_CHECK_CRC,
            args.part_size,
        )
    except (OSError, ValueError) as err:
        sys.stderr.write("mkcimg: %s\n" % err)
        return 1

    sys.stderr.write(
        "mkcimg: %s -> %s (%d chunks, %d bytes, target offset 0x%x)\n"
        % (args.input, args.output, chunks, total, args.offset)
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
