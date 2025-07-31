# RG34XXSP Project Instructions

## Project Overview
This project is focused on creating a community Armbian build for RG34XXSP hardware. The RG34XXSP is based on the Allwinner H700 SoC, which is part of the sunxi family. This repository contains reference implementations and build systems for H700-based devices.

## Project Objectives
- Create a community Armbian build for RG34XXSP handheld gaming device
- Leverage existing H700 device support from other projects
- Adapt existing configurations for RG34XXSP specific hardware

## Reference Repositories

### repos_reference/alpine-h700/
**Purpose**: Alpine Linux build system for H700 SoC devices
**Documentation**: `repos_reference/alpine-h700/README.md`
**Build**: `make` (requires stock SD card image as factory.img)
**Key Features**:
- Tested on Anbernic RG35XX Plus (H700-based)
- Extracts SPL, U-Boot, kernel, and firmware from stock image
- Creates minimal Alpine Linux system with WiFi and SSH
- Build requirements: podman, python3, sgdisk, guestfish, fakeroot

### repos_reference/armbian-build/
**Purpose**: Main Armbian build framework
**Documentation**: `repos_reference/armbian-build/README.md`
**Build**: `./compile.sh` (interactive) or with parameters
**Key Features**:
- Comprehensive build system for ARM devices
- Supports kernel, image, and distribution builds
- Uses buildroot-style configuration
- Board configurations in `config/boards/`

### repos_reference/knulli-distribution/
**Purpose**: Gaming-focused distribution based on Batocera
**H700 Support**: 
- Board config: `repos_reference/knulli-distribution/configs/knulli-h700.board`
- Defconfig: `repos_reference/knulli-distribution/configs/knulli-h700_defconfig`
**Key H700 Details**:
- Target: aarch64 Cortex-A53 with NEON
- Kernel: Linux 4.9.170 from orangepi-xunlong repo
- GPU: Mali-G31 with fbdev driver
- Uses Buildroot with custom Knulli packages

### repos_reference/rocknix-distribution/
**Purpose**: Gaming distribution fork of JELOS
**H700 Support**: Extensive support for H700 devices
**Key H700 Files**:
- Device options: `projects/Allwinner/devices/H700/options`
- Device tree patches: `projects/Allwinner/patches/linux/H700/`
- RG34XXSP specific: `0145-Create-sun50i-h700-anbernic-rg34xx.dts`
- RG34XXSP SP variant: `0146-Create-sun50i-h700-anbernic-rg34xx-sp.dts`

### repos_reference/sunxi-dt-overlays/
**Purpose**: Device tree overlays for Allwinner/sunxi devices
**Documentation**: `repos_reference/sunxi-dt-overlays/README.md`
**Compatibility**: Kernel 4.14.x (may need updates for newer kernels)
**Usage**: For hardware customization via device tree overlays

## H700 Device Build Documentation

### Hardware Specifications (H700 SoC)
- **Architecture**: ARM64 (aarch64)
- **CPU**: Cortex-A53 quad-core
- **GPU**: Mali-G31 
- **Kernel**: Linux 4.9.170 (legacy) or newer mainline
- **Bootloader**: U-Boot with ARM Trusted Firmware

### Build Requirements
- x86_64/aarch64 host with 8GB+ RAM, 50GB+ disk
- Ubuntu 22.04+ or Armbian host system
- For Alpine build: podman, python3, sgdisk, guestfish, fakeroot
- For Armbian build: `./compile.sh` handles dependencies

### Build Commands by Repository

#### Alpine H700 Build
```bash
cd repos_reference/alpine-h700/
# Place stock image as factory.img
make
# Output: artifacts/alpine-h700.img
```

#### Armbian Build (General)
```bash
cd repos_reference/armbian-build/
./compile.sh BOARD=<board> BRANCH=current RELEASE=noble
```

#### Knulli Build (H700)
```bash
cd repos_reference/knulli-distribution/
make knulli-h700_defconfig
make
```

### RG34XXSP Specific Notes
- Device tree files exist in ROCKNIX: `sun50i-h700-anbernic-rg34xx.dts` and `sun50i-h700-anbernic-rg34xx-sp.dts`
- Based on H700 SoC with standard Allwinner bootloader chain
- Should leverage existing H700 board support in Armbian
- Need to create board configuration file for Armbian build system

## Development Guidelines
- Follow existing code style in each repository
- Test changes thoroughly before committing
- Document hardware-specific configurations in HARDWARE.md
- Track project progress in PLAN.md

