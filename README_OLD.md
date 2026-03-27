## Building
- Clone this repository
- Run `build.sh` to start the build process. This will generate an image in the `output` folder.
- Run `write.sh` to write the generated image to an SD card. Make sure to change the `SD_PATH` variable in the script to the correct device.

## Info
This repository contains a fork of the [original armbian build script](https://github.com/armbian/build).
The fork is modified to:
- Build armbian for RPI4 using the `config-ip-terminal.conf` configuration file in the `userpatches` folder.
    - Uses the `current` branch of the linux LTS kernel which is currently `6.18.x`
    - Base the image on debian trixie
    - Use `network-manager`
    - And more... see the config file for details.
- Customize the image using `customize-image.sh`script in the `userpatches` folder.
    - Use `overlayroot` to make the root filesystem read-only and create an immutable image.
    - Create a user `cisco` with password `cisco`.
    - Use a static IP address
    - Installs various network debugging tools
    - And more... see the script for details.
- Read the [Armbian build framework documentation](https://docs.armbian.com/Developer-Guide_Overview/) for more details.
- The `build.sh` script:
    - Removes the `userpatches/overlay` folder and recreates it before each build.
    - Copies the contents of the `ip-terminal-code` folder to the `userpatches/overlay` folder.
    - Compiles armbian using the `compile.sh` script with the `ip-terminal` configuration.

- Enable I2C in the image by default, this is done by setting "dtparam=i2c_arm=on" in the file "config/sources/families/bcm2711.conf"
