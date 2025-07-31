# RG34XXSP Hardware Specifications

## Overview

The ANBERNIC RG34XXSP is a GBA SP-inspired clamshell handheld gaming device featuring a 3.4-inch display, dual analog sticks, and comprehensive connectivity options. This document provides complete hardware specifications for Armbian development.

## Research Status and Knowledge Gaps

### Areas Requiring Further Investigation
*This section tracks uncertain areas and knowledge gaps that need additional research or validation:*

#### ✅ **Confirmed from ROCKNIX Analysis** *(Source: ROCKNIX DTB + source analysis July 18, 2025)*
- [x] **Power LED GPIO**: PI12 pin confirmed for power status LED
- [x] **PWM Backlight**: `pwm-backlight` driver confirmed for display backlight control  
- [x] **Display Engine**: `allwinner,sun50i-h6-display-engine` confirmed
- [x] **Console Configuration**: Dual console setup: `console=ttyS0,115200 console=tty0`
- [x] **Joypad Driver**: `rocknix-singleadc-joypad` with device name "H700 Gamepad"
- [x] **GPIO Mux Pin**: PI0 with `gpio_out` configuration for input multiplexing
- [x] **PWM3 Control**: PI13 pin for PWM3 functionality
- [x] **ADC Channel Configuration**: Complete analog joystick setup with 74HC4052D mux
- [x] **Audio System**: Sun8i codec with PI5 amplifier GPIO and PI3 headphone detection
- [x] **I2C Device Addresses**: AXP717 PMIC on r_i2c bus (standard 0x34 address)
- [x] **Lid Sensor Implementation**: Hall sensor via AXP717 `/sys/class/power_supply/axp2202-battery/hallkey`
- [x] **Complete GPIO Mapping**: All button pins confirmed from ROCKNIX patches

#### ⚠️ **Minor Remaining Details**
- [ ] **Storage Performance**: Actual SD card and eMMC read/write speeds for boot reliability
- [ ] **WiFi/Bluetooth Range**: Actual wireless performance and antenna characteristics
- [ ] **Display Panel Timing**: Specific LCD timing parameters and initialization sequence

#### 🔍 **Implementation Questions** *(Most resolved via ROCKNIX research)*
- [x] **Boot Priority Logic**: MMC0 (primary SD), MMC2 (secondary SD), MMC1 (WiFi)
- [x] **Power Button Behavior**: AXP717 PMIC handles all power management (not GPIO)
- [x] **LED Control Method**: GPIO-controlled via PI12 pin
- [x] **USB-C OTG Configuration**: AXP717 PMIC handles USB Type-C role switching
- [ ] **Serial Console Access**: Physical location of UART pins and voltage levels
- [ ] **Display Panel Timing**: Specific LCD timing parameters and initialization sequence

#### 📋 **Validation Needed**
- [ ] **Storage Performance**: Actual SD card and eMMC read/write speeds for boot reliability
- [ ] **WiFi/Bluetooth Range**: Actual wireless performance and antenna characteristics for connectivity validation

*These areas will be updated as research progresses and hardware testing provides validation.*

## Main Hardware Components

### System-on-Chip (SoC)
- **Chipset**: Allwinner H700 (sun50iw9 family)
- **Architecture**: ARM Cortex-A53 quad-core @ 1.5GHz
- **Process**: 28nm
- **GPU**: Mali-G31 MP2 dual-core @ 850MHz
- **Memory**: 2GB LPDDR4 RAM  
- **Storage**: 64GB eMMC (expandable via microSD to 512GB)
- **ATF Platform**: Uses `sun50i_h616` ARM Trusted Firmware (H700 is H616 derivative)
- **Bootloader**: Compatible with H616 U-Boot configurations