## Repository Structure
- `repos_reference/` - Reference implementations and documentation for H700 devices
  - `alpine-h700/` - Alpine Linux build system for H700 SoC
  - `armbian-build/` - Main Armbian build framework
  - `knulli-distribution/` - Gaming distribution with H700 support
  - `rocknix-distribution/` - Gaming distribution with extensive H700 patches
  - `sunxi-dt-overlays/` - Device tree overlays for Allwinner devices
  - `linux-kernel/` - Linux kernel source tree
  - `muos-core/` - MuOS core build system
  - `muos-internal/` - MuOS internal tools
- `repos_to_update/` - Working directory for repositories to be modified for RG34XXSP support
- `PLAN.md` - Project roadmap and planning
- `HARDWARE.md` - Hardware specifications and documentation
- `TODO.md` - User-defined task list
- `CLAUDE.md` - Project instructions and documentation (this file)

## Ongoing Tasks
- Always keep the HARDWARE.md up to date with what is learned about the objective to compile Armbian for RG34XXSP
- Focus on adapting existing H700 support for RG34XXSP specific hardware differences
- **README.md Maintenance**: For every commit, update README.md phase indicators; update status only for implementation progress (not style changes)
- **Human-Only Submissions**: Never submit pull requests to Armbian team; notify human when submission is ready

## Development Rules

### Rule 1: Documentation Reference for PLAN.md Updates
**MANDATORY**: When updating PLAN.md, Claude must ALWAYS reference and incorporate information from:
1. **ALTERNATIVE_IMPLEMENTATIONS.md** - For understanding existing H700 implementations and their approaches
2. **HARDWARE.md** - For hardware specifications and distribution-specific handling
3. **ARMBIAN_COMMUNITY_BUILD_GUIDE.md** - For Armbian-specific build requirements and community guidelines

This ensures all planning decisions are based on:
- Proven implementations from other distributions
- Complete hardware understanding
- Armbian community standards and best practices

### Rule 2: Documentation Reference for Plan Execution
**MANDATORY**: When executing the plan, Claude must ALWAYS reference and consult:
1. **ALTERNATIVE_IMPLEMENTATIONS.md** - For implementation patterns and proven solutions
2. **HARDWARE.md** - For hardware-specific requirements and constraints

This ensures all implementation decisions are informed by existing successful approaches and hardware realities.

### Rule 3: Testing Confirmation Requirement
**MANDATORY**: Claude must NOT proceed to the next phase of implementation without explicit user confirmation that tests have passed. The process is:

1. **Test Creation**: Claude creates TESTING.md with specific test procedures for the current phase
2. **User Testing**: User performs tests on actual hardware following TESTING.md instructions
3. **Results Documentation**: User updates TESTING.md with test results and marks PASS/FAIL
4. **Confirmation Required**: Claude can only proceed when user confirms "ALL TESTS PASSED" in TESTING.md
5. **Issue Resolution**: If tests fail, Claude must fix issues and provide updated TESTING.md for retest

**No exceptions**: Implementation phases cannot proceed without successful user testing confirmation on actual hardware.

### Rule 4: TESTING.md Lifecycle Management
**MANDATORY**: The TESTING.md file must follow strict lifecycle management:

1. **Creation**: Only created when active testing is required for a specific phase
2. **Active Use**: Contains specific test procedures and user result documentation
3. **Completion**: After successful testing, results are incorporated into PLAN.md
4. **Cleanup**: TESTING.md is removed between testing phases to avoid confusion
5. **Regeneration**: New TESTING.md created for each new phase requiring testing

**Purpose**: Ensures testing documentation is current, relevant, and not cluttered with obsolete information.

### Rule 5: README.md Status Maintenance
**MANDATORY**: Before every git commit, Claude must update README.md with:

1. **Phase Indicators**: Update phase status using proper emojis:
   - ✅ = Complete phases
   - ▶️ = Current active phase (with ✨*In Progress*✨ suffix)
   - 🔜 = Future pending phases

2. **Status Summary**: Replace the "Status:" field with exactly one sentence describing progress along the implementation plan (not minor style/documentation changes)

3. **Timing**: This update must happen before the git commit, ensuring the public GitHub page always reflects current development status

**Purpose**: Maintains up-to-date public visibility of project progress and current development state.

### Rule 6: Human-Only Armbian Submission
**MANDATORY**: All submissions to the Armbian team must be performed by a human, never by Claude.

1. **Claude Responsibility**: Prepare all code, documentation, and branch structure for submission
2. **Human Handoff**: When submission is ready, Claude must notify the human via console message
3. **Notification Format**: "🚨 HUMAN ACTION REQUIRED: Armbian submission ready. Please review and submit pull request manually."
4. **No Automation**: Claude must never attempt to create pull requests, contact maintainers, or submit code upstream
5. **Support Role**: Claude can assist with submission preparation but cannot execute the submission

