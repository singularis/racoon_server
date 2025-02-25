---
- name: Configure System
  hosts: all
  become: true
  pre_tasks:
    - name: Create directories
      file:
        path: "{{ item }}"
        state: directory
        mode: '0755'
      loop:
        - /etc/kubernetes/manifests
        - /var/lib/kubelet

    - name: Set up SSH key for root user
      authorized_key:
        user: root
        key: "ssh-rsa AAAAB3NzaC1yc2E... (your public key here)"

  roles:
    - repository-setup
    - docker
    - kubernetes
    - hashicorp

  tasks:
    - name: Install required packages
      apt:
        pkg:
          - docker.io
          - containerd
          - kubelet
          - kubeadm
          - kubectl
          - nomad
          - vault
        state: present
        update_cache: yes

    - name: Enable and start Docker
      systemd:
        name: docker
        enabled: true
        state: started

    - name: Enable and start kubelet
      systemd:
        name: kubelet
        enabled: true
        state: started

    - name: Set up SSH access for Kubernetes
      lineinfile:
        path: /etc/ssh/sshd_config
        line: "AuthorizedKeysFile .ssh/authorized_keys"
        state: present

    - name: Ensure SSH service is running
      systemd:
        name: ssh
        enabled: true
        state: started

    - name: Install Python dependencies
      pip:
        name:
          - ansible
          - docker
          - kubernetes
        state: latest
#!/bin/bash
set -e

echo "=== Cleaning APT repositories and updating keys ==="

# Create directories for keyrings if they do not exist.
sudo mkdir -p /etc/apt/keyrings
sudo mkdir -p /usr/share/keyrings

#############################
# 1. Docker Repository Setup
#############################
echo ">> Updating Docker GPG key..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Update or create the Docker sources list file.
DOCKER_LIST="/etc/apt/sources.list.d/docker.list"
DOCKER_ENTRY="deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu noble stable"
if [ -f "$DOCKER_LIST" ]; then
    echo ">> Updating existing Docker sources file..."
    sudo sed -i "s|deb https://download.docker.com/linux/ubuntu|$DOCKER_ENTRY|g" "$DOCKER_LIST"
else
    echo ">> Creating Docker sources file..."
    echo "$DOCKER_ENTRY" | sudo tee "$DOCKER_LIST" > /dev/null
fi

###############################
# 2. HashiCorp Repository Setup
###############################
echo ">> Updating HashiCorp GPG key..."
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

# Update or create the HashiCorp sources list file.
HASHICORP_LIST="/etc/apt/sources.list.d/hashicorp.list"
HASHICORP_ENTRY="deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com noble main"
if [ -f "$HASHICORP_LIST" ]; then
    echo ">> Updating existing HashiCorp sources file..."
    sudo sed -i "s|deb https://apt.releases.hashicorp.com|$HASHICORP_ENTRY|g" "$HASHICORP_LIST"
else
    echo ">> Creating HashiCorp sources file..."
    echo "$HASHICORP_ENTRY" | sudo tee "$HASHICORP_LIST" > /dev/null
fi

####################################
# 3. Kubernetes Repository Setup
####################################
echo ">> Removing expired Kubernetes key..."
# Remove the expired key. If it does not exist, the command will output an error which we ignore.
sudo apt-key del 234654DA9A296436 || echo "Expired key not found or already removed."

echo ">> Updating Kubernetes GPG key..."
# NOTE: Replace the URL below with the official updated Kubernetes key URL if different.
KUBE_KEY_URL="https://packages.cloud.google.com/apt/doc/apt-key.gpg"
curl -fsSL "$KUBE_KEY_URL" | sudo gpg --dearmor -o /usr/share/keyrings/kubernetes-archive-keyring.gpg

# Update or create the Kubernetes sources list file.
KUBE_LIST="/etc/apt/sources.list.d/kubernetes.list"
KUBE_ENTRY="deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://prod-cdn.packages.k8s.io/repositories/isv:/kubernetes:/addons:/cri-o:/stable:/v1.30/deb noble main"
if [ -f "$KUBE_LIST" ]; then
    echo ">> Updating existing Kubernetes sources file..."
    sudo sed -i "s|deb https://prod-cdn.packages.k8s.io/repositories/isv:/kubernetes:/addons:/cri-o:/stable:/v1.30/deb|$KUBE_ENTRY|g" "$KUBE_LIST"
else
    echo ">> Creating Kubernetes sources file..."
    echo "$KUBE_ENTRY" | sudo tee "$KUBE_LIST" > /dev/null
fi

#############################
# 4. Update Package Index
#############################
echo ">> Updating package index..."
sudo apt update

echo "=== Repository cleaning and key updates completed successfully. ==="
