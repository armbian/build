# Armbian Community Build Guide

This guide provides comprehensive instructions for creating community builds for Armbian, specifically focused on adding new board support like the RG34XXSP.

## Overview

Armbian is a Debian/Ubuntu-based Linux distribution optimized for ARM-based single-board computers. Community builds allow developers to add support for new hardware platforms and contribute to the Armbian ecosystem.

## Requirements

### System Requirements
- **Architecture**: x86_64, aarch64, or riscv64 machine
- **Memory**: Minimum 8GB RAM (for non-BTF builds)
- **Storage**: ~50GB disk space for VM, container, or bare-metal
- **OS**: Armbian/Ubuntu Noble 24.04.x for native building, or Docker-capable Linux for containerized builds
- **Privileges**: Superuser rights (sudo or root access)
- **System State**: Up-to-date system (outdated Docker binaries can cause issues)

### For Windows Users
- **OS**: Windows 10/11 with WSL2 subsystem
- **WSL Distribution**: Armbian/Ubuntu Noble 24.04.x

## Getting Started

### 1. Clone the Repository
```bash
apt-get -y install git
git clone --depth=1 --branch=main https://github.com/armbian/build
cd build
```

### 2. Initial Build (Interactive Mode)
```bash
./compile.sh
```

This launches an interactive graphical interface that:
- Prepares the workspace by installing dependencies
- Downloads necessary sources
- Guides through the build process
- Creates kernel packages or SD card images

### 3. Expert Mode
```bash
./compile.sh EXPERT="yes"
```

Shows work-in-progress areas and advanced options.

## Build Commands

### Basic Build Commands

#### 1. Build Full Image
```bash
./compile.sh build BOARD=<board> BRANCH=<branch> RELEASE=<release>
```

#### 2. Build Kernel Only
```bash
./compile.sh kernel BOARD=<board> BRANCH=<branch>
```

#### 3. Interactive Kernel Configuration
```bash
./compile.sh kernel-config BOARD=<board> BRANCH=<branch>
```

#### 4. Device Tree Validation
```bash
./compile.sh dts-check BOARD=<board> BRANCH=<branch>
```

#### 5. Board Inventory
```bash
./compile.sh inventory-boards
```

### Build Parameters

#### Core Parameters
- **BOARD**: Target board name (e.g., `rg34xxsp`)
- **BRANCH**: Kernel branch (`legacy`, `current`, `edge`)
- **RELEASE**: OS release (`noble`, `jammy`, `bookworm`, `trixie`)
- **BUILD_DESKTOP**: Build desktop variant (`yes`/`no`)
- **BUILD_MINIMAL**: Build minimal system (`yes`/`no`)
- **KERNEL_CONFIGURE**: Interactive kernel config (`yes`/`no`)
- **DESKTOP_ENVIRONMENT**: Desktop environment (`xfce`, `gnome`, `kde`, `minimal`)
- **DESKTOP_ENVIRONMENT_CONFIG_NAME**: Desktop config variant (`config_base`, `config_full`, `config_minimal`)

#### Advanced Parameters
- **EXPERT**: Show advanced/experimental options (`yes`/`no`)
- **CLEAN_LEVEL**: Clean build artifacts (`make`, `images`, `cache`, `sources`, `oldcache`)
- **REPOSITORY_INSTALL**: Repository packages to install (space-separated list)
- **DESKTOP_APPGROUPS_SELECTED**: Desktop application groups (space-separated list)
- **COMPRESS_OUTPUTIMAGE**: Compress final image (`yes`/`no`)
- **BUILD_ONLY**: Build component only (`u-boot`, `kernel`, `bootloader`)
- **KERNEL_GIT**: Override kernel source URL
- **KERNELBRANCH**: Override kernel branch
- **BOOTLOADER_GIT**: Override bootloader source URL
- **BOOTBRANCH**: Override bootloader branch

