#!/bin/bash -x

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

SYNCLOUD_BOARD=$(cat /etc/hostname)

if [[ ${SYNCLOUD_BOARD} == "Cubian" ]]; then
  SYNCLOUD_BOARD=$(./cubian-boardname.sh)
fi

CI_TEMP=/data/syncloud/ci/temp

echo "Building board: ${SYNCLOUD_BOARD}"

if [[ ${SYNCLOUD_BOARD} == "raspberrypi" ]]; then
  PARTITION=2
  USER=pi
  NAME=2014-01-07-wheezy-raspbian
  IMAGE_FILE=2014-01-07-wheezy-raspbian.img
  IMAGE_FILE_ZIP=$IMAGE_FILE.zip
  DOWNLOAD_IMAGE="wget --progress=dot:mega http://downloads.raspberrypi.org/raspbian_latest -O $IMAGE_FILE_ZIP"
  UNZIP=unzip
  BOARD=raspberrypi
  RESOLVCONF_FROM=
  RESOLVCONF_TO=
  RESIZE=
  KILL_HOST_MYSQL=false
  STOP_NTP=false
  INIT_RANDOM=false
elif [[ ${SYNCLOUD_BOARD} == "arm" ]]; then
  PARTITION=2
  USER=ubuntu
  IMAGE_FILE=BBB-eMMC-flasher-ubuntu-14.04-console-armhf-2014-08-13-2gb.img
  #IMAGE_FILE=BBB-eMMC-flasher-debian-7.6-console-armhf-2014-08-13-2gb.img
  IMAGE_FILE_ZIP=$IMAGE_FILE.xz
  DOWNLOAD_IMAGE="wget --progress=dot:mega https://rcn-ee.net/deb/flasher/trusty/$IMAGE_FILE_ZIP"
  #DOWNLOAD_IMAGE="wget --progress=dot:mega https://rcn-ee.net/deb/flasher/wheezy/$IMAGE_FILE_ZIP"
  UNZIP=unxz
  BOARD=beagleboneblack
  RESOLVCONF_FROM=/run/resolvconf/resolv.conf
  RESOLVCONF_TO=/run/resolvconf/resolv.conf
  #RESOLVCONF_FROM=
  #RESOLVCONF_TO=
  RESIZE=
  KILL_HOST_MYSQL=false
  STOP_NTP=false
  INIT_RANDOM=false
elif [[ ${SYNCLOUD_BOARD} == "cubieboard" ]]; then
  PARTITION=1
  USER=cubie
  IMAGE_FILE=Cubian-base-r8-a10-large.img
  IMAGE_FILE_ZIP=$IMAGE_FILE.7z
  DOWNLOAD_IMAGE="wget --progress=dot:mega https://www.dropbox.com/s/spnhzwhsit9ggz6/Cubian-base-r8-a10-large.img.7z -O $IMAGE_FILE_ZIP"
  UNZIP="p7zip -d"
  BOARD=cubieboard
  RESOLVCONF_FROM=/etc/resolv.conf
  RESOLVCONF_TO=/etc/resolv.conf
  RESIZE=
  KILL_HOST_MYSQL=true
  STOP_NTP=true
  INIT_RANDOM=true
elif [[ ${SYNCLOUD_BOARD} == "cubieboard2" ]]; then
  PARTITION=1
  USER=cubie
  IMAGE_FILE=Cubian-base-r5-a20-large.img
  IMAGE_FILE_ZIP=$IMAGE_FILE.7z
  DOWNLOAD_IMAGE="wget --progress=dot:mega https://www.dropbox.com/s/vh8nsrsloplwji0/Cubian-base-r5-a20-large.img.7z -O $IMAGE_FILE_ZIP"
  UNZIP="p7zip -d"
  BOARD=cubieboard2
  RESOLVCONF_FROM=/etc/resolv.conf
  RESOLVCONF_TO=/etc/resolv.conf
  RESIZE=
  KILL_HOST_MYSQL=true
  STOP_NTP=true
  INIT_RANDOM=true
elif [[ ${SYNCLOUD_BOARD} == "cubietruck" ]]; then
  PARTITION=1
  USER=cubie
  IMAGE_FILE=Cubian-base-r5-a20-ct-large.img
  IMAGE_FILE_ZIP=$IMAGE_FILE.7z
  DOWNLOAD_IMAGE="wget --progress=dot:mega https://www.dropbox.com/s/m5hfp7escijllaj/Cubian-base-r5-a20-ct-large.img.7z -O $IMAGE_FILE_ZIP"
  UNZIP="p7zip -d"
  BOARD=cubietruck
  RESOLVCONF_FROM=/etc/resolv.conf
  RESOLVCONF_TO=/etc/resolv.conf
  RESIZE=
  KILL_HOST_MYSQL=true
  STOP_NTP=true
  INIT_RANDOM=true
fi
IMAGE_FILE_TEMP=$CI_TEMP/$IMAGE_FILE

