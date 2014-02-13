#!/bin/bash -x

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

VERSION_TO_INSTALL='latest' #[latest|appstore] 
DATADIR=/data
OWNCLOUDPATH='/var/www/owncloud'
OWNCLOUDDATA=$DATADIR

if [ ! -d "$DATADIR" ]; then
  mkdir $DATADIR
else
  echo "WARNING: data dir already exists"
fi

chmod 770 $DATADIR

apt-get update
# Tools
apt-get -y install php-apc miniupnpc

# install mySql (set root user password to root)
echo "mysql-server-5.5 mysql-server/root_password password root" | debconf-set-selections
echo "mysql-server-5.5 mysql-server/root_password_again password root" | debconf-set-selections
apt-get -y install mysql-server-5.5 unzip

# create MySQL database and user/password
mysql -uroot -proot <<EOFMYSQL
CREATE USER 'owncloud'@'localhost' IDENTIFIED BY 'owncloud';
CREATE DATABASE IF NOT EXISTS owncloud;
GRANT ALL PRIVILEGES ON owncloud.* TO 'owncloud'@'localhost' IDENTIFIED BY 'owncloud';
EOFMYSQL

# install owncloud
OS_VERSION=$(lsb_release -sr)
if [[ $OS_VERSION = "13.06" ]]; then OS_VERSION="13.04"; fi # fix for cubieboard lubuntu 13.06
owncloud_repo=http://download.opensuse.org/repositories/isv:ownCloud:community/xUbuntu_$OS_VERSION
wget --no-check-certificate -qO - $owncloud_repo/Release.key | apt-key add -
echo "deb $owncloud_repo/ /" > /etc/apt/sources.list.d/owncloud.list
apt-get update
apt-get -y --no-install-recommends install owncloud

#fix owncloud warning for 13.10
if [[ $OS_VERSION = "13.10" ]]; then 
   
cat <<APACHE > /etc/apache2/sites-available/owncloud.conf
<Directory /var/www/owncloud>
  AllowOverride All
</Directory>
APACHE

a2ensite owncloud

fi

# change ownership of owncloud data folder
chown -R www-data:www-data $OWNCLOUDDATA

# disable some owncloud apps
sed -i -e "/<default_enable\/>/d" $OWNCLOUDPATH/apps/contacts/appinfo/info.xml
sed -i -e "/<default_enable\/>/d" $OWNCLOUDPATH/apps/calendar/appinfo/info.xml
sed -i -e "/<default_enable\/>/d" $OWNCLOUDPATH/apps/updater/appinfo/info.xml

cat <<AUTOCNF > $OWNCLOUDPATH/config/autoconfig.php
<?php
\$AUTOCONFIG = array(
  "dbtype"        => "mysql", 
  "dbname"        => "owncloud",
  "dbuser"        => "root",
  "dbpass"        => "root",
  "dbhost"        => "localhost",
  "directory"     => "$OWNCLOUDDATA",
);
AUTOCNF

# setup crontab task
su -c "echo \"*/1 * * * * php -f ${OWNCLOUDPATH}/cron.php\" | crontab -" www-data

cd $OWNCLOUDPATH/apps

wget -qO- https://raw.github.com/syncloud/upnp_port_mapper/master/get_$VERSION_TO_INSTALL.sh | sh
   
sed -i '/<info>/a \<default_enable\/>' ./upnp_port_mapper/appinfo/info.xml
sed -i '/<info>/a \<default_native\/>' ./upnp_port_mapper/appinfo/info.xml
sed -i '/<info>/a \<default_mapped\/>' ./upnp_port_mapper/appinfo/info.xml

service apache2 reload

# Service discovery

cat <<AVAHI > /etc/avahi/services/owncloud.service
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">Owncloud on %h</name>
  <service>
    <type>_http._tcp</type>
    <port>80</port>
    <txt-record>path=/owncloud</txt-record>
  </service>
</service-group>
AVAHI

service avahi-daemon restart