### Display System *(Source: ROCKNIX DTB analysis July 18, 2025)*
- **Screen**: 3.4-inch full-fit IPS LCD
- **Resolution**: 720×480 pixels (3:2 aspect ratio)
- **Touch**: No touchscreen support
- **Panel Type**: MIPI-DPI-SPI compatible
- **Color Depth**: 24-bit RGB888
- **Display Engine**: `allwinner,sun50i-h6-display-engine` (confirmed from ROCKNIX DTB)
- **Driver Requirements**: 
  - Display Engine (DE) driver for pipeline management
  - DRM/KMS driver for modern graphics stack
  - Framebuffer driver for console output
  - Panel driver for timing and power control
- **Backlight Control**:
  - **Method**: `pwm-backlight` driver (confirmed from ROCKNIX DTB)
  - **PWM Channel**: Dedicated PWM channel for brightness control
  - **GPIO Enable**: GPIO pin for backlight power control
  - **Brightness Levels**: 8-bit resolution (0-255)
- **Console Output**: Dual console configuration: `console=ttyS0,115200 console=tty0` (serial + display)

### Audio System *(Source: ROCKNIX source analysis July 18, 2025)*
- **Codec**: Built-in sun8i-codec (Allwinner internal)
- **Output**: Dual speakers + 3.5mm headphone jack
- **Amplifier**: 74HC4052D analog multiplexer
- **Amplifier GPIO**: PI5 (`allwinner,pa-gpios = <&pio 8 5 GPIO_ACTIVE_HIGH>`)
- **Headphone Detection**: PI3 (`hp-det-gpios = <&pio 8 3 GPIO_ACTIVE_HIGH>`)
- **Audio Routing**: 
  ```
  allwinner,audio-routing = "Speaker", "LINEOUT",
                            "Headphone", "LINEOUT";
  ```
- **Microphone**: Built-in microphone with bias control
- **Automatic Switching**: Hardware-based headphone detection via PI3 GPIO
- **Formats**: "flac", "mp3", "wav", "ape", "aif", "aiff", "ogg", "wma", "aac", "m4a", "m4r"

### Input Controls

#### D-Pad and Action Buttons *(Source: ROCKNIX source analysis July 18, 2025)*
- **Input Driver**: `rocknix-singleadc-joypad` custom gaming input handler
- **Device Name**: "H700 Gamepad" 
- **GPIO Mux**: PI0 pin with `gpio_out` configuration for input multiplexing
- **Implementation**: Single ADC channel multiplexed input system (gaming-optimized)
- **Confirmed GPIO Mapping**: *(From ROCKNIX patches)*
  - **D-Pad**: PA6 (Up), PA8 (Left), PE0 (Down), PA9 (Right)
  - **Action Buttons**: PA0 (A), PA1 (B), PA2 (X), PA3 (Y)
  - **Shoulder Buttons**: PA10 (L1), PA11 (L2), PA12 (R1), PA7 (R2)
  - **System Buttons**: PA5 (Select), PA4 (Start), PE3 (Menu)
  - **Stick Clicks**: PE8 (Left), PE9 (Right)
  - **Volume Controls**: *(GPIO pins TBD - implemented as gpio-keys-volume)*

#### Analog Controls *(Source: ROCKNIX source analysis July 18, 2025)*
- **ADC Multiplexer**: 74HC4052D analog multiplexer for joystick inputs
- **ADC Control GPIOs**: 
  - **Mux A**: PI1 (`amux-a-gpios = <&pio 8 1 GPIO_ACTIVE_LOW>`)
  - **Mux B**: PI2 (`amux-b-gpios = <&pio 8 2 GPIO_ACTIVE_LOW>`)
- **ADC Channel**: GPADC channel 0 (`io-channels = <&gpadc 0>`)
- **Channel Mapping**: `amux-channel-mapping = <0 2 1 3>` (ABS_RY, ABS_RX, ABS_Y, ABS_X)
- **Calibration Values**:
  - **Scale**: `button-adc-scale = <2>`
  - **Dead Zone**: `button-adc-deadzone = <128>`
  - **Fuzz/Flat**: `button-adc-fuzz = <32>`, `button-adc-flat = <32>`
  - **Tuning**: 70% for all axes (`p-tuning = 70, n-tuning = 70`)
