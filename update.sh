#!/bin/bash

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

echo "Updating package lists..."
apt-get update

echo "Upgrading installed packages..."
apt-get upgrade -y

echo "Performing distribution upgrade..."
apt-get dist-upgrade -y

echo "Removing unnecessary packages..."
apt-get autoremove -y

echo "Cleaning up APT cache..."
apt-get autoclean

echo "Update and cleanup process complete!"
