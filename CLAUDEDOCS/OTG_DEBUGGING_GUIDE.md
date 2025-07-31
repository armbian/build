# RG34XXSP USB OTG Debugging and Solution Guide for Embedded Claude

## Current Problem Summary

The RG34XXSP USB OTG connector is not detecting keyboards, mice, or USB storage devices. The device tree configuration appears correct (dr_mode = "otg", VBUS regulator configured), but USB devices are not being detected when plugged in.

## Hardware Context - CRITICAL SAFETY INFORMATION ⚠️

**BEFORE ANY TESTING**: The RG34XXSP uses these GPIO pins for USB OTG:
- **PI4 (GPIO 260)**: USB ID detection pin - READ ONLY, do not write to this pin
- **PI16 (GPIO 272)**: VBUS control pin - Controls 5V power to USB devices

**⚠️ HARDWARE DAMAGE WARNINGS:**
1. **Never write to PI4/GPIO260** - This is the ID detection pin and should never be driven as output
2. **VBUS control (PI16/GPIO272)** - Be extremely careful with this pin as it controls 5V power
3. **Never enable VBUS without a proper OTG cable connected** - Could damage the device
4. **Test incrementally** - Start with read-only diagnostics before any configuration changes

## Current System Status (Known Information)

### ✅ Working Components:
- Device tree has `dr_mode = "otg"` configured
- VBUS regulator `usb0-vbus` exists and is detected
- GPIO pins are properly defined in device tree
- USB controllers are present: musb-hdrc, ohci-platform, ehci-platform

### ❌ Issues Identified:
- No USB device detection when plugging in peripherals
- USB role switching may not be functional
- VBUS regulator may not be properly controlled

## Investigation Methods for Embedded Claude

### Method 1: System Package Solutions (PRIORITY 1)

**Goal**: Find existing Debian/Ubuntu packages that can manage USB OTG without custom code.

**Investigation Steps**:
```bash
# Search for USB OTG management packages
apt list --installed | grep -i usb
apt search "usb otg"
apt search "usb role"
apt search "usb switch" 
apt search "usb gadget"

# Check for USB management daemons
systemctl list-units | grep -i usb
dpkg -l | grep -i usb | grep -E "(daemon|service|manager)"

# Look for USB utilities
apt search "usb-modeswitch"
apt search "usbutils"
apt search "libusb"
```

**Packages to Research**:
- `usb-modeswitch` - USB device mode switching
- `usbutils` - USB utilities and debugging tools
- `libusbg` - USB gadget library
- `gadgetfs-utils` - USB gadget filesystem utilities
- `udev` rules and helpers

### Method 2: Kernel Module Investigation (PRIORITY 2)

**Goal**: Determine if required kernel modules are loaded and functional.

**Investigation Script** (create as `check_usb_modules.sh`):
```bash
#!/bin/bash
echo "=== USB OTG Module Investigation ==="

echo "--- Currently loaded USB modules ---"
lsmod | grep -E "(musb|otg|usb|gadget)"

echo "--- Available USB modules ---"
find /lib/modules/$(uname -r) -name "*usb*" -o -name "*otg*" -o -name "*musb*" | head -20

echo "--- USB module parameters ---"
ls /sys/module/musb_hdrc/parameters/ 2>/dev/null || echo "musb_hdrc module not loaded"

echo "--- USB subsystem kernel messages ---"
dmesg | grep -i -E "(usb|otg|musb)" | tail -20

echo "--- Check if USB role switch framework exists ---"
ls -la /sys/class/usb_role/ 2>/dev/null || echo "No USB role switch support"

echo "--- USB configuration in /proc ---"
cat /proc/bus/usb/devices 2>/dev/null | head -10 || echo "No USB device info in /proc"
```

### Method 3: Hardware State Diagnostics (PRIORITY 3)

**Goal**: Understand current USB hardware state without making changes.

**Investigation Script** (create as `usb_hardware_diagnostics.sh`):
```bash
#!/bin/bash
echo "=== USB Hardware Diagnostics ==="

echo "--- USB Controllers Status ---"
lsusb -t

echo "--- USB Devices Currently Detected ---"
lsusb

echo "--- USB PHY Status ---"
find /sys/devices -name "*phy*" -path "*/usb*" | head -10
ls -la /sys/bus/platform/drivers/sun4i-usb-phy/ 2>/dev/null || echo "USB PHY driver not found"

echo "--- USB OTG Controller Status ---"
ls -la /sys/devices/platform/soc/*usb*/ 2>/dev/null | head -10

echo "--- Check USB regulator status ---"
echo "VBUS regulator status:"
find /sys/class/regulator -name "name" -exec grep -l "usb" {} \; 2>/dev/null | xargs -I {} sh -c 'echo "{}:" && cat {}'

echo "--- USB power state ---"
find /sys -path "*/usb*/power/control" 2>/dev/null | head -5 | xargs -I {} sh -c 'echo "{}: $(cat {})"'

echo "--- Current USB role (if available) ---"
find /sys/class/usb_role -name "role" 2>/dev/null | xargs -I {} sh -c 'echo "{}: $(cat {})"'
```