- **Configuration**: 
  - **Poll Interval**: 10ms
  - **Channel Count**: 4 (`amux-count = <4>`)
  - **Inversion Flags**: `invert-absrx` and `invert-absry` set for RG34XXSP
- **Resolution**: 12-bit ADC precision via Allwinner GPADC

#### Power and Reset Controls *(Source: ROCKNIX DTB + source analysis July 18, 2025)*
- **Power Button Controller**: **AXP717 PMIC** (not GPIO-based)
  - **Input Device**: `axp20x-pek` (AXP20X Power Enable Key)
  - **Driver**: AXP717 PMIC driver creates hardware-managed power button
  - **Event Type**: `KEY_POWER` press/release events via input subsystem
  - **Advantages**: Hardware-level power management, more reliable than GPIO
- **Power LED**: PI12 GPIO pin for power status indication
- **Lid Switch**: `gpio-keys-lid` device tree node for clamshell detection
  - **Event Type**: `SW_LID` open/close events
  - **Implementation**: Separate from power button (GPIO-based)
- **PWM Controls**: PI13 pin for PWM3 functionality (potential power management)
- **ROCKNIX Current Status**: Power button functionality **DISABLED** due to broken sleep
  - `HandlePowerKey=ignore` in systemd configuration
  - `/usr/bin/suspendmode off` disables suspend functionality
- **Armbian Implementation**: Should enable proper power management unlike ROCKNIX
- **GPIO Mapping**: 
  - Power LED: PI12 (confirmed from ROCKNIX DTB)
  - Power button: AXP717 PMIC hardware (not GPIO)
  - Lid sensor: Hall sensor via AXP717 `/sys/class/power_supply/axp2202-battery/hallkey`
- **Expected Behavior**: 
  - Short press: Sleep/wake (systemd configurable)
  - Long press: Power off (systemd configurable)
  - Lid close: Automatic sleep (configurable via `SW_LID` events)

### Wireless Connectivity

#### WiFi
- **Chipset**: Realtek RTL8821CS
- **Interface**: SDIO (Secure Digital Input/Output)
- **Standards**: IEEE 802.11 a/b/g/n/ac
- **Bands**: 2.4GHz and 5GHz dual-band
- **Antenna**: Internal PCB antenna
- **GPIO Control**: Power sequencing via dedicated GPIO

#### Bluetooth
- **Chipset**: RTL8821CS-BT (integrated with WiFi)
- **Version**: Bluetooth 4.2
- **Interface**: UART1 with RTS/CTS flow control
- **GPIO Control**: Enable/disable and wake signals
- **Profiles**: A2DP, HID, HFP support

### Power Management

#### Battery System
- **Capacity**: 3,300mAh lithium-ion battery
- **Type**: Replaceable battery pack
- **Charging**: USB-C PD (Power Delivery)
- **Voltage**: 3.7V nominal
- **Runtime**: 4-6 hours typical gaming

#### Power Management IC (PMIC) *(Source: ROCKNIX source analysis July 18, 2025)*
- **Controller**: AXP717 (Allwinner standard)
- **I2C Bus**: r_i2c (likely address 0x34)
- **Features**: Battery charging, voltage regulation, power sequencing, USB Type-C role switching
- **Regulators**: Multiple voltage rails for SoC, memory, peripherals
- **Power Button**: Hardware-managed via `axp20x-pek` input device
- **Battery Interface**: `/sys/class/power_supply/axp2202-battery/` (includes hall sensor)
- **Hall Sensor**: Lid detection via `/sys/class/power_supply/axp2202-battery/hallkey`