#### Example Build Commands
```bash
# Minimal CLI build
./compile.sh build \
BOARD=rg34xxsp \
BRANCH=current \
RELEASE=noble \
BUILD_MINIMAL=yes \
BUILD_DESKTOP=no \
KERNEL_CONFIGURE=no

# Desktop build with specific environment
./compile.sh build \
BOARD=rg34xxsp \
BRANCH=current \
RELEASE=noble \
BUILD_DESKTOP=yes \
BUILD_MINIMAL=no \
DESKTOP_ENVIRONMENT="xfce" \
DESKTOP_ENVIRONMENT_CONFIG_NAME="config_base"

# Multiple build variants
# Bookworm minimal
./compile.sh build BOARD=rg34xxsp BRANCH=current RELEASE=bookworm BUILD_MINIMAL=yes BUILD_DESKTOP=no

# Bookworm desktop  
./compile.sh build BOARD=rg34xxsp BRANCH=current RELEASE=bookworm BUILD_MINIMAL=no BUILD_DESKTOP=yes

# Noble minimal
./compile.sh build BOARD=rg34xxsp BRANCH=current RELEASE=noble BUILD_MINIMAL=yes BUILD_DESKTOP=no

# Noble desktop
./compile.sh build BOARD=rg34xxsp BRANCH=current RELEASE=noble BUILD_MINIMAL=no BUILD_DESKTOP=yes

# Token-optimized build (saves build logs locally, shows only essential output)
./compile.sh build BOARD=rg34xxsp BRANCH=current RELEASE=bookworm \
BUILD_MINIMAL=yes BUILD_DESKTOP=no KERNEL_CONFIGURE=no \
2>&1 | tee build_log.txt | tail -20
```

## Creating New Board Support

### 1. Board Configuration Structure

Board configurations are stored in `config/boards/` with the following structure:

```
config/boards/
├── <board-name>.conf     # Main board configuration
├── <board-name>.csc      # Community supported configuration
├── <board-name>.wip      # Work in progress
├── <board-name>.tvb      # TV box configuration
└── <board-name>.eos      # End of support
```

### 2. Board Configuration File Format

Create `config/boards/rg34xxsp.csc` (using modern syntax):

```bash
# Anbernic RG34XXSP Gaming Handheld
# Allwinner H700 quad core 2GB RAM SoC WiFi Bluetooth clamshell handheld

# Board identification (modern syntax with declare -g)
declare -g BOARD_NAME="Anbernic RG34XXSP"
declare -g BOARDFAMILY="sun50iw9"
declare -g BOARD_MAINTAINER="mitswan"

# Kernel and bootloader configuration  
declare -g KERNEL_TARGET="current"
declare -g KERNEL_TEST_TARGET="current"
declare -g BOOTCONFIG="anbernic_rg34xx_sp_h700_defconfig"
declare -g BOOTBRANCH="tag:v2025.04"
declare -g BOOTPATCHDIR="v2025-sunxi"

# Device tree and hardware
declare -g BOOT_FDT_FILE="sun50i-h700-anbernic-rg34xx-sp.dtb"
declare -g SERIALCON="ttyS0"
declare -g HAS_VIDEO_OUTPUT="yes"

# Package configuration
declare -g PACKAGE_LIST_BOARD="rfkill bluetooth bluez bluez-tools"
declare -g FORCE_BOOTSCRIPT_UPDATE="yes"

# Board-specific extensions
enable_extension "uwe5622-allwinner"

# BSP package functions
function post_family_tweaks_bsp__rg34xxsp_firmware() {
    display_alert "$BOARD" "Installing panel firmware and display services" "info"
    
    # Install panel firmware files
    mkdir -p "${destination}"/lib/firmware/panels/
    cp -fr $SRC/packages/bsp/anbernic/panel_firmware/* "${destination}"/lib/firmware/panels/
    
    # Install lid screen control script
    mkdir -p "${destination}"/usr/local/bin/
    cp -fv $SRC/packages/bsp/anbernic/systemd_services/basic-lid-screen-off-monitor "${destination}"/usr/local/bin/
    chmod +x "${destination}"/usr/local/bin/basic-lid-screen-off-monitor
    
    # Copy systemd services
    mkdir -p "${destination}"/etc/systemd/system/
    cp -fv $SRC/packages/bsp/anbernic/systemd_services/anbernic-display-fix.service "${destination}"/etc/systemd/system/
    cp -fv $SRC/packages/bsp/anbernic/systemd_services/basic-lid-screen-off.service "${destination}"/etc/systemd/system/
}

function post_family_tweaks__rg34xxsp_enable_services() {
    display_alert "$BOARD" "Enabling display services" "info"
    # Enable the display fix service (required for display to work)
    chroot_sdcard systemctl enable anbernic-display-fix.service
    
    # Note: basic-lid-screen-off.service is installed but not enabled
    # Users can enable it manually with: systemctl enable basic-lid-screen-off.service
}
```

### 3. Complete Board Configuration Parameters

Based on comprehensive analysis of the Armbian build system, here are all available parameters:

