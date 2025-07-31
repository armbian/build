# RG34XXSP Mouse Configuration Guide

This guide explains how to configure the RG34XXSP joysticks and buttons as mouse input for desktop use instead of gamepad functionality.

## Overview

The RG34XXSP hardware includes:
- **Analog joysticks**: Can be configured as mouse X/Y movement
- **Select button**: Can be configured as left mouse click
- **Start button**: Can be configured as right mouse click
- **Other buttons**: Can be configured as additional mouse functions

## Current Configuration Status

### Current Device Tree Setup
The device tree currently configures a ROCKNIX custom gamepad driver:
```dts
joypad: rocknix-singleadc-joypad {
    compatible = "rocknix-singleadc-joypad";
    io-channels = <&gpadc 0>;
    // Analog joystick configuration via ADC multiplexer
}
```

**Problem**: This requires the ROCKNIX custom driver which is not included in the Armbian kernel build.

## Mouse Configuration Options

### Option 1: Replace with Standard Linux Input Drivers (Recommended)

**Advantages:**
- Uses standard Linux drivers (no custom patches needed)
- Direct mouse input support
- Simple configuration

**Implementation:**

#### Files to Modify:
- `kernel-patches-tracking/arch/arm64/boot/dts/allwinner/sun50i-h700-anbernic.dtsi`
- `kernel-patches-tracking/arch/arm64/boot/dts/allwinner/sun50i-h700-anbernic-rg35xx-sp.dts`

#### Device Tree Changes:

**File**: `sun50i-h700-anbernic.dtsi`
```dts
// Replace the ROCKNIX joypad configuration with standard drivers

// Mouse movement via ADC joystick
adc-mouse {
    compatible = "adc-joystick";
    io-channels = <&gpadc 0>;
    
    // Configure as mouse instead of gamepad
    #address-cells = <1>;
    #size-cells = <0>;
    
    axis@0 {
        reg = <0>;
        linux,code = <REL_X>;        // Mouse X movement
        abs-range = <0 4095>;
        abs-fuzz = <4>;
        abs-flat = <200>;
    };
    
    axis@1 {
        reg = <1>; 
        linux,code = <REL_Y>;        // Mouse Y movement
        abs-range = <0 4095>;
        abs-fuzz = <4>;
        abs-flat = <200>;
    };
};

// Mouse buttons via GPIO
gpio-keys-mouse {
    compatible = "gpio-keys";
    
    mouse-left {
        label = "Mouse Left Click";
        linux,code = <BTN_LEFT>;
        gpios = <&pio 0 11 GPIO_ACTIVE_LOW>; /* PA11 - Select button */
    };
    
    mouse-right {
        label = "Mouse Right Click";  
        linux,code = <BTN_RIGHT>;
        gpios = <&pio 0 8 GPIO_ACTIVE_LOW>; /* PA8 - Start button */
    };
    
    mouse-middle {
        label = "Mouse Middle Click";
        linux,code = <BTN_MIDDLE>;
        gpios = <&pio 0 0 GPIO_ACTIVE_LOW>; /* PA0 - A button (optional) */
    };
};
```

#### Required Kernel Configuration:
```
CONFIG_INPUT_JOYDEV=y
CONFIG_INPUT_EVDEV=y
CONFIG_JOYSTICK_ADC=y
CONFIG_INPUT_GPIO_KEYS=y
```

### Option 2: Userspace Mouse Emulation Service

**Advantages:**
- No device tree changes needed
- Can work with existing gamepad configuration
- User can enable/disable easily
- Configurable sensitivity and button mapping

**Implementation:**

#### Create Mouse Emulation Service:

