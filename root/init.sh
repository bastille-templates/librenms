#!/bin/bash
# This script initializes the MySQL database for LibreNMS.
# Generate a random password for the LibreNMS database user.
MYDB_USER="librenms"
MYDB_PASS=$(openssl rand -base64 12)
MYDB="librenms"
mysql -u root -e "CREATE DATABASE $MYDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql -u root -e "CREATE USER '$MYDB_USER'@'localhost' IDENTIFIED BY '$MYDB_PASS';"
mysql -u root -e "GRANT ALL PRIVILEGES ON $MYDB.* TO '$MYDB_USER'@'localhost';"
mysql -u root -e "FLUSH PRIVILEGES;"

# Store the generated password in a file for later use
cat > /root/librenms.credentials <<'EOF'
LibreNMS Database Credentials
--------------------------
Username: $MYDB_USER
Password: $MYDB_PASS
Database: $MYDB
EOF

# Configure Redis for LibreNMS
REDIS_PASS=$(openssl rand -base64 12)
REDIS_CONF="/usr/local/etc/redis.conf"

{
  echo "LibreNMS Credentials"
  echo "Username: ${APP_USER}"
  echo "Password: ${APP_PASSWORD}"
} >> /root/librenms.credentials

if [ -f "$REDIS_CONF" ]; then
  sed -i.bak \
    -e 's#^bind .*#bind 127.0.0.1 ::1#' \
    -e 's#^protected-mode .*#protected-mode yes#' \
    -e 's#^# requirepass .*#requirepass $REDIS_PASS#' \
    "$REDIS_CONF"
fi

# Configure PHP-FPM to listen on a socket for LibreNMS.
wwwconf="/usr/local/etc/php-fpm.d/www.conf"
if [ -f "$wwwconf" ]; then
  sed -i.bak \
    -e 's#^listen = .*#listen = /var/run/php-fpm-librenms.sock#' \
    -e 's#^listen.owner = .*#listen.owner = www#' \
    -e 's#^listen.group = .*#listen.group = www#' \
    -e 's#^listen.mode = .*#listen.mode = 0660#' \
    "$wwwconf"
fi

# Create a php.ini file
cp /usr/local/etc/php.ini-production /usr/local/etc/php.ini
phpini="/usr/local/etc/php.ini"
if [ -f "$phpini" ]; then
  sed -i.bak \
    -e 's#^;date.timezone =.*#date.timezone = Asia/Jakarta#' \
    -e 's#^upload_max_filesize =.*#upload_max_filesize = 100M#' \
    -e 's#^post_max_size =.*#post_max_size = 100M#' \
    "$phpini"
fi

# LibreNMS configuration file
cp /usr/local/www/librenms/config.php.default /usr/local/www/librenms/config.php

# Create the directory for RRD graphs and set ownership www:www
mkdir -p /var/db/librenms/rrd/journal && mkdir -p /var/run/rrdcached
chown -R www:www /var/db/librenms/rrd /var/run/rrdcached
chmod 770 /var/run/rrdcached /var/db/librenms/rrd/journal

sysrc rrdcached_enable="YES"

sysrc rrdcached_user="root" && sysrc rrdcached_group="www"

sysrc rrdcached_flags="-l unix:/var/run/rrdcached.sock -s www -w 1800 -z 1800 -t 4 -b /var/db/librenms/rrd -j /var/db/librenms/rrd/journal -p /var/run/rrdcached.pid -B -F -R"

# LibreNMS environment variables
cp /usr/local/www/librenms/.env.example /usr/local/www/librenms/.env && chown www:www /usr/local/www/librenms/.env

node_id=$(php -r 'echo uniqid() . "\n";')
lnms_env="/usr/local/www/librenms/.env"
if [ -f "$lnms_env" ]; then
  sed -i.bak \
    -e "s#^DB_HOST=.*#DB_HOST=localhost#" \
    -e "s#^DB_DATABASE=.*#DB_DATABASE=librenms#" \
    -e "s#^DB_USERNAME=.*#DB_USERNAME=$MYDB_USER#" \
    -e "s#^DB_PASSWORD=.*#DB_PASSWORD=$MYDB_PASS#" \
    -e "s#^NODE_ID=.*#NODE_ID=$node_id#" \
    "$lnms_env"
fi

# Set ownership and permissions for LibreNMS directories
chown -R www:www /usr/local/www/librenms/storage /usr/local/www/librenms/bootstrap/cache

# Generate the application key and cache the configuration
su -m www -c "lnms key:generate" && chmod 600 /usr/local/www/librenms/.env

# Clear and cache the configuration
su -m www -c "lnms key:rotate --generate-new-key"
su -m www -c "lnms config:clear" && su -m www -c "lnms config:cache"

su -m www -c "lnms config:set base_url http://${JAIL_IP}"

curl -o /usr/local/bin/distro https://raw.githubusercontent.com/librenms/librenms-agent/master/snmp/distro
chmod +x /usr/local/bin/distro
systemctl enable snmpd && systemctl restart snmpd