#!/bin/bash
set -e
set -x

NUM_CPUS=`nproc`
echo "###############"
echo "### Using ${NUM_CPUS} cores"

# setup some build variables
BUILD_USER=vagrant
BUILD_GROUP=vagrant
BUILD_ROOT=/var/kernel_build
BUILD_CACHE=$BUILD_ROOT/cache
ARM_TOOLS=$BUILD_CACHE/tools
LINUX_KERNEL=$BUILD_CACHE/linux-kernel
LINUX_KERNEL_COMMIT=""
# LINUX_KERNEL_COMMIT=1f58c41a5aba262958c2869263e6fdcaa0aa3c00
RASPBERRY_FIRMWARE=$BUILD_CACHE/rpi_firmware

if [ -d /vagrant ]; then
  # running in vagrant VM
  SRC_DIR=/vagrant
else
  # running in drone build
  SRC_DIR=`pwd`
  BUILD_USER=`whoami`
  BUILD_GROUP=`whoami`
fi

LINUX_KERNEL_CONFIGS=$SRC_DIR/kernel_configs

NEW_VERSION=`date +%Y%m%d-%H%M%S`
BUILD_RESULTS=$BUILD_ROOT/results/kernel-$NEW_VERSION

X64_CROSS_COMPILE_CHAIN=arm-bcm2708/gcc-linaro-arm-linux-gnueabihf-raspbian-x64

declare -A CCPREFIX
CCPREFIX["rpi1"]=$ARM_TOOLS/$X64_CROSS_COMPILE_CHAIN/bin/arm-linux-gnueabihf-
CCPREFIX["rpi2"]=$ARM_TOOLS/$X64_CROSS_COMPILE_CHAIN/bin/arm-linux-gnueabihf-
CCPREFIX["qemu"]=/usr/bin/arm-linux-gnueabihf-

declare -A IMAGE_NAME
IMAGE_NAME["rpi1"]=kernel.img
IMAGE_NAME["rpi2"]=kernel7.img
IMAGE_NAME["qemu"]=kernel-qemu

function create_dir_for_build_user () {
    local target_dir=$1

    sudo mkdir -p $target_dir
    sudo chown $BUILD_USER:$BUILD_GROUP $target_dir
}

function setup_build_dirs () {
  for dir in $BUILD_ROOT $BUILD_CACHE $BUILD_RESULTS $ARM_TOOLS $LINUX_KERNEL $RASPBERRY_FIRMWARE; do
    create_dir_for_build_user $dir
  done
}

function clone_or_update_repo_for () {
  local repo_url=$1
  local repo_path=$2
  local repo_commit=$3

  if [ ! -z "${repo_commit}" ]; then
    rm -rf $repo_path
  fi
  if [ -d ${repo_path}/.git ]; then
    cd $repo_path
    git reset --hard HEAD
    git pull
  else
    echo "Cloning $repo_path with commit $repo_commit"
    git clone --depth 1 $repo_url $repo_path
    if [ ! -z "${repo_commit}" ]; then
      cd $repo_path && git checkout -qf ${repo_commit}
    fi
  fi
}

function setup_arm_cross_compiler_toolchain () {
  echo "### Check if Raspberry Pi Crosscompiler repository at ${ARM_TOOLS} is still up to date"
  clone_or_update_repo_for 'https://github.com/raspberrypi/tools.git' $ARM_TOOLS ""
}

function setup_linux_kernel_sources () {
  echo "### Check if Raspberry Pi Linux Kernel repository at ${LINUX_KERNEL} is still up to date"
  clone_or_update_repo_for 'https://github.com/raspberrypi/linux.git' $LINUX_KERNEL $LINUX_KERNEL_COMMIT
  echo "### Cleaning .version file for deb packages"
  rm -f $LINUX_KERNEL/.version
}

function setup_rpi_firmware () {
  echo "### Check if Raspberry Pi Firmware repository at ${LINUX_KERNEL} is still up to date"
  clone_or_update_repo_for 'https://github.com/asb/firmware' $RASPBERRY_FIRMWARE ""
}