**File**: `packages/bsp/anbernic/systemd_services/gamepad-mouse-emulation`
```bash
#!/bin/bash
# RG34XXSP Gamepad to Mouse Emulation Service

GAMEPAD_DEVICE=""
MOUSE_SENSITIVITY=3
DEADZONE=100

# Find the gamepad device
find_gamepad() {
    for device in /dev/input/event*; do
        if udevadm info --query=all --name="$device" | grep -q "H700 Gamepad"; then
            GAMEPAD_DEVICE="$device"
            return 0
        fi
    done
    return 1
}

# Convert gamepad input to mouse
gamepad_to_mouse() {
    evtest "$GAMEPAD_DEVICE" --grab | while read line; do
        case "$line" in
            *"ABS_X"*) 
                value=$(echo "$line" | grep -o 'value [0-9-]*' | cut -d' ' -f2)
                if [ "$value" -gt $DEADZONE ]; then
                    xdotool mousemove_relative $((value/500*MOUSE_SENSITIVITY)) 0
                elif [ "$value" -lt -$DEADZONE ]; then
                    xdotool mousemove_relative $((value/500*MOUSE_SENSITIVITY)) 0
                fi
                ;;
            *"ABS_Y"*)
                value=$(echo "$line" | grep -o 'value [0-9-]*' | cut -d' ' -f2)
                if [ "$value" -gt $DEADZONE ]; then
                    xdotool mousemove_relative 0 $((value/500*MOUSE_SENSITIVITY))
                elif [ "$value" -lt -$DEADZONE ]; then
                    xdotool mousemove_relative 0 $((value/500*MOUSE_SENSITIVITY))
                fi
                ;;
            *"BTN_SELECT"*"value 1"*)
                xdotool click 1  # Left click
                ;;
            *"BTN_START"*"value 1"*)
                xdotool click 3  # Right click
                ;;
        esac
    done
}

# Main execution
if find_gamepad; then
    echo "Found gamepad: $GAMEPAD_DEVICE"
    gamepad_to_mouse
else
    echo "No gamepad device found"
    exit 1
fi
```

**Systemd Service**: `packages/bsp/anbernic/systemd_services/gamepad-mouse-emulation.service`
```ini
[Unit]
Description=RG34XXSP Gamepad Mouse Emulation
After=graphical.target
Wants=graphical.target
ConditionPathExists=/usr/bin/xdotool

[Service]
Type=simple
User=pi
ExecStartPre=/usr/bin/apt-get install -y xdotool evtest
ExecStart=/usr/local/bin/gamepad-mouse-emulation
Restart=always
RestartSec=5
Environment=DISPLAY=:0

[Install]
WantedBy=graphical.target
```

### Option 3: X11/Wayland Input Configuration

**Advantages:**
- No kernel changes needed
- Works with existing input devices
- Desktop environment handles the mapping

**Implementation:**

#### X11 Configuration:
**File**: Create via BSP package: `/etc/X11/xorg.conf.d/99-rg34xxsp-mouse.conf`
```
Section "InputClass"
    Identifier "RG34XXSP Gamepad as Mouse"
    MatchDevicePath "/dev/input/event*"
    MatchProduct "H700 Gamepad"
    
    # Enable mouse emulation
    Option "EmulateWheel" "on"
    Option "EmulateWheelButton" "2"
    Option "EmulateWheelTimeout" "200"
    
    # Map axes to mouse movement
    Option "XAxisMapping" "6 7"
    Option "YAxisMapping" "4 5"
    
    # Button mapping
    Option "ButtonMapping" "1 2 3 4 5 6 7 8 9 10 11 12"
EndSection
```

#### Wayland Configuration:
**libinput configuration**: `/etc/libinput/local-overrides.quirks`
```
[RG34XXSP Gamepad Mouse]
MatchName=H700 Gamepad
AttrEventCode=+BTN_LEFT;+BTN_RIGHT;+REL_X;+REL_Y
```

## Implementation Steps

### For Option 1 (Device Tree Modification):

1. **Modify Device Tree Files:**
   ```bash
   # Edit the base device tree
   nano kernel-patches-tracking/arch/arm64/boot/dts/allwinner/sun50i-h700-anbernic.dtsi
   
   # Replace the rocknix-singleadc-joypad configuration with adc-mouse and gpio-keys-mouse
   ```

