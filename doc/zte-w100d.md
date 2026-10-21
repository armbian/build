# ZTE W100D (Amlogic S905X2) 构建与刷写

本教程说明如何为 ZTE W100D 盒子构建 Armbian、写入 SD 卡并从 SD 卡启动。
内容也适用于同系列 W102D / W103D / W105D。

## 1. 硬件

| 项目 | 参数 |
| --- | --- |
| SoC | Amlogic S905X2（meson-g12a，4x Cortex-A53） |
| 内存 | 2 GB DDR4 |
| 存储 | 8 GB eMMC |
| 网络 | WiFi5 + 蓝牙 5.0（无有线网口） |
| 接口 | HDMI、3x USB2.0、Type-C 供电 |
| 外设 | Panfrost（Mali-G31）GPU |

## 2. 支持的形态

该板卡为电视盒子支持级别（`tvb`），依赖盒子自带的 vendor bootloader。
构建系统不编译也不烧写 u-boot。

- vendor u-boot 直接加载 `Image`、`uInitrd`、`dtb`，再用 `booti` 启动。
- 不使用 `u-boot.ext` 链式加载，不依赖 `extlinux.conf`。
- boot 分区类型设为 `0x0c`（FAT32 LBA）并置活动标志。vendor u-boot
  不识别 Armbian 默认的 `0xea`（Linux extended boot）类型。

## 3. 构建

```bash
PESTER_TERMINAL=no ./compile.sh \
  BOARD=zte-w100d \
  RELEASE=trixie \
  BUILD_DESKTOP=no BUILD_MINIMAL=no \
  KERNEL_CONFIGURE=no
```

镜像类型三选一：

```bash
BUILD_DESKTOP=no  BUILD_MINIMAL=no   # 标准命令行（推荐先用）
BUILD_DESKTOP=no  BUILD_MINIMAL=yes  # 最小化
BUILD_DESKTOP=yes BUILD_MINIMAL=no   # 桌面
```

不要同时给 `BUILD_DESKTOP=yes` 和 `BUILD_MINIMAL=yes`。

`BUILD_MINIMAL=yes` 使用 systemd-networkd，没有 NetworkManager/`nmcli`。
需要 WiFi 联网测试时用 `BUILD_MINIMAL=no`（NetworkManager）。

产物在 `output/images/`，文件名为
`Armbian-unofficial_*_Zte-w100d_trixie_current_*_*.img`。

## 4. 镜像内容

构建后 boot 分区（FAT）包含：

- `aml_autoscript`：vendor bootloader 首先执行的脚本，负责扫描 SD/USB。
- `s905_autoscript`、`emmc_autoscript`：`booti` 启动脚本。设备树默认为
  `dtb/amlogic/meson-g12a-w100d.dtb`。
- `Image`、`uInitrd`、`dtb/amlogic/`：内核、initrd、设备树。
- `extlinux/extlinux.conf`：构建系统生成，vendor u-boot 不使用。

rootfs 中 WiFi/蓝牙相关文件：

- `/usr/lib/firmware/mediatek/mt7663_n9_v3.bin`、`mt7663pr2h.bin`：固件。
- `mt7663s.ko`、`btmtksdio.ko`：内核模块（`/lib/modules/<版本>/`）。

## 5. 写入 SD 卡

Windows 用 balenaEtcher 或 Rufus（DD 模式）。出现“需要格式化”对话框时选取消。

Linux 用 `dd`：

