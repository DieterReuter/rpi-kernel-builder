[![Build Status](https://builder.hypriot.com/api/badge/github.com/hypriot/rpi-kernel-builder/status.svg?branch=master)](https://builder.hypriot.com/github.com/hypriot/rpi-kernel-builder)
# rpi-kernel-builder

Build a Raspberry Pi 1 and 2 kernel with all kernel modules running docker.

## Build inputs

### Kernel configs

In the local directory `kernel_configs/` are two configuration files for Pi 1 nad Pi 2.

* `rpi1_docker_kernel_config`
* `rpi2_docker_kernel_config`

These configuration files are created from an initial `make menuconfig` and activating all kernel modules we need to run docker on the Raspberry Pi.

## Build outputs

### Kernel deb packages

The five kernel deb packages are uploaded to S3 bucket `s3://buildserver-production/kernel/<date-time>/`.

* `libraspberrypi-bin_<date-time>_armhf.deb`
* `libraspberrypi-dev_<date-time>_armhf.deb`
* `libraspberrypi-doc_<date-time>_armhf.deb`
* `libraspberrypi0_<date-time>_armhf.deb`
* `raspberrypi-bootloader_<date-time>_armhf.deb`
* `kernel-commit.txt`
* `kernel-qemu.img`
* `linux-firmware-image-3.18.9+_3.18.9+-5_armel.deb`
* `linux-firmware-image-3.18.9-v7+_3.18.9-v7+-6_armel.deb`
* `linux-headers-3.18.9+_3.18.9+-5_armel.deb`
* `linux-headers-3.18.9-v7+_3.18.9-v7+-6_armel.deb`
* `linux-image-3.18.9+_3.18.9+-5_armel.deb`
* `linux-image-3.18.9-v7+_3.18.9-v7+-6_armel.deb`
* `linux-libc-dev_3.18.9+-5_armel.deb`
* `linux-libc-dev_3.18.9-v7+-6_armel.deb`

## Build with Vagrant

To build the SD card image locally with Vagrant and VirtualBox, enter

```bash
vagrant up
```

### Recompile kernel

Only on first boot the kernel will be compiled automatically.
If you want to compile again, use these steps:

```bash
vagrant up
vagrant ssh
sudo su
/vagrant/scripts/compile_kernel.sh
```

### Update kernel configs

To update the two kernel config files you can use this steps.

```bash
vagrant up
vagrant ssh
sudo su
MENUCONFIG=1 /vagrant/scripts/compile_kernel.sh
```

This will only call the `make menuconfig` inside the toolchain and copies the updated kernel configs back to `kernel_configs/` folder to be committed to the GitHub repo.

### Build only one kernel

To build only one of the three kernels you can use these steps.

```bash
vagrant up
vagrant ssh
sudo su
ONLY_BUILD=qemu /vagrant/scripts/compile_kernel.sh
```

For the variable `ONLY_BUILD` the values `rpi1`, `rpi2` and `qemu` are supported.

You also can combine this with `MENUCONFIG=1` to run `make menuconfig` only for this kernel.

### Build qemu kernel config

```bash
ONLY_BUILD=qemu MENUCONFIG=1 VERSATILE=1 /vagrant/scripts/compile_kernel.sh
```

## Build with Drone

Add this GitHub repo to the Drone CI server. Then customize the project settings as follows.

### Private Variables

The following variables have to be defined in the GUI of the Drone CI build server.
For uploading the build results to Amazon S3 we need the following Amazon S3 credentials

* `AWS_ACCESS_KEY_ID: your_aws_key`
* `AWS_SECRET_ACCESS_KEY: your_secret_access_key`