#### LED Indicators *(Source: ROCKNIX DTB analysis July 18, 2025)*
- **Power LED**: GPIO PI12 (confirmed from ROCKNIX DTB)
- **Control**: GPIO LED drivers via device tree `gpio-leds` configuration
- **Boot Behavior**: No LED activity until GPIO drivers initialize (normal)
- **Device Tree Node**: `led-0` (power), `led-1` (status) in ROCKNIX configuration

### Storage and Expansion

#### SD Card Slots and Boot Configuration *(Source: ROCKNIX source analysis July 18, 2025)*
- **MMC0 (Primary SD)**: Card detect on PF6 (`cd-gpios = <&pio 5 6 GPIO_ACTIVE_LOW>`)
- **MMC2 (Secondary SD)**: Card detect on PE22 (`cd-gpios = <&pio 4 22 GPIO_ACTIVE_LOW>`)
- **MMC1**: WiFi controller (RTL8821CS SDIO)
- **Boot Priority**: MMC0 → MMC2 → Internal eMMC (as per device tree aliases)
- **Voltage Regulators**: 
  - **MMC0**: `vmmc-supply = <&reg_cldo3>`
  - **MMC2**: `vmmc-supply = <&reg_vcc3v3_mmc2>` (GPIO controlled: PE4)
  - **MMC2 I/O**: `vqmmc-supply = <&reg_cldo3>`
- **Boot Sector**: Standard Allwinner layout (SPL at 8KB, U-Boot at ~40KB)
- **Card Requirements**: Class 10 minimum, UHS-I recommended for performance

#### Internal Storage
- **Primary**: 64GB eMMC 5.1
- **Boot**: Dedicated boot partition
- **User**: Available for OS and games

#### External Storage
- **Slot 1**: microSD card slot (up to 512GB)
- **Slot 2**: Second microSD card slot (up to 512GB)
- **Format**: FAT32, exFAT, ext4 support
- **Hot-swap**: Supported with proper unmounting

### Connectivity Ports

#### USB-C Port *(Source: ROCKNIX source analysis July 18, 2025)*
- **Function**: Charging and data transfer
- **Standard**: USB 2.0 with PD support
- **OTG**: USB On-The-Go capable with AXP717 role switching
- **Role Switch**: Handled by AXP717 PMIC (`usb-role-switch` support)
- **Data Rate**: 480 Mbps

#### HDMI Output
- **Type**: Mini HDMI 1.4
- **Resolution**: Up to 1080p @ 60Hz
- **Audio**: Digital audio output support
- **CEC**: Consumer Electronics Control support

#### Audio Jack
- **Type**: 3.5mm TRRS (Tip-Ring-Ring-Sleeve)
- **Function**: Headphone output + microphone input
- **Impedance**: 16-32 ohm headphone support
- **Detection**: Automatic insertion detection

### Physical Specifications

#### Form Factor
- **Design**: Clamshell (GBA SP style)
- **Dimensions**: 152mm × 89mm × 24mm (closed)
- **Weight**: 280g (approximate)
- **Colors**: Yellow, Gray, Black, Indigo

#### Build Quality
- **Materials**: ABS plastic shell
- **Hinges**: Dual-axis hinge mechanism
- **Buttons**: Tactile membrane switches
- **Sticks**: Hall effect analog sensors
- **Durability**: Consumer-grade construction

## GPIO Pin Mapping

*Source: ROCKNIX device tree files `sun50i-h700-anbernic-rg35xx-2024.dts` and `sun50i-h700-anbernic-rg34xx-sp.dts`*

