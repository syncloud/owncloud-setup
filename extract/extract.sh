#!/bin/bash

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

if [ "$1" == "" ]; then
    echo "Usage: $0 board"
    exit 1
fi

SYNCLOUD_BOARD=$1

CPU_FREQUENCY_CONTROL=false
CPU_FREQUENCY_GOVERNOR=
CPU_FREQUENCY_MAX=
CPU_FREQUENCY_MIN=

if [[ ${SYNCLOUD_BOARD} == "raspberrypi" ]]; then
  IMAGE_FILE=2015-05-05-raspbian-wheezy.img
  IMAGE_FILE_ZIP=${IMAGE_FILE}.zip
  DOWNLOAD_IMAGE="wget --progress=dot:mega http://downloads.raspberrypi.org/raspbian_latest -O $IMAGE_FILE_ZIP"
  UNZIP=unzip
elif [[ ${SYNCLOUD_BOARD} == "beagleboneblack" ]]; then
  echo "single partition is not supported yet"
  exit 1
  IMAGE_FILE=bone-debian-7.8-console-armhf-2015-02-19-2gb.img
  IMAGE_FILE_ZIP=${IMAGE_FILE}.xz
  DOWNLOAD_IMAGE="wget --progress=dot:mega https://rcn-ee.net/rootfs/2015-02-19/microsd/$IMAGE_FILE_ZIP"
  UNZIP=unxz
elif [[ ${SYNCLOUD_BOARD} == "cubieboard" ]]; then
  IMAGE_FILE="Cubian-nano+headless-x1-a10.img"
  IMAGE_FILE_ZIP=${IMAGE_FILE}.7z
  DOWNLOAD_IMAGE="wget --progress=dot:mega https://s3-us-west-2.amazonaws.com/syncloud-distributives/Cubian-nano%2Bheadless-x1-a10.img.7z -O $IMAGE_FILE_ZIP"
  UNZIP="p7zip -d"
  CPU_FREQUENCY_CONTROL=true
  CPU_FREQUENCY_GOVERNOR=performance
  CPU_FREQUENCY_MAX=1056000
  CPU_FREQUENCY_MIN=648000
elif [[ ${SYNCLOUD_BOARD} == "cubieboard2" ]]; then
  IMAGE_FILE="Cubian-nano+headless-x1-a20.img"
  IMAGE_FILE_ZIP=${IMAGE_FILE}.7z
  DOWNLOAD_IMAGE="wget --progress=dot:mega https://s3-us-west-2.amazonaws.com/syncloud-distributives/Cubian-nano%2Bheadless-x1-a20.img.7z -O $IMAGE_FILE_ZIP"
  UNZIP="p7zip -d"
  CPU_FREQUENCY_CONTROL=true
  CPU_FREQUENCY_GOVERNOR=performance
  CPU_FREQUENCY_MAX=1056000
  CPU_FREQUENCY_MIN=648000
elif [[ ${SYNCLOUD_BOARD} == "cubietruck" ]]; then
  IMAGE_FILE="Cubian-nano+headless-x1-a20-cubietruck.img"
  IMAGE_FILE_ZIP=${IMAGE_FILE}.7z
  DOWNLOAD_IMAGE="wget --progress=dot:mega https://s3-us-west-2.amazonaws.com/syncloud-distributives/Cubian-nano%2Bheadless-x1-a20-cubietruck.img.7z -O $IMAGE_FILE_ZIP"
  UNZIP="p7zip -d"
  CPU_FREQUENCY_CONTROL=true
  CPU_FREQUENCY_GOVERNOR=performance
  CPU_FREQUENCY_MAX=1056000
  CPU_FREQUENCY_MIN=648000
#elif [[ ${SYNCLOUD_BOARD} == "odroid-xu3" ]]; then
fi

PARTED_SECTOR_UNIT=s
DD_SECTOR_UNIT=b
OUTPUT=${SYNCLOUD_BOARD}

function cleanup {
    echo "cleanup"
    umount extract_rootfs
    kpartx -d ${IMAGE_FILE}
}

apt-get install unzip

cleanup

if [ ! -f ${IMAGE_FILE} ]; then
  echo "Base image $IMAGE_FILE is not found, getting new one ..."
  ${DOWNLOAD_IMAGE}
  ls -la
  ${UNZIP} ${IMAGE_FILE_ZIP}
fi

parted -sm ${IMAGE_FILE} print | tail -n +3

PARTITIONS=$(parted -sm ${IMAGE_FILE} print | tail -n +3 | wc -l)
if [ ${PARTITIONS} == 1 ]; then
    echo "single partition is not supported yet"
    exit 1
fi

BOOT_PARTITION_END_SECTOR=$(parted -sm ${IMAGE_FILE} unit ${PARTED_SECTOR_UNIT} print | grep "^1" | cut -d ':' -f3 | cut -d 's' -f1)
rm -rf ${OUTPUT}
mkdir ${OUTPUT}

echo "applying cpu frequency fix"
if [ "$CPU_FREQUENCY_CONTROL" = true ] ; then
    mkdir -p ${OUTPUT}/root/var/lib
    touch ${OUTPUT}/root/var/lib/cpu_frequency_control
    echo -n ${CPU_FREQUENCY_GOVERNOR} > ${OUTPUT}/root/var/lib/cpu_frequency_governor
    echo -n ${CPU_FREQUENCY_MAX} > ${OUTPUT}/root/var/lib/cpu_frequency_max
    echo -n ${CPU_FREQUENCY_MIN} > ${OUTPUT}/root/var/lib/cpu_frequency_min
fi

echo "extracting boot partition with boot loader"
dd if=${IMAGE_FILE} of=${OUTPUT}/boot bs=1${DD_SECTOR_UNIT} count=$(( ${BOOT_PARTITION_END_SECTOR} ))

echo "extracting kernel modules and firmware from rootfs"

rm -rf extract_rootfs
mkdir -p extract_rootfs
kpartx -av ${IMAGE_FILE}
LOOP=$(kpartx -l ${IMAGE_FILE} | head -1 | cut -d ' ' -f1 | cut -c1-5)
mount /dev/mapper/${LOOP}p2 extract_rootfs

mount | grep extract_rootfs

losetup -l

ls -la extract_rootfs/

mkdir ${OUTPUT}/root/lib
cp -rp extract_rootfs/lib/firmware ${OUTPUT}/root/lib/firmware
cp -rp extract_rootfs/lib/modules ${OUTPUT}/root/lib/modules
sync

cleanup

rm -rf ${OUTPUT}.tar.gz
tar czf ${OUTPUT}.tar.gz ${OUTPUT}

echo "result: $OUTPUT.tar.gz"
