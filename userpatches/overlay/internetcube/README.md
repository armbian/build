## How to Build

This README describes how we currently build the Internet Cube images.

Since January 2019, we do not build the InternetCube images anymore. We simply use [YunoHost images](https://yunohost.org/#/images) to which we add InternetCube specific scripts for automatic configuration.

The images are currently based on Armbian Stretch.

For previous build scripts, refer to the git history of this repo.

### Supported Devices

For now, we support only 2 boards: Olimex LIME and Olimex LIME2.

Encrypted images are not supported at the moment.

### Configure a YunoHost Image

```
bash yunocube.sh <yunohostimagefile.img>
```

example:
```
bash yunocube.sh yunohost-stretch-3.4.2-lime2-stable.img
```

This will create named under the same directory as the source images:

```
internetcube-stretch-3.4.2-lime2-stable.img
```

Respecting the format of the filenames is important to ensure the compatibility with *install-sd.sh*.
For generating (optional) GPG signatures, please ask on the *La Brique Internet*'s mailing list.

### Installing the New Images

Now you can follow [tutorials](https://install.labriqueinter.net) to install a new Internet Cube.
