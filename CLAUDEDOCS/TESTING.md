# RG34XXSP Armbian Build Testing Instructions

## Testing Protocol Overview

This document provides specific testing instructions for validating RG34XXSP Armbian builds. Each phase of development requires user testing on actual hardware before proceeding to the next phase.

**IMPORTANT**: This file should only exist during active testing phases. After completing tests, results are incorporated into PLAN.md and this file is removed.

## Current Testing Phase: Phase 1 - Foundation and Basic Boot (HYBRID BOOTLOADER BUILD)

### Prerequisites

#### Hardware Requirements
- **RG34XXSP Device**: Physical hardware for testing
- **Serial Console Access**: UART cable for debugging (optional but recommended)
- **Test SD Card**: High-speed microSD card (Class 10 or better, 8GB minimum)
- **SD Card Reader**: For flashing images to SD card
- **Computer**: For flashing images and monitoring serial console

#### Software Requirements
- **SD Card Flashing Tool**: USBImager, Balena Etcher, or dd command
- **Serial Console Software**: minicom, screen, or PuTTY (if using serial console)
- **Build Output**: Armbian Bookworm ALPHA image with ROCKNIX bootloader (hybrid approach)

### BREAKTHROUGH: Hybrid Bootloader Approach

**NEW SOLUTION**: Hybrid image combines proven ROCKNIX bootloader with Armbian Bookworm rootfs. This bypasses U-Boot compilation issues by using extracted working bootloader from ROCKNIX while maintaining full Armbian userspace.

### Phase 1 Testing Procedures (HYBRID BOOTLOADER BUILD)

#### Test 1.1: Image Flashing
**Objective**: Verify the hybrid image can be flashed to SD card successfully

**RESOLVED ISSUE**: Previous hybrid image had device tree mismatch causing boot failure

**HYBRID ARMBIAN Test Image**: `/home/ai/otherprojects/RG34XXSP-Armbian-Port/builds/Armbian-HYBRID-ROCKNIX-BOOT-20250718-1534.img.gz`
**Image Size**: 1.9G (compressed, hybrid system)
**Base**: ROCKNIX bootloader + DTB configuration + Armbian Bookworm rootfs
**Build Type**: ARMBIAN HYBRID TEST - Working Armbian system with proven ROCKNIX bootloader

**Hybrid Approach**: Combines proven ROCKNIX boot partition (SPL + U-Boot + DTB) with complete Armbian Bookworm minimal rootfs for full Debian environment

**Steps**:
1. Insert SD card into computer
2. Extract compressed image: `gunzip Armbian-HYBRID-ROCKNIX-BOOT-20250718-1534.img.gz`
3. Flash the extracted .img file to SD card using your preferred tool
4. Verify flashing completed without errors
5. Safely eject SD card

**Expected Result**: Image flashes successfully without errors

**Result**: [ ] PASS / [ ] FAIL
**Notes**: _User to fill in any issues encountered_

---

#### Test 1.2: Initial Boot
**Objective**: Verify system boots to login prompt

**Steps**:
1. Insert flashed SD card into RG34XXSP
2. Power on the device
3. Wait for boot process to complete (up to 2 minutes)
4. Observe for login prompt on display

**Expected Result**: System boots and displays login prompt

**Expected Outcome**: System should show basic boot activity (power LED, initial boot sequence)

**Previous Result**: [X] FAIL - Red power light only, no boot progression (SPL missing)
**Previous 64MB Copy**: [X] FAIL - Missing boot partition content
**ROCKNIX Validation**: [X] PASS ✅ - Confirmed working bootloader and DTB
**HYBRID ARMBIAN Result**: [ ] PASS / [ ] FAIL
**Notes**: _This hybrid should boot to Armbian login prompt using proven ROCKNIX bootloader foundation. Expected: Red → Green → Display → Armbian Bookworm login_

---

#### Test 1.3: Serial Console Access (Optional)
**Objective**: Verify serial console provides access to system

**Steps**:
1. Connect UART cable to RG34XXSP serial pins
2. Open serial console software (115200 baud, 8N1)
3. Power on device and monitor boot process
4. Verify login prompt appears in serial console

