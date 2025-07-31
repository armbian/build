# RG34XXSP Armbian Community Build

## What is this Project?

This project aims to create a complete Armbian community build for the RG34XXSP device, transforming it into a full-featured ARM64 Linux computer. Unlike gaming-focused distributions, this follows Armbian's mission to provide standard desktop and server computing capabilities on ARM hardware.

🛠️ **Development Branch**: All Armbian code changes are being made on the [`rg34xxsp-support`](https://github.com/armbian/build/compare/main...mitswan:build:rg34xxsp-support) branch for eventual upstream submission.

⚠️ **This is NOT a gaming distribution** - This project focuses on general-purpose computing following Armbian's mission.

## Development Status

**Status:** Phase 2.2 - Reproducible build process created with working hybrid system fully documented and automated.

- ✅ **Phase 0**: Discovery and comprehensive hardware research
- ✅ **Phase 1**: DTB discovery and boot validation - Working hybrid system achieved
- ✅ **Phase 2.1**: Working system analysis and documentation completed
- ✅ **Phase 2.2**: Reproducible build process creation
- ▶️ **Phase 2.3**: File replacement strategy (Armbian build integration) ✨*In Progress - Debugging Boot Issues*✨
- 🔜 **Phase 3**: Enhanced system features (network, SSH, display)
- 🔜 **Phase 4**: Armbian build system integration (step-by-step migration)

## Available Builds

📦 **Builds Directory**: [`builds/`](builds/)

*Currently no builds available. Builds will appear here as development progresses through each phase.*

## Documentation

### 📋 Project Planning
Key documents used by Claude to Plan and track progress.
- **[PLAN.md](PLAN.md)** - Describes the plan Claude is working on and which steps have been completed. 
- **[TESTING.md](TESTING.md)** - Hardware testing procedures and validation steps.

### Prior Research
- **[HARDWARE.md](HARDWARE.md)** - Knowledge Claude has researched about the device hardware to prepare the plan.
- **[ALTERNATIVE_IMPLEMENTATIONS.md](ALTERNATIVE_IMPLEMENTATIONS.md)** - Research into other linux distributions that support H700 devices that could be useful in porting Armbian.
- **[ARMBIAN_COMMUNITY_BUILD_GUIDE.md](ARMBIAN_COMMUNITY_BUILD_GUIDE.md)** - Summary of what Claude knows about the official Armbian guidelines for sumbitting community builds.