2. **Update Kernel Configuration:**
   ```bash
   # Ensure required configs are enabled
   ./compile.sh kernel-config BOARD=rg34xxsp BRANCH=current
   # Enable: CONFIG_JOYSTICK_ADC, CONFIG_INPUT_GPIO_KEYS, CONFIG_INPUT_EVDEV
   ```

3. **Rebuild and Test:**
   ```bash
   ./compile.sh build BOARD=rg34xxsp BRANCH=current RELEASE=noble BUILD_DESKTOP=yes
   ```

### For Option 2 (Userspace Service):

1. **Add Service to BSP Package:**
   ```bash
   # Copy the service files to packages/bsp/anbernic/systemd_services/
   ```

2. **Update Board Configuration:**
   ```bash
   # Add service installation to rg34xxsp.csc post_family_tweaks_bsp function
   ```

3. **User Activation:**
   ```bash
   # Service is installed but not enabled by default
   sudo systemctl enable gamepad-mouse-emulation.service
   sudo systemctl start gamepad-mouse-emulation.service
   ```

### For Option 3 (X11 Configuration):

1. **Add Configuration to BSP Package:**
   ```bash
   # Add X11 config file to packages/bsp/anbernic/
   ```

2. **Install via BSP Function:**
   ```bash
   # Copy X11 config during BSP installation
   ```

## GPIO Pin Mapping Reference

Based on the current device tree configuration:

| Function | GPIO Pin | Device Tree Reference |
|----------|----------|-----------------------|
| Select Button | PA11 | `<&pio 0 11 GPIO_ACTIVE_LOW>` |
| Start Button | PA8 | `<&pio 0 8 GPIO_ACTIVE_LOW>` |
| A Button | PA0 | `<&pio 0 0 GPIO_ACTIVE_LOW>` |
| B Button | PA1 | `<&pio 0 1 GPIO_ACTIVE_LOW>` |
| X Button | PA2 | `<&pio 0 2 GPIO_ACTIVE_LOW>` |
| Y Button | PA3 | `<&pio 0 3 GPIO_ACTIVE_LOW>` |
| L1 Button | PA4 | `<&pio 0 4 GPIO_ACTIVE_LOW>` |
| R1 Button | PA5 | `<&pio 0 5 GPIO_ACTIVE_LOW>` |

**Note**: Verify actual GPIO assignments by checking the complete device tree patch file.

## ADC Configuration

The analog joysticks use ADC multiplexer configuration:
- **ADC Channel**: `<&gpadc 0>`
- **Multiplexer Control**: GPIO PI1, PI2
- **Channel Mapping**: `amux-channel-mapping = <0 2 1 3>` (ABS_RY ABS_RX ABS_Y ABS_X)

## Testing and Validation

### Test Mouse Functionality:
```bash
# Check if mouse input device is created
ls /dev/input/mice
cat /proc/bus/input/devices | grep -i mouse

# Test mouse movement
evtest /dev/input/eventX  # Replace X with mouse event device number

# Test in desktop environment
# Move joysticks -> should move mouse cursor
# Press select button -> should left click
# Press start button -> should right click
```

### Troubleshooting:
```bash
# Check device tree loading
dmesg | grep -i -E "(adc|mouse|gpio-keys)"

# Check input devices
cat /proc/bus/input/devices

# Check X11 input configuration (if using Option 3)
xinput list
xinput list-props "H700 Gamepad"
```

## Recommendation

**Option 1 (Device Tree Modification)** is recommended because:
- ✅ Provides native mouse input
- ✅ Works in both X11 and Wayland
- ✅ No additional software dependencies
- ✅ Cleaner implementation
- ✅ Works at console level (not just desktop)

**Option 2 (Userspace Service)** is good for:
- ✅ Testing and experimentation
- ✅ User-configurable sensitivity
- ✅ Can be enabled/disabled easily
- ❌ Requires desktop environment
- ❌ Additional software dependencies

**Option 3 (X11 Configuration)** is suitable for:
- ✅ Quick setup without kernel changes
- ❌ X11 only (doesn't work in Wayland)
- ❌ Desktop environment dependent