#### **Core Board Identity**
| Parameter | Type | Purpose | Example |
|-----------|------|---------|---------|
| `BOARD_NAME` | string | Display name for board | `"Anbernic RG34XXSP"` |
| `BOARDFAMILY` | string | SoC/hardware family | `"sun50iw9"` |
| `BOARD_MAINTAINER` | string | GitHub username(s) | `"mitswan"` |

#### **Kernel Configuration**
| Parameter | Type | Purpose | Example |
|-----------|------|---------|---------|
| `KERNEL_TARGET` | list | Supported kernel branches | `"current,edge"` |
| `KERNEL_TEST_TARGET` | list | Testing kernel branches | `"current"` |
| `KERNEL_UPGRADE_FREEZE` | list | Freeze kernel updates | `"current@24.8.1"` |

#### **Bootloader Configuration**
| Parameter | Type | Purpose | Example |
|-----------|------|---------|---------|
| `BOOTCONFIG` | string | U-Boot defconfig name | `"anbernic_rg34xx_sp_h700_defconfig"` |
| `BOOTBRANCH` | string | U-Boot version/branch | `"tag:v2025.04"` |
| `BOOTPATCHDIR` | string | U-Boot patch directory | `"v2025-sunxi"` |
| `BOOT_SCENARIO` | string | Bootloader build strategy | `"spl-blobs"` |
| `BOOT_SOC` | string | SoC identifier | `"h700"` |

#### **Device Tree & Hardware**
| Parameter | Type | Purpose | Example |
|-----------|------|---------|---------|
| `BOOT_FDT_FILE` | string | Force specific DTB file | `"sun50i-h700-anbernic-rg34xx-sp.dtb"` |
| `DEFAULT_OVERLAYS` | list | Default DT overlays | `"usbhost0 usbhost2"` |
| `OVERLAY_PREFIX` | string | Overlay file prefix | `"sun50i-h700"` |
| `HAS_VIDEO_OUTPUT` | boolean | Board has video output | `"yes"` |

#### **Console & Serial**
| Parameter | Type | Purpose | Example |
|-----------|------|---------|---------|
| `DEFAULT_CONSOLE` | string | Console output type | `"serial"` or `"both"` |
| `SERIALCON` | list | Serial interfaces + baud | `"ttyS0,ttyGS0"` |
| `SRC_CMDLINE` | string | Kernel command line | `"console=ttyS0,115200"` |

#### **Kernel Modules**
| Parameter | Type | Purpose | Example |
|-----------|------|---------|---------|
| `MODULES` | list | Modules for all kernels | `"g_serial"` |
| `MODULES_CURRENT` | list | Current kernel modules | `"extcon-usbc-virtual-pd"` |
| `MODULES_BLACKLIST` | list | Blacklist for all kernels | `"lima sunxi_cedrus"` |

#### **Desktop & Packages**
| Parameter | Type | Purpose | Example |
|-----------|------|---------|---------|
| `FULL_DESKTOP` | boolean | Install full desktop stack | `"yes"` or `"no"` |
| `PACKAGE_LIST_BOARD` | list | Board-specific packages | `"rfkill bluetooth bluez"` |
| `BOARD_FIRMWARE_INSTALL` | string | Firmware install type | `"-full"` |

#### **Advanced Options**
| Parameter | Type | Purpose | Example |
|-----------|------|---------|---------|
| `FORCE_BOOTSCRIPT_UPDATE` | boolean | Force bootscript install | `"yes"` |
| `CPUMIN` | integer | Min CPU frequency (Hz) | `"480000"` |
| `CPUMAX` | integer | Max CPU frequency (Hz) | `"1400000"` |
| `CRUSTCONFIG` | string | Crust firmware config | `"h616_defconfig"` |

#### **File Extensions**
- `.csc` - Community board or no active maintainer ✅ **Recommended for new boards**
- `.conf` - Official board with active maintainer
- `.wip` - Work in progress  
- `.eos` - End of life
- `.tvb` - TV box configuration

### 3. Device Tree Integration

#### Add Device Tree Source
Create or copy device tree file:
```bash
# Copy from reference implementation
cp repos_reference/rocknix-distribution/projects/Allwinner/patches/linux/H700/0146-Create-sun50i-h700-anbernic-rg34xx-sp.dts.patch \
   patch/kernel/sunxi64-current/

# Or create new device tree file
# arch/arm64/boot/dts/allwinner/sun50i-h700-anbernic-rg34xx-sp.dts
```

