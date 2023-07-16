#!/bin/bash

# Check if the user is root.
if [[ $EUID -ne 0 ]]; then
  echo "You must be root to run this script."
  exit 1
fi

# Get the user's email address.
echo "Enter your email address: "
read email

# Get the user's name .
echo "Enter your name: "
read name

#Install fish
sudo apt-add-repository ppa:fish-shell/release-3
sudo apt update
sudo apt install fish

#Generate new SSH keys
ssh-keygen -t rsa -b 4096 -C "$email"
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_rsa

# Print the public key.
echo "Your public key is:"
cat ~/.ssh/id_rsa.pub

# Disable password authentication.
sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config

# Prompt for the user's SSH key.
echo "Enter your SSH key: "
read ssh_key

# Add the user's SSH key to the authorized_keys file.
echo "$ssh_key" >> /etc/ssh/authorized_keys

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


# Restart the SSH service.
service ssh restart

#Setup git
git config --global user.email "$email"
git config --global user.name "$name"