**Purpose**: Ensures human oversight and responsibility for all upstream contributions to the Armbian project.

### Rule 7: Shell Command Error Learning
**MANDATORY**: When making shell command errors that could be prevented by better understanding or documentation, Claude must consider adding preventive guidance to CLAUDE.md.

1. **Error Analysis**: After encountering unexpected shell command failures, analyze if the error could have been prevented with better project-specific knowledge
2. **Pattern Recognition**: Identify if the error represents a class of mistakes likely to recur in this project context
3. **Documentation Update**: If the error reflects missing project knowledge or common pitfalls, add a preventive rule or reminder to this CLAUDE.md file
4. **Learning Integration**: Ensure future work benefits from lessons learned through systematic documentation

**Purpose**: Creates a self-improving documentation system that reduces repeat errors and builds project-specific shell command expertise.

### Rule 7a: Token-Optimized Build Command Exception
**MANDATORY**: Claude is authorized to execute the specific token-optimized Armbian build command pattern.

**Approved Command Pattern**:
```bash
./compile.sh build BOARD=rg34xxsp BRANCH=current RELEASE=bookworm BUILD_MINIMAL=yes BUILD_DESKTOP=no KERNEL_CONFIGURE=no 2>&1 | tee build_log.txt | tail -20
```

**Rationale**: This command pattern is token-efficient because:
1. `tee build_log.txt` saves complete logs locally without token cost
2. `tail -20` limits AI monitoring to essential final output only  
3. Enables AI build execution while preserving quota for complex debugging
4. Maintains full debugging capability through local build_log.txt file

**Scope**: This exception applies only to Armbian build commands using this specific token-optimization pattern.

### Rule 8: Host System Modification Approval
**MANDATORY**: Claude must always check with the user before making any changes to the host system configuration.

1. **Identification**: When encountering build issues that require host system changes (package installation, service configuration, system settings)
2. **User Consultation**: Present the issue and proposed solution to the user for approval before proceeding
3. **Alternatives**: Always provide both host system changes and containerized alternatives when possible
4. **Documentation**: Update PLAN.md with the user-approved solution for future reference

**Purpose**: Ensures user maintains control over their development environment and system configuration.

### Rule 9: Compression Validation and Timeout
**MANDATORY**: Claude must always validate compressed files before recommending them for testing.

1. **Compression Timeout**: Allow up to 10 minutes for compression/decompression operations
2. **Integrity Testing**: Always test compressed files using appropriate tools (e.g., `gzip -t`, `xz -t`, `7z t`) before marking them ready for testing
3. **Decompression Testing**: Always perform a full decompression test to verify the compressed file can be properly extracted
4. **Corruption Prevention**: If compression is interrupted or fails, remove corrupted files and retry with appropriate timeouts
5. **File Format**: Use gzip compression for broad compatibility with image flashing tools (Balena Etcher, Raspberry Pi Imager)
6. **Documentation**: Update TESTING.md with correct file names and formats after validation

**Purpose**: Prevents user frustration from corrupt compressed files and ensures reliable testing procedures.

### Rule 10: Local Build Storage with ALPHA Marking
**MANDATORY**: Claude must store builds locally in builds/ directory and mark all builds as ALPHA.

1. **Local Storage**: Store build files in builds/ directory (gitignored to avoid repository bloat)
2. **ALPHA Marking**: All builds must be clearly marked as ALPHA in filename and documentation
3. **File Format**: Use gzip compression for compatibility with image flashing tools
4. **Build Validation**: Test compression integrity before saving builds
5. **No Removal**: Never remove existing builds from builds/ directory - preserve all versions
6. **TESTING.md Updates**: Update TESTING.md with local file paths for testing
7. **Documentation**: Clearly mark builds as ALPHA quality in all documentation

**Purpose**: Provides local build storage while avoiding repository size issues and preserving build history.

### Rule 11: HARDWARE.md Content Guidelines
**MANDATORY**: HARDWARE.md must contain only technical specifications relevant to Armbian development.

1. **Include**: GPIO mappings, device tree requirements, driver specifications, bootloader configuration, kernel requirements
2. **Exclude**: General performance specs, gaming benchmarks, consumer review information, marketing specifications
3. **Focus**: Technical implementation details needed for device tree creation, driver selection, and hardware enablement
4. **Source Attribution**: Every technical specification must reference where the information was obtained (repository file, documentation URL, hardware testing, etc.)
5. **Purpose**: Provide developers with actionable technical information for Armbian board support implementation

### Rule 12: Post-PR Phase Management
**MANDATORY**: Post-PR phases must be implemented separately from Armbian upstream work.