### SoC Pin Assignments (Verified from ROCKNIX Device Trees)
```
Port A (PA):
PA0  - Button A (BTN_EAST)
PA1  - Button B (BTN_SOUTH)  
PA2  - Button Y (BTN_WEST)
PA3  - Button X (BTN_NORTH)
PA4  - Button Start (BTN_START)
PA5  - Button Select (BTN_SELECT)
PA6  - D-Pad Up (BTN_DPAD_UP)
PA7  - Button R2 (BTN_TR2)
PA8  - D-Pad Left (BTN_DPAD_LEFT)
PA9  - D-Pad Right (BTN_DPAD_RIGHT)
PA10 - Button L1 (BTN_TL)
PA11 - Button L2 (BTN_TL2)
PA12 - Button R1 (BTN_TR)

Port E (PE):
PE0  - D-Pad Down (BTN_DPAD_DOWN)
PE3  - Menu Button (BTN_MODE)
PE4  - MMC2 Power Control (GPIO_ACTIVE_HIGH)
PE8  - Left Joystick Button (BTN_THUMBL)
PE9  - Right Joystick Button (BTN_THUMBR)
PE22 - MMC2 Card Detect (GPIO_ACTIVE_LOW)

Port F (PF):
PF6  - MMC0 Card Detect (GPIO_ACTIVE_LOW)

Port I (PI):
PI1  - Analog Mux A (amux-a-gpios)
PI2  - Analog Mux B (amux-b-gpios)
```

### Analog Joystick Configuration
*Source: ROCKNIX joypad driver configuration*
```
ADC Channel: GPADC channel 0
Mux Control: PI1 (amux-a), PI2 (amux-b)
Channel Mapping: ABS_RY=0, ABS_RX=2, ABS_Y=1, ABS_X=3
Deadzone: 128
Poll Interval: 10ms
Tuning: 70% scaling for all axes
RG34XXSP Specific: invert-absrx, invert-absry, amux-count=4
```

### Power Management
```
AXP717 PMIC:
- DCDC1: 3.3V (System)
- DCDC2: 1.1V (CPU Core)
- DCDC3: 1.5V (DDR)
- LDO1: 3.3V (IO)
- LDO2: 1.8V (Internal)
- LDO3: 2.8V (WiFi)
```

## Device Tree Configuration

### Base Device Tree
- **File**: `sun50i-h700-anbernic-rg34xx-sp.dts`
- **Parent**: `sun50i-h700.dtsi`
- **Compatible**: `anbernic,rg34xx-sp`, `allwinner,sun50i-h700`

### Critical Device Tree Nodes
```dts
/ {
    model = "Anbernic RG34XX-SP";
    compatible = "anbernic,rg34xx-sp", "allwinner,sun50i-h700";
    
    gpio-keys {
        compatible = "gpio-keys";
        // Button definitions
    };
    
    gpio-leds {
        compatible = "gpio-leds";
        // LED definitions
    };
    
    sound {
        compatible = "simple-audio-card";
        // Audio routing
    };
};
```

## Driver Requirements

### Essential Drivers
- **Display**: `panel-mipi-dpi-spi` (gaming panel support)
- **Audio**: `sun8i-codec` (internal codec)
- **WiFi**: `rtl8821cs` (SDIO interface)
- **Bluetooth**: `rtl8821cs-bt` (UART interface)
- **GPIO**: `sun50i-h616-pinctrl` (pin control)
- **Power**: `axp717-pmic` (power management)
- **Input**: `gpio-keys` (button input)
- **Joystick**: Custom ADC-based driver

### Gaming-Specific Drivers
- **Joypad**: ROCKNIX custom gaming joypad driver
- **Panel**: Gaming device-specific panel driver
- **Audio Routing**: Gaming-optimized audio paths
- **Power Management**: Gaming-optimized governors

## Performance Characteristics

### CPU Performance
- **Single-core**: ~1,200 PassMark points
- **Multi-core**: ~4,800 PassMark points
- **Architecture**: ARMv8-A instruction set
- **Cache**: 32KB L1I + 32KB L1D per core, 512KB shared L2

### GPU Performance
- **Compute Units**: 2 execution engines
- **Memory**: Shared system memory
- **API Support**: OpenGL ES 3.2, Vulkan 1.0
- **Performance**: ~40 GFLOPS theoretical

