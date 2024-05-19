#!/bin/bash

ips=(
  "192.168.0.100"
  "192.168.0.101"
  "192.168.0.102"
  "192.168.0.110"
  "192.168.0.104"
  "192.168.0.103"
  "192.168.0.120"
)

mac="80:38:fb:fc:cf:60"

for ip in "${ips[@]}"; do
  sudo arp -s "$ip" "$mac"
  if [ $? -eq 0 ]; then
    echo "Successfully added ARP entry for IP $ip with MAC $mac"
  else
    echo "Failed to add ARP entry for IP $ip with MAC $mac"
  fi
done
