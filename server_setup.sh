#!/bin/bash

# Check if the user is root.
if [[ $EUID -ne 0 ]]; then
  echo "You must be root to run this script."
  exit 1
fi

#Install fish
sudo apt-add-repository ppa:fish-shell/release-3
sudo apt update
sudo apt install fish

# Check if kubectl is already installed.
if kubectl version > /dev/null; then
  echo "kubectl is already installed."
  exit 0
fi

# Install kubectl using apt.
sudo apt-get install -y ca-certificates curl
sudo apt-get install -y apt-transport-https
curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-archive-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt install kubectl

# Verify the installation.
kubectl version

sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config
# Disable password authentication.

# Get the current SSH port.
current_port=$(grep 'Port ' /etc/ssh/sshd_config | awk '{print $2}')

# Get the new SSH port.
echo "Promt a new port: "
read new_port

# Check if the new SSH port is valid.
if ! [[ $new_port -ge 1024 && $new_port -le 65535 ]]; then
  echo "The new SSH port is not valid."
  exit 1
fi

# Update the SSH port in the SSH configuration file.
sed -i "s/$current_port/$new_port/g" /etc/ssh/sshd_config

# Restart the SSH service.
service ssh restart

# Print a success message.
echo "The SSH port has been successfully changed to $new_port."

# Check if Python is already installed.
if python --version > /dev/null; then
  echo "Python is already installed."
  exit 0
fi

# Install Python using apt.
sudo apt install python3

# Check the Python version.
python --version

# Install Ansible using pip.
pip install ansible

# Check the Ansible version.
ansible --version

# Restart the SSH service.
service ssh restart

ansible-playbook server_setup.yml