function prepare_kernel_building () {
  setup_build_dirs
  setup_arm_cross_compiler_toolchain
  setup_linux_kernel_sources
  setup_rpi_firmware
}


create_kernel_for () {
  local PI_VERSION=$1

  echo "###############"
  echo "### START building kernel for ${PI_VERSION}"
  echo "### Using CROSS_COMPILE = ${CCPREFIX[$PI_VERSION]}"

  cd $LINUX_KERNEL

  # add kernel branding for hyprOS
  sed -i 's/^EXTRAVERSION =.*/EXTRAVERSION = -hypriotos/g' Makefile
  # patch kernel header for qemu build
  if [ "$PI_VERSION" == "qemu" ]; then
    # install standard gcc cross compiler for ARM qemu
    apt-get install -y gcc-arm-linux-gnueabihf
    sed -i 's/40803/40802/g' arch/arm/kernel/asm-offsets.c
  fi

  # save git commit id of this build
  local KERNEL_COMMIT=`git rev-parse HEAD`
  echo "### git commit id of this kernel build is ${KERNEL_COMMIT}"

  # clean build artifacts
  make ARCH=arm clean

  # copy kernel configuration file over
  cp $LINUX_KERNEL_CONFIGS/${PI_VERSION}_docker_kernel_config $LINUX_KERNEL/.config

  echo "### building kernel"
  mkdir -p $BUILD_RESULTS/$PI_VERSION
  echo $KERNEL_COMMIT > $BUILD_RESULTS/kernel-commit.txt
  if [ "$PI_VERSION" == "qemu" ]; then
    echo "### patching kernel configs for qemu"
    patch -p1 -d . < $LINUX_KERNEL_CONFIGS/linux-qemu-linux-arm.patch
  fi
  if [ ! -z "${MENUCONFIG}" ]; then
    if [ "$PI_VERSION" == "qemu" ]; then
      if [ ! -z "$VERSATILE" ]; then
        echo "### make versatile_defconfig"
        rm -f $LINUX_KERNEL/.config
        make ARCH=arm clean
        make ARCH=arm versatile_defconfig
      fi
    fi
    echo "### starting menuconfig"
    ARCH=arm CROSS_COMPILE=${CCPREFIX[$PI_VERSION]} make menuconfig
    echo "### saving new config back to $LINUX_KERNEL_CONFIGS/${PI_VERSION}_docker_kernel_config"
    cp $LINUX_KERNEL/.config $LINUX_KERNEL_CONFIGS/${PI_VERSION}_docker_kernel_config
    return
  fi
  if [ "$PI_VERSION" == "qemu" ]; then
    make ARCH=arm -j$NUM_CPUS -k
  else
    ARCH=arm CROSS_COMPILE=${CCPREFIX[$PI_VERSION]} make -j$NUM_CPUS -k
  fi
  if [ "$PI_VERSION" == "qemu" ]; then
    cp $LINUX_KERNEL/arch/arm/boot/zImage $BUILD_RESULTS/$PI_VERSION/${IMAGE_NAME[${PI_VERSION}]}
  else
    cp $LINUX_KERNEL/arch/arm/boot/Image $BUILD_RESULTS/$PI_VERSION/${IMAGE_NAME[${PI_VERSION}]}
  fi

  echo "### building kernel modules"
  mkdir -p $BUILD_RESULTS/$PI_VERSION/modules
  ARCH=arm CROSS_COMPILE=${CCPREFIX[${PI_VERSION}]} INSTALL_MOD_PATH=$BUILD_RESULTS/$PI_VERSION/modules make modules_install -j$NUM_CPUS

  # remove symlinks, mustn't be part of raspberrypi-bootloader*.deb
  echo "### removing symlinks"
  rm -f $BUILD_RESULTS/$PI_VERSION/modules/lib/modules/*/build
  rm -f $BUILD_RESULTS/$PI_VERSION/modules/lib/modules/*/source

  if [ "$PI_VERSION" != "qemu" ]; then
    echo "### building deb packages"
    KBUILD_DEBARCH=armhf ARCH=arm CROSS_COMPILE=${CCPREFIX[${PI_VERSION}]} make deb-pkg
    mv ../*.deb $BUILD_RESULTS
  fi
  echo "###############"
  echo "### END building kernel for ${PI_VERSION}"
  echo "### Check the $BUILD_RESULTS/$PI_VERSION/${IMAGE_NAME[${PI_VERSION}]} and $BUILD_RESULTS/$PI_VERSION/modules directory on your host machine."
}

function create_kernel_deb_packages () {
  echo "###############"
  echo "### START building kernel DEBIAN PACKAGES"

  PKG_TMP=`mktemp -d`

  NEW_KERNEL=$PKG_TMP/raspberrypi-kernel-${NEW_VERSION}

  create_dir_for_build_user $NEW_KERNEL

  # copy over source files for building the packages
  echo "copying firmware from $RASPBERRY_FIRMWARE to $NEW_KERNEL"
  # skip modules directory from standard tree, because we will our on modules below
  tar --exclude=modules -C $RASPBERRY_FIRMWARE -cf - . | tar -C $NEW_KERNEL -xvf -
  # create an empty modules directory, because we have skipped this above
  mkdir -p $NEW_KERNEL/modules/
  cp -r $SRC_DIR/debian $NEW_KERNEL/debian
  touch $NEW_KERNEL/debian/files

  for pi_version in ${!CCPREFIX[@]}; do
    if [ "$PI_VERSION" != "qemu" ]; then
      cp $BUILD_RESULTS/$pi_version/${IMAGE_NAME[${pi_version}]} $NEW_KERNEL/boot
      cp -R $BUILD_RESULTS/$pi_version/modules/lib/modules/* $NEW_KERNEL/modules
    fi
  done
  # build debian packages
  cd $NEW_KERNEL

  dch -v ${NEW_VERSION} --package raspberrypi-firmware 'add Hypriot custom kernel'
  debuild --no-lintian -ePATH=${PATH}:$ARM_TOOLS/$X64_CROSS_COMPILE_CHAIN/bin -b -aarmhf -us -uc
  cp ../*.deb $BUILD_RESULTS

  echo "###############"
  echo "### FINISH building kernel DEBIAN PACKAGES"
}


##############
###  main  ###
##############

echo "*** all parameters are set ***"
echo "*** the kernel timestamp is: $NEW_VERSION ***"
echo "#############################################"


# setup necessary build environment: dir, repos, etc.
prepare_kernel_building

# create kernel, associated modules
for pi_version in ${!CCPREFIX[@]}; do
  build=1
  if [ ! -z "${ONLY_BUILD}" ]; then
    build=0
    if [ "${ONLY_BUILD}" == "$pi_version" ]; then
      build=1
    fi
  fi

  if [ $build -eq 1 ]; then
    create_kernel_for $pi_version
  fi
done

# create kernel packages
create_kernel_deb_packages

# running in vagrant VM
if [ -d /vagrant ]; then
  # copy build results to synced vagrant host folder
  FINAL_BUILD_RESULTS=/vagrant/build_results/$NEW_VERSION
else
  # running in drone build
  FINAL_BUILD_RESULTS=$SRC_DIR/output/$NEW_VERSION
fi

echo "###############"
echo "### Copy deb packages to $FINAL_BUILD_RESULTS"
mkdir -p $FINAL_BUILD_RESULTS
cp $BUILD_RESULTS/*.deb $FINAL_BUILD_RESULTS
cp $BUILD_RESULTS/*.txt $FINAL_BUILD_RESULTS
cp $BUILD_RESULTS/qemu/${IMAGE_NAME["qemu"]} $FINAL_BUILD_RESULTS

ls -lh $FINAL_BUILD_RESULTS
echo "*** kernel build done"
