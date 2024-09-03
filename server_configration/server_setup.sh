#!/bin/bash

# Check if the user is root.
if [[ $EUID -ne 0 ]]; then
  echo "You must be root to run this script."
  exit 1
fi

#Install fish
sudo apt-add-repository ppa:fish-shell/release-3
sudo apt update
sudo apt install fish -y

# Check if kubectl is already installed.
if kubectl version > /dev/null; then
  echo "kubectl is already installed."
  exit 0
fi

# Verify the installation.
kubectl version

sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config
# Disable password authentication.

# Print a success message.
echo "The SSH port has been successfully changed to $new_port."

# Check if Python is already installed.
if python --version > /dev/null; then
  echo "Python is already installed."
  exit 0
fi

# Install Python using apt.
sudo apt install python3 -y
sudo apt install python3-pip -y
sudo apt install ansible -y

#Java
sudo apt install default-jre -y

#Maven

sudo apt install maven -y

# Check the Python version.
python3 --version

# Install Ansible using pip.
pip3 install ansible

# Check the Ansible version.
ansible --version

# Restart the SSH service.
service ssh restart