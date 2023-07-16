#!/bin/bash

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

ansible-playbook server_setup.yml