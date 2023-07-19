#!/bin/bash

sudo apt update
sudo apt upgrade

if ! dpkg -s mdadm; then
  echo "The mdadm package is not installed."
  exit 1
fi

#Writing config
echo "DEVICE /dev/nvme0n1" >> /etc/mdadm/mdadm.conf
echo "DEVICE /dev/nvme1n1" >> /etc/mdadm/mdadm.conf
echo "ARRAY /dev/md0 RAID1" >> /etc/mdadm/mdadm.conf

#Creating raid
sudo mdadm --create /dev/md0 --verbose --level=1 --force --raid-devices=2 /dev/nvme0n1 /dev/nvme1n1

echo Checking raid configuration
cat /proc/mdstat