**Expected Result**: Serial console shows boot messages and login prompt

**Result**: [ ] PASS / [ ] FAIL / [ ] SKIPPED
**Notes**: _User to fill in any issues or skip if no serial access_

---

#### Test 1.4: Basic System Functionality
**Objective**: Verify basic Linux functionality works

**Steps**:
1. Login to system using default credentials
2. Run basic commands: `ls`, `ps`, `free`, `df -h`
3. Check system information: `uname -a`, `cat /etc/os-release`
4. Verify no critical errors in: `dmesg | tail -20`

**Expected Result**: All basic commands work, system information correct

**Result**: [ ] PASS / [ ] FAIL
**Notes**: _User to fill in any command failures or errors_

---

#### Test 1.5: Storage Access
**Objective**: Verify SD card storage is accessible

**Steps**:
1. Check available storage: `df -h`
2. Create test file: `echo "test" > /tmp/test.txt`
3. Verify file creation: `cat /tmp/test.txt`
4. Check available memory: `free -h`

**Expected Result**: Storage accessible, file operations work

**Result**: [ ] PASS / [ ] FAIL
**Notes**: _User to fill in storage capacity and any issues_

---

## Phase 1 Test Results Summary

### Overall Phase 1 Results  
- [ ] ALL TESTS PASSED - Ready to proceed to Phase 2
- [ ] SOME TESTS FAILED - Requires fixes before Phase 2

### Previous Failed Approach (RESOLVED)
**Fixed Issue**: Complete boot failure with incorrect U-Boot device tree configuration

The previous Noble build failed due to using `sun50i-h700-anbernic-rg34xx-sp` device tree in U-Boot, which doesn't exist. Fixed by using `sun50i-h616-orangepi-zero2` device tree for U-Boot (which works with H700 hardware) while maintaining H700 kernel device tree support.

### Additional Observations
_User to note any additional observations, performance issues, or unexpected behavior:_

---

## Hardware Information Collection

### Device Information
**RG34XXSP Model**: _User to fill in specific model/revision if known_
**Serial Number**: _User to fill in if accessible_
**Hardware Revision**: _User to fill in if known_

### Performance Metrics
**Boot Time**: _User to record time from power on to login prompt_
**Memory Usage**: _User to record from `free -h` command_
**Storage Usage**: _User to record from `df -h` command_

### Error Logs
_User to paste any error messages from dmesg or system logs:_

```
[User to paste error logs here if any]
```

---

## Next Steps

### If All Tests Pass
1. **User Action**: Mark "ALL TESTS PASSED" in summary above
2. **Claude Action**: Proceed to Phase 2 implementation
3. **File Action**: Remove this TESTING.md file and update PLAN.md with results

### If Tests Fail
1. **User Action**: Document all failures in "Failed Tests" section
2. **Claude Action**: Analyze failures and update PLAN.md with fixes
3. **File Action**: Update this TESTING.md with new test procedures for retesting

### Additional Testing
If user discovers additional issues not covered by these tests, please document them in the "Additional Observations" section.

---

## Contact and Support

If testing reveals issues that require clarification or additional support:
1. Document the issue thoroughly in the test results
2. Include relevant log outputs and error messages
3. Note any workarounds or partial solutions discovered

This information helps improve the implementation and ensures robust hardware support.

---

**Testing Date**: _User to fill in date of testing_
**Tester**: _User to fill in name/identifier_
**Build Version**: Armbian-ALPHA-RG34XXSP-bookworm-ROCKNIX-bootloader-20250718-1050 (Hybrid: ROCKNIX bootloader + Armbian Bookworm rootfs)

## Important Notes

- **Complete all applicable tests**: Do not skip tests unless hardware/software not available
- **Document everything**: Even minor issues should be noted
- **Be thorough**: Take time to verify each test completely
- **Report accurately**: Honest test results help improve the final product

This testing is crucial for ensuring the RG34XXSP Armbian build works correctly on actual hardware. Thank you for your thorough testing!