1. **Separate Directory**: Post-PR phases must be implemented in a separate folder from "repos_to_update" 
2. **Repository Management**: Post-PR features maintained in this repository, not in Armbian upstream
3. **User Installation**: Post-PR features should be implementable by users after Armbian base install when possible
4. **Clear Separation**: No mixing of upstream-compliant and post-PR code in the same directory structure
5. **Documentation**: Post-PR phases clearly marked as community extensions, not official Armbian features

### Rule 13: Plan Step Responsibility Assignment
**MANDATORY**: Every step in PLAN.md must clearly specify whether it is performed by Human or Claude.

1. **Format**: Each step must include "[Human]" or "[Claude]" prefix to indicate responsibility
2. **Clarity**: No ambiguity about who performs each action
3. **Accountability**: Clear ownership for every task and deliverable
4. **Collaboration**: Shared tasks must specify both "[Human+Claude]" with role descriptions
5. **Purpose**: Ensures proper workflow and prevents confusion about responsibilities

### Rule 14: Phase Approval Requirement
**MANDATORY**: Claude must obtain human approval before beginning any new phase of implementation.

1. **Phase Summary**: Present a clear summary of planned phase activities and goals
2. **Human Confirmation**: Wait for explicit human approval before proceeding with phase execution
3. **Scope Validation**: Ensure human agrees with planned approach and timeline
4. **Risk Assessment**: Highlight any potential issues or dependencies for human review
5. **Purpose**: Ensures human oversight and agreement on project direction before significant work begins

### Rule 15: Local Build Testing Requirements
**MANDATORY**: Claude must clearly mark all builds as ALPHA quality for local testing.

1. **ALPHA Labeling**: All build files must include "ALPHA" in the filename
2. **Local Testing**: All testing uses local builds/ directory files
3. **Documentation**: TESTING.md must clearly state builds are ALPHA quality and local-only
4. **Validation Sequence**: Must complete compression integrity test before recommending testing
5. **Build Preservation**: Never remove or overwrite existing builds - maintain version history
6. **Warning Labels**: All documentation must warn that builds are experimental/alpha quality
7. **External Distribution**: For sharing builds, use external hosting or manual transfer

**Purpose**: Ensures proper expectations about build stability while enabling local testing and build preservation.

### Rule 16: Kernel Configuration Method
**MANDATORY**: Claude must never use KERNEL_EXTRA_CONFIG as it does not work in Armbian builds.

1. **KERNEL_EXTRA_CONFIG Prohibition**: Never add KERNEL_EXTRA_CONFIG to board .csc files - this method is non-functional
2. **Manual Kernel Config**: For kernel configuration changes, always request human to manually update kernel config using proper kernel-config tools
3. **BSP Package Method**: For firmware and file installation, use post_family_tweaks_bsp__[boardname]_[function] in board .csc files
4. **Config Change Requests**: Clearly specify exact CONFIG_* options that need to be enabled/disabled
5. **BSP Function Format**: Use proper Armbian BSP function syntax with destination variable and source paths

**Examples**:
```bash
# WRONG - Does not work
KERNEL_EXTRA_CONFIG="CONFIG_DRM_FBDEV_EMULATION=y"

# CORRECT - Request manual change
"Please add CONFIG_DRM_FBDEV_EMULATION=y to kernel config using kernel-config method"

# CORRECT - BSP package function
function post_family_tweaks_bsp__rg34xxsp_firmware() {
    display_alert "$BOARD" "Installing panel firmware" "info"
    mkdir -p "${destination}"/lib/firmware/
    cp -fr $SRC/packages/bsp/rg34xxsp/lib/firmware/* "${destination}"/lib/firmware/
}
```

**Purpose**: Ensures proper Armbian build system usage and prevents non-functional configuration attempts.

### Rule 12: Strict Armbian Community Standards Compliance
**MANDATORY**: Claude must strictly follow Armbian's community board standards for all implementation decisions.

1. **Board Configuration**: Use `.csc` extension and modern `declare -g` syntax for community boards
2. **Naming Conventions**: Follow exact Armbian patterns for files, variables, and configurations
3. **Hardware Mapping**: Use correct board families, overlay prefixes, and device tree references
4. **Package Lists**: Include appropriate packages following established device category patterns
5. **BSP Structure**: Implement Board Support Package functions matching Armbian conventions
6. **Documentation**: Follow Armbian's community contribution guidelines and formatting
7. **Upstream Readiness**: Ensure all code changes are ready for Armbian upstream submission

**Purpose**: Maintains compatibility with Armbian ecosystem and ensures successful upstream integration.