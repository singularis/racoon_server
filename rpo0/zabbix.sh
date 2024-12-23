#!/usr/bin/env bash
set -e

# Variables
ZABBIX_VERSION="7.2.1"
ZABBIX_URL="https://cdn.zabbix.com/zabbix/sources/stable/7.2/zabbix-${ZABBIX_VERSION}.tar.gz"
INSTALL_PREFIX="/usr/local"
ZABBIX_USER="zabbix"
ZABBIX_GROUP="zabbix"
ZABBIX_DB="/var/lib/zabbix/zabbix.db"
ZABBIX_FRONTEND_DIR="/var/www/zabbix"
WEBUSER="www-data"
WEBSERVER="lighttpd"

# Update system
sudo apt-get update
sudo apt-get -y upgrade --fix-missing

# Install dependencies for building Zabbix server (server and frontend)
sudo apt-get install -y build-essential pkg-config sqlite3 libsqlite3-dev \
    libpcre3-dev libevent-dev libssl-dev libsnmp-dev libxml2-dev libcurl4-openssl-dev \
    libssh2-1-dev fping libiksemel-dev libldap2-dev unixodbc-dev libmicrohttpd-dev \
    openssl libopenipmi-dev libpcre3-dev libiconv-hook-dev git wget \
    lighttpd php-cgi php-fpm php-common php-xml php-sqlite3 php-ldap php-mbstring php-bcmath

# Create zabbix user and group
if ! id ${ZABBIX_USER} &>/dev/null; then
    sudo groupadd ${ZABBIX_GROUP}
    sudo useradd -g ${ZABBIX_GROUP} -s /bin/false ${ZABBIX_USER}
fi

# Download and extract Zabbix
wget ${ZABBIX_URL} -O /tmp/zabbix.tar.gz
cd /tmp
tar -xvf zabbix.tar.gz
cd zabbix-${ZABBIX_VERSION}

# Configure Zabbix for SQLite backend
./configure \
    --prefix=${INSTALL_PREFIX} \
    --enable-server \
    --enable-agent \
    --with-sqlite3 \
    --with-openssl \
    --with-ssh2 \
    --with-libpcre \
    --sysconfdir=/etc/zabbix \
    --enable-ipv6

# Build and install
make -j1 # On Pi Zero, using multiple jobs may overload memory.
sudo make install

# Create directories
sudo mkdir -p /etc/zabbix /var/log/zabbix /var/run/zabbix /var/lib/zabbix
sudo chown ${ZABBIX_USER}:${ZABBIX_GROUP} /var/log/zabbix /var/run/zabbix /var/lib/zabbix

# Initialize the SQLite database
sudo -u ${ZABBIX_USER} sqlite3 ${ZABBIX_DB} < database/schema.sql
sudo -u ${ZABBIX_USER} sqlite3 ${ZABBIX_DB} < database/images.sql
sudo -u ${ZABBIX_USER} sqlite3 ${ZABBIX_DB} < database/data.sql

# Configure Zabbix server
sudo tee /etc/zabbix/zabbix_server.conf > /dev/null <<EOF
LogFile=/var/log/zabbix/zabbix_server.log
DBName=${ZABBIX_DB}
DBUser=
DBPassword=
DBSocket=
DBHost=
DBPort=
ListenIP=0.0.0.0
EOF

sudo chown ${ZABBIX_USER}:${ZABBIX_GROUP} /etc/zabbix/zabbix_server.conf

# Install frontend
sudo mkdir -p ${ZABBIX_FRONTEND_DIR}
sudo cp -r frontends/php/* ${ZABBIX_FRONTEND_DIR}
sudo chown -R ${WEBUSER}:${WEBUSER} ${ZABBIX_FRONTEND_DIR}

# Configure PHP for Zabbix
PHP_INI="/etc/php/7.4/cgi/php.ini"
if [ -f "${PHP_INI}" ]; then
    sudo sed -i 's/max_execution_time = .*/max_execution_time = 300/' "${PHP_INI}"
    sudo sed -i 's/post_max_size = .*/post_max_size = 16M/' "${PHP_INI}"
    sudo sed -i 's/upload_max_filesize = .*/upload_max_filesize = 2M/' "${PHP_INI}"
    sudo sed -i 's/;date.timezone =.*/date.timezone = UTC/' "${PHP_INI}"
fi

# Configure Lighttpd
sudo tee /etc/lighttpd/conf-available/15-zabbix.conf > /dev/null <<EOF
server.modules += ("mod_fastcgi")
alias.url += ( "/zabbix" => "${ZABBIX_FRONTEND_DIR}" )
fastcgi.server += ( ".php" =>
    ((
        "bin-path" => "/usr/bin/php-cgi",
        "socket" => "/var/run/lighttpd/php.socket",
        "max-procs" => 1,
        "bin-environment" => (
            "PHP_FCGI_CHILDREN" => "1",
            "PHP_FCGI_MAX_REQUESTS" => "1000"
        ),
        "broken-scriptfilename" => "enable"
    ))
)
EOF

sudo lighty-enable-mod fastcgi
sudo ln -s /etc/lighttpd/conf-available/15-zabbix.conf /etc/lighttpd/conf-enabled/15-zabbix.conf || true

# Restart services
sudo service php7.4-fpm restart || true
sudo service php-fpm restart || true
sudo service lighttpd restart

# Create a simple systemd unit for Zabbix server if it doesn't exist
if [ ! -f /etc/systemd/system/zabbix-server.service ]; then
    sudo tee /etc/systemd/system/zabbix-server.service > /dev/null <<EOF
[Unit]
Description=Zabbix Server
After=network-online.target

[Service]
User=${ZABBIX_USER}
Group=${ZABBIX_GROUP}
ExecStart=${INSTALL_PREFIX}/sbin/zabbix_server -c /etc/zabbix/zabbix_server.conf
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable zabbix-server
fi

sudo systemctl start zabbix-server

echo "Zabbix server installation complete."
echo "Access the Zabbix UI at http://<raspberry_pi_ip>/zabbix"