echo "existing path: $PATH"
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

if [[ -z "$1" ]]; then
  BUILD_ID=$(date +%F-%H-%M-%S)
else
  BUILD_ID=$1
fi

SYNCLOUD_IMAGE=syncloud-$BOARD-$BUILD_ID.img

# build syncloud setup script
./build.sh

# checking if base image file already present, download and resize if doesn't 
mkdir -p $CI_TEMP
if [ ! -f $IMAGE_FILE_TEMP ]; then
  echo "Base image $IMAGE_FILE_TEMP is not found, getting new one ..."
  $DOWNLOAD_IMAGE
  ls -la
  $UNZIP $IMAGE_FILE_ZIP

  if [ -n "$RESIZE" ]; then
    echo "Need to resize base image, resizing ..."
    ./resize-partition.sh $IMAGE_FILE $PARTITION $RESIZE
  fi

  mv $IMAGE_FILE $IMAGE_FILE_TEMP
fi

# copy image file we are going to modify
cp $IMAGE_FILE_TEMP $SYNCLOUD_IMAGE

# command for getting image partitions information
FILE_INFO$(parted -sm $SYNCLOUD_IMAGE unit B print)
echo $FILE_INFO

# retrieving partition start sector
STARTSECTOR=$(echo $FILE_INFO | grep -oP '^$PARTITION:\K[0-9]*(?=B)')

# folder for mounting image file
IMAGE_FOLDER=imgmnt

if mount | grep $IMAGE_FOLDER; then
  echo "image already mounted, unmounting ..."
  umount $IMAGE_FOLDER
fi

# checking who is using image folder
lsof | grep $IMAGE_FOLDER

LOOP_DEVICE=/dev/loop0;

# if /dev/loop0 is mapped then unmap it
if losetup -a | grep $LOOP_DEVICE; then
  echo "/dev/loop0 is already setup, deleting ..."
  losetup -d $LOOP_DEVICE
fi

# map /dev/loop0 to image file
losetup -o $STARTSECTOR $LOOP_DEVICE $SYNCLOUD_IMAGE

if [ -d $IMAGE_FOLDER ]; then 
  echo "$IMAGE_FOLDER dir exists, deleting ..."
  rm -rf $IMAGE_FOLDER
fi

# mount /dev/loop0 to IMAGE_FOLDER folder
pwd
mkdir $IMAGE_FOLDER

mount $LOOP_DEVICE $IMAGE_FOLDER

if [ -n "$RESOLVCONF_FROM" ]; then
  RESOLV_DIR=$IMAGE_FOLDER/$(dirname $RESOLVCONF_TO)
  echo "creatig resolv conf dir: ${RESOLV_DIR}"
  mkdir -p $RESOLV_DIR
  echo "copying resolv conf from $RESOLVCONF_FROM to $IMAGE_FOLDER$RESOLVCONF_TO"
  cp $RESOLVCONF_FROM $IMAGE_FOLDER$RESOLVCONF_TO
fi

if [ "$INIT_RANDOM" = true ] ; then
  chroot $IMAGE_FOLDER mknod /dev/random c 1 8
  chroot $IMAGE_FOLDER mknod /dev/urandom c 1 9
fi

# copy syncloud setup script to IMAGE_FOLDER
cp syncloud-setup.sh $IMAGE_FOLDER/tmp

chroot $IMAGE_FOLDER rm -rf /var/cache/apt/archives/*.deb
chroot $IMAGE_FOLDER rm -rf /opt/Wolfram

chroot $IMAGE_FOLDER /tmp/syncloud-setup.sh

chroot $IMAGE_FOLDER rm -rf /var/cache/apt/archives/*.deb
chroot $IMAGE_FOLDER rm -rf /opt/Wolfram

if [ -f $IMAGE_FOLDER/usr/sbin/minissdpd ]; then
  echo "stopping minissdpd holding the $IMAGE_FOLDER ..."
  chroot $IMAGE_FOLDER /etc/init.d/minissdpd stop
fi

if [ "$STOP_NTP" = true ] ; then
    echo 'Stopping ntp'
    chroot $IMAGE_FOLDER service ntp stop
fi

if [ "$KILL_HOST_MYSQL" = true ] ; then
    echo 'Killing host mysql!'
    chroot $IMAGE_FOLDER service mysql stop
    pkill mysqld
fi

if [ -n "$RESOLVCONF_FROM" ]; then
  echo "removing resolv conf: $IMAGE_FOLDER$RESOLVCONF_TO"
  rm $IMAGE_FOLDER$RESOLVCONF_TO
fi

while lsof | grep $IMAGE_FOLDER | grep -v "build-image.sh" > /dev/null
do 
  sleep 5
  echo "waiting for all proccesses using $IMAGE_FOLDER to die"
done

echo "unmounting $IMAGE_FOLDER"
umount $IMAGE_FOLDER

echo "removing loop device"
losetup -d $LOOP_DEVICE

echo "build finished"