```bash
lsblk                                              # 确认 SD 卡节点，勿写错盘
sudo umount /dev/sdX* 2>/dev/null
sudo dd if=output/images/Armbian-*_Zte-w100d_*.img of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

> **不要用 Amlogic_USB_Burning_Tool。** 它只认 Amlogic 专有烧录包（AML 头部、
> 加密 bootloader、安卓分区表）。Armbian 是标准磁盘镜像，导入时会提示
> “解析烧录固件失败”。Burning Tool 仅用于刷官方安卓线刷包或救砖。

## 6. 从 SD 卡启动

1. 断电，插入 SD 卡。
2. 顶住机身的 Reset 孔，再上电。
3. 松开 Reset，等待启动（首次启动约 1-2 分钟）。

启动失败时，盒子仍可使用原 Android 系统。SD 启动不修改 eMMC。

## 7. 安装到 eMMC

进入 SD 卡上的系统后：

```bash
sudo /root/install-aml.sh
```

脚本备份原 u-boot、重建分区、复制系统到 eMMC。完成后关机、拔出 SD 卡、上电，
系统从 eMMC 启动。

原 u-boot 备份在 `/root/u-boot-default-aml.img`。

## 8. 设备树

默认使用专用设备树 `amlogic/meson-g12a-w100d.dtb`。它由
`patch/kernel/archive/meson64-6.18/dt/meson-g12a-w100d.dts` 提供，
与 W103D 移植共用板级定义：

- 2 GB 内存，SD_EMMC_B 作为 SDIO（WiFi/蓝牙），SD_EMMC_C 为 eMMC。
- `compatible = "zte,w100d", "zte,w103d", "amlogic,g12a"`。
  `zte,w103d` 必须保留：MT7663 combo 驱动按它判断板型。
- 蓝牙走 SDIO（`btmtksdio`），不走 UART。

其他 G12A 设备树仍保留在 `/boot/dtb/amlogic/`，可作对照：

- `meson-g12a-x96-max.dtb`
- `meson-g12a-sei510.dtb`
- `meson-g12a-u200.dtb`

需要改 `fdtfile` 时，按 8.1 节创建 `/boot/armbianEnv.txt`；也可改
`/boot/s905_autoscript` 里的 `setenv fdtfile`（脚本为 uImage，需用 `mkimage`
重新编译）。

### 8.1 启动参数与 armbianEnv.txt

镜像默认没有 `/boot/armbianEnv.txt`。板级配置为 `SRC_EXTLINUX=yes`，
构建时会删除该文件；`s905_autoscript` / `emmc_autoscript` 使用内置默认值。

需要追加内核参数时，可手动创建该文件。它会整体替换启动脚本的默认
`extraargs`，因此必须写全：

```bash
sudo tee /boot/armbianEnv.txt >/dev/null <<'EOF'
verbosity=1
bootlogo=false
console=both
fdtfile=amlogic/meson-g12a-w100d.dtb
rootdev=LABEL=armbi_root
extraargs=rootflags=data=writeback rw no_console_suspend consoleblank=0 fsck.fix=yes fsck.repair=yes net.ifnames=0
EOF
```

`rootdev` 必须与 `blkid` 显示的根分区标签或 UUID 一致。标签不是
`armbi_root` 时，写成 `rootdev=UUID=<uuid>`。

不要用 Windows 编辑器保存该文件，避免 CRLF。检查：

```bash
cat -A /boot/armbianEnv.txt
```

`rootdev` 值后出现 `^M` 时，删除文件或改成 Unix 换行。

EDID 读取失败时可固定 HDMI 模式，在 `extraargs` 末尾追加：

```text
video=HDMI-A-1:2560x1440@60e
```

该参数固定输出分辨率，换其他显示器时可能黑屏。只在对应显示器上使用。

### 8.2 开机 logo 与花屏

启动初期的 logo 来自 vendor u-boot，通常是安卓系统遗留的 logo，不是
`/boot/boot.bmp`。内核 `meson-drm` 接管显示时会有约 2 秒花屏，然后显示
启动 log。这是 u-boot framebuffer 到 DRM 的交接，不是故障。

## 9. WiFi 与蓝牙

W100D 使用 MediaTek MT7661LSN（MT7663 SDIO combo）。内核补丁
`zz-board-zte-w100d-mt7663.patch` 增加 `mt7663s` 驱动和
`btmtksdio` combo 协调。BSP 包安装两个固件：

| 文件 | sha256 |
| --- | --- |
| `mt7663_n9_v3.bin` | `223f73f17f0f986dc4e7167daa6eef14ffb41c713f22d70f9645eb049bdec80a` |
| `mt7663pr2h.bin` | `534f2152f9b0f48dfcec9c1727b0bab9a3727a655d76d5ec818cc39a55602336` |

启动后检查：

```bash
dmesg | grep -iE "mt7663|btmtk|sdio"
ip link
nmcli device wifi list
rfkill list
bluetoothctl show
```

连 WiFi（NetworkManager）：

```bash
sudo rfkill unblock wifi
nmcli radio wifi on
nmcli device wifi list
sudo nmcli device wifi connect "SSID" password "PASSWORD"
nmcli connection show
ip addr show wlan0
```

隐藏网络加 `hidden yes`。也可用 `sudo armbian-config` → Network → WiFi。

连蓝牙：

```bash
bluetoothctl
power on
scan on
pair XX:XX:XX:XX:XX:XX
connect XX:XX:XX:XX:XX:XX
trust XX:XX:XX:XX:XX:XX
```

`mt7663s` 未加载时：

```bash
sudo modprobe mt7663s
dmesg | tail -50
```

`modprobe mt7663s` 会先加载 `btmtksdio`，两者共用同一张 SDIO 卡。
若只有蓝牙或只有 WiFi，检查 DTB 中 `sd_emmc_b` 是否为 `okay`，
以及 `zte,w103d` 是否仍在 compatible 列表中。

`ip link` 没有 `wlan0` 时：

```bash
lsmod | grep -E "mt7663|btmtk|mt76"
sudo modprobe mt7663s
dmesg | grep -iE "mt7663|mt76|sdio|firmware"
cat /proc/device-tree/model          # 应为 ZTE W100D
ls -l /lib/firmware/mediatek/mt7663*
```

旧 eMMC 系统没有驱动和固件，必须启动新镜像或重新执行
`/root/install-aml.sh`。`dmesg` 无 SDIO 枚举时，确认启动的是
`meson-g12a-w100d.dtb`，不是 `x96-max`。

## 10. 常见问题

- 不启动：确认已顶 Reset 进入 SD 启动；确认 boot 分区类型为 `0x0c` 且有 `aml_autoscript`。
- 反复重启：多为 boot 分区类型为 `0xea`，vendor u-boot 读不到脚本。
- 无显示：尝试另一个 G12A 设备树。
- 反复出现 `Begin: Running /scripts/local-block ...` 后停在 `(initramfs)`：
  initramfs 找不到根分区。多为手动创建的 `/boot/armbianEnv.txt` 中
  `rootdev` 错误，或文件带 CRLF。从 U 盘启动，挂载 boot 分区并删除该文件，
  或按 8.1 节修正。应急时在 initramfs 中执行 `blkid`，找到根分区后执行
  `mount -o rw /dev/mmcblk2p2 /root` 和 `exit`（设备名以实际为准）。
- 无 WiFi/蓝牙：确认使用 `meson-g12a-w100d.dtb`；`dmesg | grep -i sdio` 查看
  SDIO 枚举；确认 `mt7663_n9_v3.bin` 与 `mt7663pr2h.bin` 位于
  `/usr/lib/firmware/mediatek/`。
- 没有 `nmcli`：镜像是 `BUILD_MINIMAL=yes`（systemd-networkd）。改用
  `BUILD_MINIMAL=no` 重新构建，或用 `wpa_supplicant` 手动联网。
- `wlan0` 不存在且 `modprobe mt7663s` 报 “module not found”：当前运行的是旧
  eMMC 系统。启动新镜像，或在新系统中执行 `/root/install-aml.sh`。
- 构建报 binfmt 错误：WSL2 环境需先注册 qemu binfmt。
- USB Burning Tool 提示“解析烧录固件失败”：工具不支持 Armbian 镜像，
  请改用 SD 卡或 U 盘刷写（见第 5 节）。