#### Device Tree Content Structure
```dts
// SPDX-License-Identifier: (GPL-2.0+ OR MIT)
// Copyright (C) 2025 Armbian Community

/dts-v1/;

#include "sun50i-h700.dtsi"
#include <dt-bindings/gpio/gpio.h>
#include <dt-bindings/input/input.h>

/ {
    model = "Anbernic RG34XX-SP";
    compatible = "anbernic,rg34xx-sp", "allwinner,sun50i-h700";

    aliases {
        serial0 = &uart0;
        ethernet0 = &rtl8821cs;
    };

    chosen {
        stdout-path = "serial0:115200n8";
    };

    gpio-keys {
        compatible = "gpio-keys";
        pinctrl-names = "default";
        pinctrl-0 = <&gpio_keys_pins>;

        button-a {
            label = "Button A";
            linux,code = <KEY_SPACE>;
            gpios = <&pio 0 0 GPIO_ACTIVE_LOW>; /* PA0 */
        };

        button-b {
            label = "Button B";
            linux,code = <KEY_LEFTCTRL>;
            gpios = <&pio 0 1 GPIO_ACTIVE_LOW>; /* PA1 */
        };

        /* Additional buttons... */
    };

    gpio-leds {
        compatible = "gpio-leds";
        pinctrl-names = "default";
        pinctrl-0 = <&gpio_leds_pins>;

        power {
            label = "rg34xxsp:power";
            gpios = <&pio 8 12 GPIO_ACTIVE_HIGH>; /* PI12 */
        };

        status {
            label = "rg34xxsp:status";
            gpios = <&pio 8 11 GPIO_ACTIVE_HIGH>; /* PI11 */
        };
    };

    sound {
        compatible = "simple-audio-card";
        simple-audio-card,name = "RG34XXSP Audio";
        simple-audio-card,format = "i2s";
        simple-audio-card,mclk-fs = <256>;

        simple-audio-card,cpu {
            sound-dai = <&i2s0>;
        };

        simple-audio-card,codec {
            sound-dai = <&codec>;
        };
    };
};

&ehci0 {
    status = "okay";
};

&mmc0 {
    vmmc-supply = <&reg_dcdc1>;
    vqmmc-supply = <&reg_dldo1>;
    cd-gpios = <&pio 5 6 GPIO_ACTIVE_LOW>; /* PF6 */
    bus-width = <4>;
    status = "okay";
};

&mmc1 {
    vmmc-supply = <&reg_dcdc1>;
    vqmmc-supply = <&reg_dldo1>;
    non-removable;
    bus-width = <4>;
    status = "okay";

    rtl8821cs: wifi@1 {
        reg = <1>;
        interrupt-parent = <&pio>;
        interrupts = <6 10 IRQ_TYPE_LEVEL_LOW>; /* PG10 */
        interrupt-names = "host-wake";
    };
};

&ohci0 {
    status = "okay";
};

&pio {
    gpio_keys_pins: gpio-keys-pins {
        pins = "PA0", "PA1", "PA2", "PA3", "PA4", "PA5",
               "PA6", "PA7", "PA8", "PA9", "PA10", "PA11", "PA12",
               "PE0", "PE1", "PE2", "PE3";
        function = "gpio_in";
        bias-pull-up;
    };

    gpio_leds_pins: gpio-leds-pins {
        pins = "PI11", "PI12";
        function = "gpio_out";
        drive-strength = <10>;
    };
};

&r_rsb {
    status = "okay";

    axp717: pmic@3a3 {
        compatible = "x-powers,axp717";
        reg = <0x3a3>;
        interrupt-parent = <&nmi_intc>;
        interrupts = <0 IRQ_TYPE_LEVEL_LOW>;
        interrupt-controller;
        #interrupt-cells = <1>;

        regulators {
            reg_dcdc1: dcdc1 {
                regulator-name = "vcc-3v3";
                regulator-min-microvolt = <3300000>;
                regulator-max-microvolt = <3300000>;
                regulator-always-on;
            };

            reg_dldo1: dldo1 {
                regulator-name = "vcc-1v8";
                regulator-min-microvolt = <1800000>;
                regulator-max-microvolt = <1800000>;
                regulator-always-on;
            };
        };
    };
};

&uart0 {
    pinctrl-names = "default";
    pinctrl-0 = <&uart0_ph_pins>;
    status = "okay";
};

&usb_otg {
    dr_mode = "otg";
    status = "okay";
};

&usbphy {
    status = "okay";
};
```

### 4. Kernel Configuration

#### Create Kernel Config
```bash
# Create kernel configuration for the board
./compile.sh kernel-config BOARD=rg34xxsp BRANCH=current

# This creates/modifies:
# config/kernel/linux-sunxi64-current.config
```

