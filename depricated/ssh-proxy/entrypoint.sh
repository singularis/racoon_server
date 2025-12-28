#!/bin/bash
set -e

mkdir -p /home/proxyuser/.ssh
chmod 700 /home/proxyuser/.ssh

if [ -d "/etc/ssh/client_keys" ]; then
    echo "Importing client public keys..."
    cat /etc/ssh/client_keys/* > /home/proxyuser/.ssh/authorized_keys 2>/dev/null || echo "No client keys found or cat failed"
    chmod 600 /home/proxyuser/.ssh/authorized_keys
else
    echo "WARNING: /etc/ssh/client_keys not found."
fi

# 2. Setup Outbound Identity (Private Key)
if [ -f "/etc/ssh/server_keys/id_rsa" ]; then
    echo "Importing outbound private key..."
    cp /etc/ssh/server_keys/id_rsa /home/proxyuser/.ssh/id_rsa
    chmod 600 /home/proxyuser/.ssh/id_rsa
else
    echo "WARNING: /etc/ssh/server_keys/id_rsa not found."
fi

# Fix permissions
chown -R proxyuser:proxyuser /home/proxyuser/.ssh

# 3. Configure SSHD
sed -i 's/#Port 22/Port 3141/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/#AllowTcpForwarding yes/AllowTcpForwarding yes/' /etc/ssh/sshd_config
ssh-keygen -A

echo "Starting SSHD..."
exec /usr/sbin/sshd -D -e
