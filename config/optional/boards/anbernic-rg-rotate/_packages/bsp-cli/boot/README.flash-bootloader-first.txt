Anbernic RG Rotate - the bootloader has to be flashed once before this card boots
=================================================================================

This card will not start the board yet. The RG Rotate's first-stage loader lives
in the eMMC, and the one it ships with refuses to start anything Anbernic did not
sign - including the U-Boot on this card. Replacing it is a one-time step.

Afterwards, the stock Android on eMMC still boots normally with this card
removed, and every later Armbian image is just written to a card as usual.

You can read this file from the card on a PC, which is the point: do the reading
before you write anything.

WARNING
  The loader lives in the eMMC's hardware boot area, which is what the BootROM
  reads to start the machine. A bad image there means the board will not boot
  until it is recovered over USB. Recovery always works - the BootROM is mask ROM
  and cannot be overwritten - but it is a lot more work than getting it right the
  first time. Back up the stock loader before you begin.


What you need
-------------

  * <image>.spl.img, from the same Armbian download as this card's image. It sits
    next to the .img file and is 4 MiB.
  * Either a shell on the board (Armbian running from another card, or Android
    with "adb root"), or a USB cable and spd_dump if it will not boot at all.

The same file goes to BOTH boot areas. The two slots hold identical loaders.


Step 1: check the image
-----------------------

The BootROM reads mImgSize bytes from offset 0x200 and compares their SHA256
against the hash in the 512-byte DHTB header. If that does not match, the board
will not start. Check it on your PC first:

    python3 - <image>.spl.img <<'EOF'
    import hashlib, struct, sys
    d = open(sys.argv[1], "rb").read()
    assert d[0:4] == b"DHTB", f"not a DHTB image: {d[0:4]!r}"
    assert len(d) == 4 * 1024 * 1024, f"expected 4 MiB, got {len(d)}"
    size = struct.unpack("<I", d[0x30:0x34])[0]
    calc = hashlib.sha256(d[0x200:0x200 + size]).digest()
    print(f"payload {size} bytes, sha256 {calc.hex()}")
    print("DHTB hash:", "MATCH" if calc == d[8:0x28] else "MISMATCH - DO NOT FLASH")
    EOF

MATCH is the only acceptable answer.

The bytes after the payload are all zero in the image Armbian builds, because it
is unsigned. A stock or vendor-signed loader has a ~692 byte SIMGHDR block there
instead. Both are normal; do not take the zeros for a truncated file.


Step 2 (preferred): write it from a running system
--------------------------------------------------

Use this whenever the board still boots. It needs no extra tools.

First, find the eMMC. The boot areas are the bootN partitions of the eMMC, which
is normally mmcblk3 - but the index depends on probe order, and writing to the
wrong device destroys whatever is on it. Confirm before you touch anything:

    for d in /sys/block/mmcblk*; do
        [ -e "$d/device/type" ] || continue
        echo "$(basename "$d")  $(cat "$d/device/type")  $(cat "$d/size") sectors"
    done

The eMMC reports type MMC; the microSD reports SD. Only the eMMC has bootN
partitions - "ls /dev/mmcblk*boot*" should show exactly two, both on that
device. Everywhere below, replace mmcblk3 with whatever you found.

On Android the nodes live under /dev/block/ instead, the index is usually
different again, and there is no sudo - run the commands as root from "adb
shell" with /dev/block/mmcblkNboot0 in place of the paths below.

Back up the stock loader. Do not skip this - it is the only copy of a known good
image for your unit. Copy both files somewhere that is not the device.

    sudo dd if=/dev/mmcblk3boot0 of=stock_boot0.bak bs=1M
    sudo dd if=/dev/mmcblk3boot1 of=stock_boot1.bak bs=1M

Write boot0 only. The BootROM reads boot0; leaving boot1 alone for now means a
known good loader is still on the machine if something is wrong.

    echo 0 | sudo tee /sys/block/mmcblk3boot0/force_ro
    sudo dd if=<image>.spl.img of=/dev/mmcblk3boot0 bs=1M conv=fsync
    sudo dd if=/dev/mmcblk3boot0 of=/tmp/readback.img bs=1M count=4
    cmp <image>.spl.img /tmp/readback.img && echo "write verified"

Now power the board fully off and back on. A warm reboot is not a test: the
previous loader is still resident in IRAM and the board can come up on it,
telling you nothing. Hold the power button until it is off, then start it.

If it boots - with this card in, or into Android with the card out - write the
second slot:

    echo 0 | sudo tee /sys/block/mmcblk3boot1/force_ro
    sudo dd if=<image>.spl.img of=/dev/mmcblk3boot1 bs=1M conv=fsync


Step 2 (alternative): write it over USB, from the BootROM
---------------------------------------------------------

Use this if the board no longer boots. It talks to the mask-ROM download mode
with spd_dump (https://github.com/TomKing062/spd_dump), which supports this SoC.

You also need fdl1-dl.bin and fdl2-dl.bin for this platform. They are not part of
Armbian; they come from a vendor PAC for the device.

Entering download mode: hold the small tact switch on the mainboard - NOT the
Home button - while connecting USB. The host should show:

    $ lsusb
    Bus 001 Device 00x: ID 1782:4d00 Spreadtrum Communications Inc.

1782:4d00 is the one you want. 514c:8850 is a different mode and will not work.

splloader is boot0 and splloader_bak is boot1. Write boot0 only, for the same
reason as above:

    ./spd_dump --wait 300 keep_charge 1 \
      fdl fdl1-dl.bin 0x5500 \
      fdl fdl2-dl.bin 0x9efffe00 \
      exec \
      w splloader <image>.spl.img \
      poweroff

Cold boot, confirm, then the second slot:

    ./spd_dump --wait 300 keep_charge 1 \
      fdl fdl1-dl.bin 0x5500 \
      fdl fdl2-dl.bin 0x9efffe00 \
      exec \
      w splloader_bak <image>.spl.img \
      poweroff

To back the stock loader up this way first, read the same two names instead of
writing them:

    r splloader stock_boot0.bak 0x400000


If it does not boot
-------------------

Get into download mode as above and write stock_boot0.bak back to splloader. The
BootROM is mask ROM: whatever is in the eMMC, this path is available, so the board
cannot be bricked by a bad loader.

Do not rely on the BootROM's boot0 -> boot1 fallback. It covers boot0 being
unreadable, not a loader that reads fine and then hangs - and a hang is the more
likely failure. Recovery is over USB.


Afterwards
----------

  * Armbian images for this board are written to a microSD card in the normal way.
    The loader is not touched again.
  * Android on eMMC still boots with the card removed. The replacement loader does
    the same secure-world bring-up as stock; it only skips the signature checks on
    the images it loads.
  * If a later Armbian build ships a new .spl.img, the release notes will say so.
    Otherwise there is no need to repeat any of this.


About the loader that is being installed
----------------------------------------

It is built from source by the Armbian build, from the Unisoc "chipram" loader -
U-Boot nand_spl derived, GPL-2.0-or-later - with SD-card boot added. No vendor
binary and no signing key is involved: the image is unsigned and its DHTB
container is produced by a Python packer in the same tree. Source:
https://github.com/crackerjacques/ums512_spl (branch armbian)