#### Essential Kernel Options for RG34XXSP
```
# H700 SoC Support
CONFIG_ARCH_SUNXI=y
CONFIG_MACH_SUN50I_H616=y

# Mali GPU
CONFIG_DRM_PANFROST=y
CONFIG_DRM_PANFROST_DEVFREQ=y

# Display Engine
CONFIG_DRM_SUN4I=y
CONFIG_DRM_SUN8I_DW_HDMI=y
CONFIG_DRM_SUN8I_MIXER=y

# Audio
CONFIG_SND_SOC_SUN8I_CODEC=y
CONFIG_SND_SOC_SUN4I_I2S=y

# Input
CONFIG_INPUT_GPIO_KEYS=y
CONFIG_INPUT_EVDEV=y
CONFIG_INPUT_JOYDEV=y

# WiFi/Bluetooth
CONFIG_RTL8821CS=y
CONFIG_BT_RTL8821CS=y

# GPIO and Pinctrl
CONFIG_PINCTRL_SUN50I_H616=y
CONFIG_GPIO_SYSFS=y

# Power Management
CONFIG_AXP717_PMIC=y
CONFIG_REGULATOR_AXP717=y

# LEDs
CONFIG_LEDS_GPIO=y
CONFIG_LEDS_TRIGGER_HEARTBEAT=y

# USB
CONFIG_USB_MUSB_SUNXI=y
CONFIG_USB_SUNXI_MUSB_FORCE_DEVICE_MODE=y
```

### 5. U-Boot Configuration

#### Create U-Boot Defconfig
Create `config/bootloaders/u-boot_anbernic_rg34xxsp_defconfig`:

```
CONFIG_ARM=y
CONFIG_ARCH_SUNXI=y
CONFIG_DEFAULT_DEVICE_TREE="sun50i-h700-anbernic-rg34xx-sp"
CONFIG_SPL=y
CONFIG_MACH_SUN50I_H616=y
CONFIG_MMC0_CD_PIN=""
CONFIG_MMC_SUNXI_SLOT_EXTRA=2
CONFIG_SPL_SPI_SUNXI=y
CONFIG_SPI=y
CONFIG_TARGET_ANBERNIC_RG34XXSP=y
```

### 6. Patches and Customizations

#### Add Hardware-Specific Patches
Create patch files in `patch/kernel/sunxi64-current/`:

```bash
# Gaming controller support
patch/kernel/sunxi64-current/0001-rg34xxsp-gaming-controller.patch

# Display panel support
patch/kernel/sunxi64-current/0002-rg34xxsp-display-panel.patch

# Audio codec support
patch/kernel/sunxi64-current/0003-rg34xxsp-audio-codec.patch

# Power management
patch/kernel/sunxi64-current/0004-rg34xxsp-power-management.patch
```

#### Create BSP Package
Create `packages/bsp/rg34xxsp/` with:
- `postinst` script for post-installation setup
- Configuration files for hardware-specific settings
- Service files for gaming-specific daemons

### 7. User Customizations

#### Create Custom Configuration
Create `userpatches/config-rg34xxsp.conf`:

```bash
#!/bin/bash

# RG34XXSP specific configuration
BOARD="rg34xxsp"
BRANCH="current"
RELEASE="noble"
BUILD_DESKTOP="no"
BUILD_MINIMAL="yes"
KERNEL_CONFIGURE="no"
BOOTLOADER_TARGET="current"

# Custom packages
PACKAGE_LIST_ADDITIONAL="device-tree-compiler joystick joyutils"

# Image size for gaming device
FIXED_IMAGE_SIZE="4000"

# Enable specific features
ENABLE_EXTENSIONS="gaming-support"
```

#### Create Image Customization Script
Create `userpatches/customize-image.sh`:

```bash
#!/bin/bash

# RG34XXSP image customization
display_alert "Customizing RG34XXSP image" "gaming optimizations" "info"

# Install gaming-specific packages
chroot_sdcard "apt-get -y install joystick joyutils"

# Configure gaming controls
cat > "${SDCARD}/etc/udev/rules.d/99-rg34xxsp-gaming.rules" << EOF
# RG34XXSP Gaming Controls
SUBSYSTEM=="input", ATTRS{name}=="RG34XXSP Gamepad", ENV{ID_INPUT_JOYSTICK}="1"
EOF

# Create gaming startup script
cat > "${SDCARD}/usr/local/bin/rg34xxsp-gaming-init" << EOF
#!/bin/bash
# RG34XXSP Gaming Initialization
echo "Initializing RG34XXSP gaming controls..."
# Add gaming-specific initialization here
EOF

chmod +x "${SDCARD}/usr/local/bin/rg34xxsp-gaming-init"

# Add to systemd
cat > "${SDCARD}/etc/systemd/system/rg34xxsp-gaming.service" << EOF
[Unit]
Description=RG34XXSP Gaming Initialization
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/rg34xxsp-gaming-init
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Enable the service
chroot_sdcard "systemctl enable rg34xxsp-gaming.service"
```

