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

The five kernel deb packages are uploaded to S3 bucket `s3://buildserver-production/kernel/`.

* `libraspberrypi-bin_<date-time>_armhf.deb`
* `libraspberrypi-dev_<date-time>_armhf.deb`
* `libraspberrypi-doc_<date-time>_armhf.deb`
* `libraspberrypi0_<date-time>_armhf.deb`
* `raspberrypi-bootloader_<date-time>_armhf.deb`

## Build with Vagrant

To build the SD card image locally with Vagrant and VirtualBox, enter

```bash
vagrant up
```

## Build with Drone

Add this GitHub repo to the Drone CI server. Then customize the project settings as follows.

### Private Variables

The following variables have to be defined in the GUI of the Drone CI build server.
For uploading the build results to Amazon S3 we need the following Amazon S3 credentials

* `AWS_ACCESS_KEY_ID: your_aws_key`
* `AWS_SECRET_ACCESS_KEY: your_secret_access_key`
