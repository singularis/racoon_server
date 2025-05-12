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
sudo apt install -y cockpit
sudo systemctl start cockpit
sudo systemctl enable cockpit

# Add Ansible's PPA repository
echo "Adding Ansible PPA repository..."
add-apt-repository --yes --update ppa:ansible/ansible

# Install Ansible
echo "Installing Ansible..."
apt-get install -y ansible
nc 127.0.0.1 6443 -v
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.ipv4.ip_forward = 1
EOF
sudo sysctl --system
sysctl net.ipv4.ip_forward
export KUBERNETES_VERSION=v1.32
export CRIO_VERSION=v1.32
apt-get install -y software-properties-common curl
curl -fsSL https://pkgs.k8s.io/core:/stable:/$KUBERNETES_VERSION/deb/Release.key |
    gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/$KUBERNETES_VERSION/deb/ /" |
    tee /etc/apt/sources.list.d/kubernetes.list
curl -fsSL https://pkgs.k8s.io/addons:/cri-o:/stable:/$CRIO_VERSION/deb/Release.key |
    gpg --dearmor -o /etc/apt/keyrings/cri-o-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/cri-o-apt-keyring.gpg] https://pkgs.k8s.io/addons:/cri-o:/stable:/$CRIO_VERSION/deb/ /" |
    tee /etc/apt/sources.list.d/cri-o.list
apt-get update
apt-get install -y cri-o kubelet kubeadm kubectl
systemctl start crio.service
swapoff -a
modprobe br_netfilter
sysctl -w net.ipv4.ip_forward=1
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable --now kubelet
sudo apt install -y cockpit-pcp
sudo systemctl enable cockpit --now

#RPI
sudo apt install -y git cmake gcc-arm-none-eabi libnewlib-arm-none-eabi libstdc++-arm-none-eabi-newlib libusb-1.0-0-dev
sudo apt install -y build-essential rkdeveloptool
git clone https://github.com/raspberrypi/pico-sdk.git
cd pico-sdk
git submodule update --init
# Documentations https://docs.radxa.com/en/x/x4/software/c_sdk_examples
export PICO_SDK_PATH=/home/dante/pico-sdk
sudo apt install -y gpiod
sudo apt install -y libgpiod-tools