### Method 4: GPIO State Analysis (PRIORITY 4)

**Goal**: Check GPIO states for USB OTG control pins - READ ONLY to avoid damage.

**Investigation Script** (create as `gpio_usb_diagnostics.sh`):
```bash
#!/bin/bash
echo "=== GPIO USB OTG Diagnostics (READ ONLY) ==="

echo "--- GPIO Chip Information ---"
ls -la /sys/class/gpio/
cat /sys/kernel/debug/gpio 2>/dev/null | grep -A5 -B5 -E "(260|272|usb|id|vbus)" || echo "GPIO debug info not accessible"

echo "--- Check if USB ID/VBUS GPIOs are exported ---"
ls -la /sys/class/gpio/ | grep -E "(gpio260|gpio272)"

echo "--- USB ID Pin State (PI4/GPIO260) - SAFE READ ONLY ---"
if [ -d "/sys/class/gpio/gpio260" ]; then
    echo "GPIO260 direction: $(cat /sys/class/gpio/gpio260/direction 2>/dev/null)"
    echo "GPIO260 value: $(cat /sys/class/gpio/gpio260/value 2>/dev/null)"
else
    echo "GPIO260 not exported - this is normal"
fi

echo "--- VBUS Control Pin State (PI16/GPIO272) - SAFE READ ONLY ---"
if [ -d "/sys/class/gpio/gpio272" ]; then
    echo "GPIO272 direction: $(cat /sys/class/gpio/gpio272/direction 2>/dev/null)"
    echo "GPIO272 value: $(cat /sys/class/gpio/gpio272/value 2>/dev/null)"
else
    echo "GPIO272 not exported - this is normal"
fi

echo "--- Device Tree GPIO Configuration ---"
find /proc/device-tree -name "*gpio*" -path "*usb*" 2>/dev/null | head -5
```

### Method 5: USB Gadget Framework Investigation (PRIORITY 5)

**Goal**: Check if the USB gadget framework is available and how it might conflict with host mode.

**Investigation Script** (create as `usb_gadget_diagnostics.sh`):
```bash
#!/bin/bash
echo "=== USB Gadget Framework Diagnostics ==="

echo "--- USB Gadget Controllers ---"
ls -la /sys/class/udc/ 2>/dev/null || echo "No USB gadget controllers found"

echo "--- ConfigFS USB Gadget Support ---"
ls -la /sys/kernel/config/usb_gadget/ 2>/dev/null || echo "ConfigFS USB gadget not available"

echo "--- Legacy USB Gadget Support ---"
ls -la /dev/gadget* 2>/dev/null || echo "No legacy gadget devices"

echo "--- Check for conflicting gadget configuration ---"
find /etc -name "*gadget*" 2>/dev/null
systemctl list-units | grep -i gadget

echo "--- USB Gadget Kernel Config ---"
zcat /proc/config.gz 2>/dev/null | grep -E "CONFIG_USB.*GADGET" | head -10 || echo "Kernel config not available"
```

## Solution Categories to Explore

### Category 1: Package-Based Solutions (Preferred)

**Goal**: Use existing Debian/Ubuntu packages to solve USB OTG management.

**Research Areas**:
1. **usb-modeswitch**: May handle OTG role switching
2. **udev rules**: Custom rules for USB connector detection
3. **systemd services**: Existing USB management services
4. **libusb tools**: User-space USB device management

**Questions to Answer**:
- Can `usb-modeswitch` handle OTG role switching for this hardware?
- Are there existing udev rules for Allwinner H700 USB OTG?
- Does systemd provide any USB OTG management services?

### Category 2: Kernel Configuration Solutions

**Goal**: Enable proper kernel support without modifying driver source code.

**Investigation Areas**:
1. **Missing kernel modules**: Are all required modules loaded?
2. **Module parameters**: Can module parameters fix the issue?
3. **Kernel command line**: Can boot parameters enable proper OTG function?
4. **Kernel config options**: Are the right CONFIG_* options enabled?

