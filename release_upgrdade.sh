#!/bin/bash

# This bash script will update Ubuntu to the newest version available.

# Make sure only root can run this script
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root. Please use sudo." >&2
   exit 1
fi

# Firstly, update your current version of Ubuntu
echo "Updating currently installed packages..."
apt-get update && apt-get upgrade -y
apt-get dist-upgrade -y

# Once the updates are installed, you can upgrade to the new Ubuntu release
echo "Starting the Ubuntu distribution upgrade process..."
do-release-upgrade

# Cleanup after upgrade
echo "Cleaning up..."
apt-get autoremove -y
apt-get autoclean

echo "Ubuntu update complete. A reboot is recommended now."
