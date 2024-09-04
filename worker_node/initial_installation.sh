#!/bin/bash

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

echo "Updating the package list..."
apt-get update -y
apt upgrade -y

echo "Installing software prerequisites for Ansible..."
sudo apt install fish -y
# Install dependencies
apt-get install -y software-properties-common

# Add Ansible's PPA repository
echo "Adding Ansible PPA repository..."
add-apt-repository --yes --update ppa:ansible/ansible

# Install Ansible
echo "Installing Ansible..."
apt-get install -y ansible