### Memory Bandwidth
- **LPDDR4**: ~12.8 GB/s theoretical
- **eMMC**: ~200 MB/s read, ~100 MB/s write
- **microSD**: Class 10 minimum (10 MB/s)

## Thermal Management

### Thermal Zones
- **CPU**: Active cooling via case ventilation
- **GPU**: Integrated thermal throttling
- **Battery**: Temperature monitoring via PMIC
- **Ambient**: Passive cooling design

### Operating Temperatures
- **Operating**: 0°C to 40°C
- **Storage**: -20°C to 60°C
- **Charging**: 0°C to 35°C

## Compatibility Notes

### Armbian Support Level
- **SoC**: Full H700 support in sun50iw9 family
- **WiFi/BT**: Requires RTL8821CS driver patches
- **Display**: Requires gaming panel driver port
- **Audio**: Requires gaming audio routing
- **Input**: Requires gaming joypad driver

### Kernel Requirements
- **Minimum**: Linux 6.12+ (H700 support)
- **Recommended**: Linux 6.15+ (full gaming support)
- **Patches**: ROCKNIX gaming patches required

### Bootloader Support
- **U-Boot**: sun50i-h616 configuration
- **ATF**: ARM Trusted Firmware bl31.bin
- **SPL**: Secondary Program Loader support

## Development Notes

### Known Issues
- **Bluetooth**: Limited profile support in mainline
- **HDMI**: Requires additional patches for full support
- **Battery**: Calibration needed for accurate reporting
- **Sleep**: Lid-close sleep function needs implementation

### Future Enhancements
- **Display**: Higher refresh rate support
- **Audio**: DSP audio processing
- **Performance**: CPU/GPU overclocking options
- **Power**: Advanced power saving modes

## Distribution-Specific Hardware Handling

### Alpine H700 Implementation

**Approach**: Extracts components from stock firmware for hardware support.

**Hardware Handling**:
- **Kernel**: Uses stock H700 kernel from factory image
- **Drivers**: Relies on stock driver binaries
- **Firmware**: Extracts all firmware blobs from factory.img
- **Device Tree**: Uses stock device tree configuration
- **Display**: Stock display driver with original calibration
- **Audio**: Stock audio codec configuration
- **WiFi/BT**: Stock RTL8821CS drivers
- **Input**: Stock input driver configuration

**Limitations**:
- No customization of hardware drivers
- Limited to stock firmware capabilities
- Cannot optimize for specific use cases
- Dependent on factory image quality

### Knulli Distribution Implementation

**Approach**: Buildroot-based system with H700-specific board configuration.

**Hardware Handling**:
- **Kernel**: Linux 4.9.170 from orangepi-xunlong repository
- **Architecture**: ARM64 (aarch64) Cortex-A53 with NEON FPU
- **GPU**: Mali-G31 with fbdev driver (libmali-g31-fbdev)
- **Display**: Custom gaming panel support
- **Audio**: sun8i-codec with gaming optimizations
- **WiFi/BT**: RTL8821CS with custom power management
- **Input**: Custom SDL1/SDL2 input mapping for gaming

**Board Configuration** (`knulli-h700.board`):
```
BR2_aarch64=y
BR2_cortex_a53=y
BR2_ARM_FPU_NEON_FP_ARMV8=y
BR2_PACKAGE_BATOCERA_TARGET_H700=y
BR2_LINUX_KERNEL_CUSTOM_REPO_URL="https://github.com/orangepi-xunlong/linux-orangepi.git"
BR2_LINUX_KERNEL_CUSTOM_REPO_VERSION="orange-pi-4.9-sun50iw9"
```

**Gaming-Specific Features**:
- SDL1/SDL2 with fbdev backend
- Custom audio routing for gaming
- ADB support for debugging
- Optimized for gaming performance

### ROCKNIX Distribution Implementation

**Approach**: Extensive patching system for comprehensive H700 gaming support.