## Community Build Process

### 1. Development Workflow

#### Step 1: Create Working Branch
```bash
git checkout -b rg34xxsp-support
```

#### Step 2: Implement Board Support
- Create board configuration file
- Add device tree source
- Create kernel configuration
- Add necessary patches

#### Step 3: Test Build
```bash
./compile.sh build BOARD=rg34xxsp BRANCH=current RELEASE=noble
```

#### Step 4: Validate on Hardware
- Flash image to SD card
- Test basic functionality
- Verify all hardware components

#### Step 5: Create Pull Request
- Document changes thoroughly
- Include hardware testing results
- Follow Armbian contribution guidelines

### 2. Testing Requirements

#### Minimum Testing Checklist
- [ ] System boots successfully
- [ ] Serial console accessible
- [ ] Display output working
- [ ] WiFi connectivity functional
- [ ] SSH access available
- [ ] Audio output working
- [ ] Input controls responsive
- [ ] Storage devices accessible
- [ ] Power management functional
- [ ] LED indicators working

#### Hardware Validation Tests
- [ ] All GPIO pins properly mapped
- [ ] Device tree correctly describes hardware
- [ ] Kernel modules load successfully
- [ ] No critical boot errors
- [ ] Hardware sensors accessible
- [ ] USB ports functional
- [ ] HDMI output working (if applicable)

### 3. Community Contribution Guidelines

#### Code Quality Standards
- Follow Linux kernel coding style
- Include proper SPDX license headers
- Use descriptive commit messages
- Document all changes thoroughly

#### Documentation Requirements
- Update board-specific documentation
- Include hardware specifications
- Provide testing instructions
- Document known issues/limitations

#### Review Process
- Submit pull request to Armbian repository
- Respond to maintainer feedback
- Provide hardware for testing (if possible)
- Support ongoing maintenance

## Advanced Features

### 1. Multi-Boot Support
```bash
# Configure for multiple boot options
BOOTCONFIG="anbernic_rg34xxsp_defconfig"
BOOTLOADER_TARGET="legacy,current"
KERNEL_TARGET="current,edge"
```

### 2. Hardware Variants
```bash
# Support different hardware variants
if [[ $BOARD == "rg34xxsp-v1" ]]; then
    BOOT_FDT_FILE="allwinner/sun50i-h700-anbernic-rg34xx-sp-v1.dtb"
elif [[ $BOARD == "rg34xxsp-v2" ]]; then
    BOOT_FDT_FILE="allwinner/sun50i-h700-anbernic-rg34xx-sp-v2.dtb"
fi
```

### 3. Performance Optimizations
```bash
# Gaming performance tweaks
function family_tweaks() {
    # CPU governor for gaming
    echo "interactive" > $SDCARD/etc/default/cpufrequtils
    
    # GPU performance mode
    echo "performance" > $SDCARD/sys/class/devfreq/1c40000.gpu/governor
    
    # Gaming-specific sysctl settings
    cat >> $SDCARD/etc/sysctl.d/99-gaming.conf << EOF
# Gaming optimizations
vm.swappiness=1
vm.vfs_cache_pressure=50
kernel.sched_latency_ns=10000000
EOF
}
```

### 4. Gaming-Specific Extensions
```bash
# Create gaming extension
mkdir -p extensions/gaming-support
cat > extensions/gaming-support/gaming-support.sh << EOF
#!/bin/bash

display_alert "Installing gaming support" "RG34XXSP" "info"

# Install gaming libraries
add_packages_to_image "libsdl2-dev libsdl2-image-dev retroarch"

# Configure gaming environment
function gaming_tweaks() {
    # Add gaming-specific configurations
    return 0
}
EOF
```

## Undocumented Armbian Build Secrets

### Critical Knowledge from Real Implementation

#### 1. KERNEL_EXTRA_CONFIG Does NOT Work
**CRITICAL**: Never use `KERNEL_EXTRA_CONFIG` in board configuration files - it is completely non-functional.

