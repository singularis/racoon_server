
set -e

if [ "$(id -u)" != "0" ]; then
  echo "Please run this script as root (or via sudo)."
  exit 1
fi

echo ">>> Checking if ansible is installed..."
if ! command -v ansible >/dev/null 2>&1; then
  echo ">>> Ansible is not installed. Installing..."

  # Install dependencies
  apt-get update -y
  apt-get install -y \
    software-properties-common \
    python3 \
    python3-pip \
    python3-apt

  apt-add-repository --yes --update ppa:ansible/ansible
  apt-get install -y ansible
else
  echo ">>> Ansible is already installed."
fi
echo ">>> Running Ansible playbook: init.yaml ..."
ansible-playbook init.yaml
