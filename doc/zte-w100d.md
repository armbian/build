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

产物在 `output/images/`，文件名为
`Armbian-unofficial_*_Zte-w100d_trixie_current_*_*.img`。

## 4. 镜像内容

构建后 boot 分区（FAT）包含：

- `aml_autoscript`：vendor bootloader 首先执行的脚本，负责扫描 SD/USB。
- `s905_autoscript`、`emmc_autoscript`：`booti` 启动脚本。设备树默认为
  `dtb/amlogic/meson-g12a-x96-max.dtb`。
- `Image`、`uInitrd`、`dtb/amlogic/`：内核、initrd、设备树。
- `extlinux/extlinux.conf`：构建系统生成，vendor u-boot 不使用。

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

## 8. 调整设备树

默认使用通用 G12A 设备树 `amlogic/meson-g12a-x96-max.dtb`。
WiFi、蓝牙、声卡可能不工作。

修改 `config/boards/zte-w100d.tvb` 中的 `BOOT_FDT_FILE`：

```
BOOT_FDT_FILE="amlogic/meson-g12a-x96-max.dtb"
```

可选设备树在 `/boot/dtb/amlogic/`：

- `meson-g12a-x96-max.dtb`
- `meson-g12a-sei510.dtb`
- `meson-g12a-u200.dtb`

修改后重新构建。也可在已安装系统上改 `/boot/s905_autoscript` 里的 `setenv fdtfile`
（脚本为 uImage，需用 `mkimage` 重新编译）。

## 9. 常见问题

- 不启动：确认已顶 Reset 进入 SD 启动；确认 boot 分区类型为 `0x0c` 且有 `aml_autoscript`。
- 反复重启：多为 boot 分区类型为 `0xea`，vendor u-boot 读不到脚本。
- 无显示：尝试另一个 G12A 设备树。
- 无 WiFi：通用设备树不含 W100D 的 WiFi 节点，需要专用设备树。
- 构建报 binfmt 错误：WSL2 环境需先注册 qemu binfmt。
- USB Burning Tool 提示“解析烧录固件失败”：工具不支持 Armbian 镜像，
  请改用 SD 卡或 U 盘刷写（见第 5 节）。