```bash
# ❌ WRONG - This does NOTHING
KERNEL_EXTRA_CONFIG="CONFIG_DRM_FBDEV_EMULATION=y CONFIG_PWM_SUN20I=y"

# ✅ CORRECT - Use manual kernel-config method
./compile.sh kernel-config BOARD=rg34xxsp BRANCH=current
# Then manually enable configs in the interactive menu
```

**Why This Matters**: Many examples and guides show `KERNEL_EXTRA_CONFIG` but it's completely ignored by the build system. Hours can be wasted assuming configs are enabled when they're not.

#### 2. BSP Package Installation Method
**CRITICAL**: Firmware and custom files require specific BSP function syntax.

```bash
# ✅ CORRECT - BSP function in board .csc file
function post_family_tweaks_bsp__rg34xxsp_firmware() {
    display_alert "$BOARD" "Installing panel firmware" "info"
    mkdir -p "${destination}"/lib/firmware/
    cp -fr $SRC/packages/bsp/rg34xxsp/lib/firmware/* "${destination}"/lib/firmware/
}
```

**Key Points**:
- Use `${destination}` variable (not hardcoded paths)
- Function name format: `post_family_tweaks_bsp__[boardname]_[function]`
- Must create target directories with `mkdir -p`
- Source path uses `$SRC/packages/bsp/[boardname]/`

#### 3. Board Configuration File Extensions
**CRITICAL**: File extension determines build behavior and board visibility.

```bash
# Community boards (recommended for new hardware)
config/boards/rg34xxsp.csc   # Community Supported Configuration

# Official boards (require maintainer approval)  
config/boards/rg34xxsp.conf  # Official configuration

# Development boards (hidden by default)
config/boards/rg34xxsp.wip   # Work In Progress
config/boards/rg34xxsp.tvb   # TV Box variant
config/boards/rg34xxsp.eos   # End Of Support
```

**Impact**: Using `.conf` for community boards can cause rejection during submission. Always use `.csc` for new community hardware.

#### 4. Device Tree Circular Dependencies
**CRITICAL**: Device tree dependency cycles prevent driver binding and are hard to debug.

```bash
# ❌ PROBLEMATIC - Creates circular dependencies
tcon-top@6510000 ←→ lcd-controller@6511000 ←→ panel@0

# ✅ CORRECT - Linear dependency chain  
clocks → tcon-top → lcd-controller → panel
```

**Detection**: Look for kernel messages like "Fixed dependency cycle(s)" - these indicate non-functional hardware.

**Fix**: Restructure device tree references to create unidirectional dependency flow.

#### 5. Firmware Loading Path Issues
**CRITICAL**: Panel drivers may look in different firmware paths depending on implementation.

```bash
# ❌ COMMON ISSUE - Driver can't find firmware
/lib/firmware/panels/device-panel.panel   # Subdirectory (may not be checked)

# ✅ SOLUTION - Install in multiple locations
/lib/firmware/panels/device-panel.panel   # Original location
/lib/firmware/device-panel.panel          # Root firmware directory

# Or add fallback in driver code
request_firmware("panels/device.panel")   # Try subdirectory first
if (failed) request_firmware("device.panel")  # Fallback to root
```

#### 6. Modern Board Configuration Syntax
**CRITICAL**: Modern Armbian requires `declare -g` syntax for community boards.

```bash
# ✅ CORRECT - Modern syntax
declare -g BOARD_NAME="RG34XXSP"
declare -g BOARDFAMILY="sun50iw9"
declare -g KERNEL_TARGET="current"

# ❌ DEPRECATED - Old syntax (may be rejected)
BOARD_NAME="RG34XXSP"
BOARDFAMILY="sun50iw9"  
KERNEL_TARGET="current"
```

#### 7. DRM Framebuffer Emulation Requirement
**CRITICAL**: Modern DRM requires explicit framebuffer emulation for `/dev/fb0` creation.

```bash
# ✅ REQUIRED for display functionality
CONFIG_DRM_FBDEV_EMULATION=y

# Without this: DRM works, but no framebuffer device created
# Result: Display pipeline functional but no visual output
```

**Symptoms**: 
- DRM device exists (`/dev/dri/card0`)
- Drivers load successfully
- Hardware detected correctly
- But no `/dev/fb0` and no display output

#### 8. Token-Optimized Build Commands
**CRITICAL**: Long builds consume massive token quotas. Use optimized commands.

