#!/bin/bash

# Script should bes started in the current shell ". user_setup.sh"

# Get the user's email address.
echo "Enter your email address: "
read email

# Get the user's name .
echo "Enter your name: "
read name

#Generate new SSH keys
ssh-keygen -t rsa -b 4096 -C "$email"
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_rsa

# Print the public key.
echo "Your public key is:"
cat ~/.ssh/id_rsa.pub

# Prompt for the user's SSH key.
echo "Enter your SSH key: "
read ssh_key

# Add the user's SSH key to the authorized_keys file.
echo "$ssh_key" >> ~/.ssh/authorized_keys

#Setup git
git config --global user.email "$email"
git config --global user.name "$name"