**Hardware Handling**:
- **Kernel**: Heavily patched mainline with gaming optimizations
- **Display**: Display Engine 3.3 (DE33) support with LCD timing controller
- **Audio**: sun4i-codec with headphone detection for Anbernic RG35XX devices
- **GPU**: Mali-G31 with GPU OPP (Operating Performance Points)
- **Backlight**: PWM backlight control
- **Input**: Custom ROCKNIX joypad driver
- **USB**: USB OTG support
- **LEDs**: RGB LED support
- **HDMI**: HDMI audio and video output

**Key Patches Applied**:
- `0001-v8_20250310_ryan_drm_sun4i_add_display_engine_3_3_de33_support.patch`
- `0003-20250216_ryan_arm64_dts_allwinner_h616_add_lcd_timing_controller.patch`
- `0004-v3_20250215_ryan_asoc_sun4i_codec_add_headphone_detection.patch`
- `0005-v2_20250416_andre_przywara_arm64_sunxi_h616_enable_mali_gpu.patch`
- `0140-rg35xx-2024-use-rocknix-joypad-driver.patch`
- `0145-Create-sun50i-h700-anbernic-rg34xx.dts.patch`
- `0146-Create-sun50i-h700-anbernic-rg34xx-sp.dts.patch`

**RG34XXSP Specific Device Tree**:
```dts
// sun50i-h700-anbernic-rg34xx-sp.dts
/ {
    model = "Anbernic RG34XX-SP";
    compatible = "anbernic,rg34xx-sp", "allwinner,sun50i-h700";
    
    gpio-keys {
        compatible = "gpio-keys";
        pinctrl-names = "default";
        pinctrl-0 = <&gpio_keys_pins>;
        
        button-a { /* GPIO button definitions */ };
        button-b { /* GPIO button definitions */ };
        /* ... more buttons */
    };
    
    gpio-leds {
        compatible = "gpio-leds";
        pinctrl-names = "default";
        pinctrl-0 = <&gpio_leds_pins>;
        
        led-1 { /* LED definitions */ };
        led-2 { /* LED definitions */ };
    };
    
    sound {
        compatible = "simple-audio-card";
        /* Audio routing for gaming */
    };
};
```

**Hardware Optimizations**:
- GPU overclocking support in `400-set_gpu_overclock`
- Force feedback support
- Panel variants for different screen types
- Gaming-specific power management

### Armbian Integration Requirements

**Based on Distribution Analysis**:

**Essential Components for RG34XXSP**:
1. **Device Tree**: Port ROCKNIX `sun50i-h700-anbernic-rg34xx-sp.dts`
2. **Kernel Config**: Adapt Knulli H700 configuration for mainline
3. **Display Driver**: Port panel-mipi-dpi-spi driver
4. **Audio Driver**: Port sun8i-codec with headphone detection
5. **WiFi/BT**: Port RTL8821CS drivers with power management
6. **Input Driver**: Port ROCKNIX joypad driver
7. **GPU Driver**: Mali-G31 with OPP support
8. **Power Management**: AXP717 PMIC integration

**Hardware Support Priority**:
1. **Phase 1**: Basic boot, display, serial console
2. **Phase 2**: WiFi, SSH, storage access
3. **Phase 3**: Audio, input controls, LEDs
4. **Phase 4**: GPU, HDMI, power management
5. **Phase 5**: Gaming optimizations, overclocking

**Key Differences from Stock Distributions**:
- Armbian uses mainline kernel (6.12+) vs legacy 4.9.170
- Armbian follows Debian package management vs custom builds
- Armbian requires upstream-compatible drivers vs custom gaming patches
- Armbian focuses on general-purpose use vs gaming specialization

**Integration Strategy**:
- Start with ROCKNIX device tree as foundation
- Port essential drivers to mainline kernel
- Adapt hardware configurations for Armbian standards
- Maintain gaming compatibility while ensuring general usability

This comprehensive hardware specification provides the foundation for developing complete Armbian support for the RG34XXSP handheld gaming device.