```bash
# ✅ TOKEN-EFFICIENT - Saves logs locally, shows only essential output
./compile.sh build BOARD=rg34xxsp BRANCH=current RELEASE=bookworm \
BUILD_MINIMAL=yes BUILD_DESKTOP=no KERNEL_CONFIGURE=no \
2>&1 | tee build_log.txt | tail -20

# ❌ TOKEN-WASTEFUL - Full output consumes thousands of tokens
./compile.sh build BOARD=rg34xxsp BRANCH=current RELEASE=bookworm
```

#### 9. Panel Driver Compatible String Issues  
**CRITICAL**: Wrong compatible strings prevent driver binding.

```bash
# ❌ NON-EXISTENT - Causes driver binding failure
compatible = "anbernic,rg34xx-sp-panel", "panel-mipi-dpi-spi";

# ✅ CORRECT - Matches actual driver name
compatible = "anbernic,rg34xx-sp-panel", "panel-mipi";
```

**Detection**: Check `/sys/bus/spi/devices/spi0.0/driver_override` for wrong driver names.

#### 10. Host System Modification Rules
**CRITICAL**: Always ask before modifying host system for builds.

```bash
# ❌ DANGEROUS - Don't install packages without asking
apt install device-tree-compiler

# ✅ CORRECT - Always ask user first
"This build requires device-tree-compiler. May I install it on your system?"
```

**Alternatives**: Suggest containerized builds or Docker when possible to avoid host changes.

## Troubleshooting

### Common Issues

#### 1. Build Failures
```bash
# Clean build environment
./compile.sh clean

# Enable debug logging
./compile.sh build DEBUG=yes BOARD=rg34xxsp BRANCH=current RELEASE=noble
```

#### 2. Device Tree Validation
```bash
# Check device tree syntax
./compile.sh dts-check BOARD=rg34xxsp BRANCH=current

# Validate device tree bindings
scripts/dtc/dt-validate -p dt-bindings/processed-schema.json arch/arm64/boot/dts/allwinner/sun50i-h700-anbernic-rg34xx-sp.dtb
```

#### 3. Hardware Detection Issues
```bash
# Check hardware detection
dmesg | grep -i "rg34xxsp\|h700\|anbernic"

# Verify device tree loading
cat /proc/device-tree/model
cat /proc/device-tree/compatible
```

#### 4. Display Pipeline Debug Commands
```bash
# Check DRM connector status
find /sys/class/drm -name "card0-*" -exec sh -c 'echo "$1: $(cat $1/status 2>/dev/null)"' _ {} \;

# Check panel driver binding
ls -la /sys/bus/spi/devices/spi0.0/driver

# Check firmware loading
dmesg | grep -E "(firmware|panel|mipi)"

# Check TCON binding
ls -la /sys/devices/platform/soc/*lcd-controller*/driver

# Test framebuffer device
ls -la /dev/fb*
```

#### 5. Kernel Config Verification
```bash
# Check if configs actually enabled
zcat /proc/config.gz | grep -E "(CONFIG_DRM_PANEL_MIPI|CONFIG_PWM_SUN20I|CONFIG_DRM_FBDEV_EMULATION)"

# Verify driver modules
find /lib/modules/$(uname -r) -name "*mipi*" -o -name "*sun20i*"
lsmod | grep -E "(panel|pwm)"
```

### Log Analysis

#### Build Logs
```bash
# Check build logs
tail -f output/logs/build-*.log

# Specific component logs
tail -f output/logs/kernel-*.log
tail -f output/logs/uboot-*.log
```

#### Runtime Logs
```bash
# System logs
journalctl -f

# Hardware-specific logs
dmesg | grep -i "gpio\|input\|display\|audio"
```

## Conclusion

Creating community builds for Armbian requires:

1. **Hardware Understanding**: Thorough knowledge of the target hardware
2. **Device Tree Mastery**: Proper device tree implementation
3. **Kernel Configuration**: Appropriate kernel options for hardware support
4. **Testing Validation**: Comprehensive testing on actual hardware
5. **Community Engagement**: Active participation in the Armbian community

The RG34XXSP community build should leverage existing H700 support while adding device-specific optimizations for the gaming handheld form factor. By following this guide and the established Armbian development practices, contributors can successfully add robust support for new hardware platforms.

For ongoing support and collaboration, engage with the Armbian community through:
- GitHub Issues and Pull Requests
- Armbian Forum discussions
- Community chat channels
- Documentation contributions

This comprehensive approach ensures that community builds meet Armbian's quality standards while providing excellent support for new hardware platforms like the RG34XXSP.