**Specific Items to Check**:
```bash
# Required kernel configs
CONFIG_USB_OTG=y
CONFIG_USB_MUSB_DUAL_ROLE=y  
CONFIG_USB_ROLE_SWITCH=y
CONFIG_EXTCON=y
CONFIG_EXTCON_USB_GPIO=y

# Module parameters that might help
modprobe musb_hdrc mode=host
modprobe musb_hdrc mode=otg
```

### Category 3: Device Tree Enhancement Solutions

**Goal**: Fix USB OTG issues through device tree improvements without driver changes.

**Investigation Areas**:
1. **Missing device tree properties**: Are all required properties present?
2. **Incorrect compatible strings**: Do the compatible strings match available drivers?
3. **GPIO configuration**: Are the GPIO pins properly configured?
4. **Regulator configuration**: Is the VBUS regulator properly configured?

**Specific Device Tree Checks**:
- Verify `extcon` node for USB connector detection
- Check `usb-connector` node configuration
- Validate `usb_otg` node completeness

### Category 4: Userspace Service Solutions (Fallback)

**Goal**: Create userspace service to manage USB OTG if hardware automation doesn't work.

**Service Requirements**:
- Monitor USB connector state
- Switch USB roles via sysfs
- Control VBUS regulator safely
- Handle hot-plug detection
- Integrate with systemd

**Package This As**:
- systemd service file
- Shell script or Python daemon
- udev rules for automation
- Configuration files for customization

## Testing Protocol - SAFETY FIRST ⚠️

### Phase 1: Read-Only Diagnostics (SAFE)
1. Run all diagnostic scripts above
2. Document current system state
3. Identify what's missing or misconfigured
4. Check for package solutions

### Phase 2: Non-Destructive Testing (GENERALLY SAFE)
1. Module parameter testing
2. Kernel command line parameter testing  
3. Service/daemon configuration testing
4. Package installation testing

### Phase 3: GPIO Testing (REQUIRES EXTREME CAUTION)
⚠️ **WARNING: Only proceed if explicitly approved by user**
1. Export GPIO pins for read-only access
2. Monitor ID pin state (read-only)
3. Check VBUS regulator state (read-only)
4. **NEVER drive ID pin as output**
5. **NEVER enable VBUS without proper OTG cable**

### Phase 4: Active Configuration (HIGH RISK)
⚠️ **WARNING: Only proceed with user supervision**
1. VBUS regulator control testing
2. USB role switching testing
3. Device tree overlay testing
4. Custom service deployment

## Expected Deliverables

### 1. Diagnostic Report
- Complete system state analysis
- Identification of missing components
- Package availability assessment
- Hardware safety assessment

### 2. Solution Recommendation
- Preferred approach (package-based > kernel config > userspace service)
- Implementation complexity assessment
- Risk assessment for each approach
- Integration method for Armbian build

### 3. Implementation Plan
- Step-by-step implementation instructions
- Required files for Armbian integration
- Testing procedures
- Rollback procedures

## Integration Requirements for Armbian Build

All solutions must be implementable as:
- **BSP package components** (files in `packages/bsp/anbernic/`)
- **Systemd service files** (can be installed during build)
- **Configuration files** (can be pre-installed)
- **Package dependencies** (can be added to `PACKAGE_LIST_BOARD`)

**Do NOT recommend solutions that require**:
- Manual post-installation configuration
- User interaction after flashing
- Runtime compilation or building
- Kernel source code modifications

## Questions for Embedded Claude to Answer

1. **What existing Debian/Ubuntu packages can manage USB OTG role switching?**
2. **Are all required kernel modules loaded and properly configured?**
3. **Is the USB role switch framework functional in the current kernel?**
4. **Can the issue be resolved through kernel module parameters or boot options?**
5. **What is the current state of the USB hardware and regulators?**
6. **Are there any conflicting USB gadget configurations?**
7. **What is the safest approach that can be integrated into the Armbian build?**

## Success Criteria

The solution is successful when:
- USB keyboards/mice are detected when plugged into OTG connector
- USB storage devices are recognized and mountable
- No hardware damage occurs during testing
- Solution can be reliably built into Armbian images
- No manual post-installation configuration required
- Works across reboots and power cycles

## Emergency Procedures

If any testing causes system instability:
1. **Immediately reboot the device**
2. **Do not attempt further GPIO manipulation**
3. **Document exactly what was done before the issue**
4. **Report hardware symptoms (heat, unusual behavior, etc.)**
5. **Wait for user guidance before proceeding**

**Remember**: Hardware preservation is more important than solving the USB OTG issue. When in doubt, stop and ask for guidance.