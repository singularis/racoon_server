# Kubernetes Infrastructure Automation

Ansible-based Kubernetes cluster deployment and configuration management for production workloads.

## Project Structure

```
.
├── main.yaml                   # Main playbook entry point
├── vars.yaml                   # Global configuration variables
├── server_configration/        # Base server setup
├── kube_configration/          # Kubernetes cluster configuration
├── workload/                   # Application workload deployments
├── monitoring/                 # Monitoring stack deployment
├── inventory/                  # Ansible inventory files
├── worker_node/               # Worker node specific configurations
├── gpu-node/                  # GPU node configurations
└── update.sh                  # System maintenance script
```

## Infrastructure Components

### Core Infrastructure
- **Kubernetes Master**: 192.168.0.10
- **Worker Node**: 192.168.0.11
- **Pod Network**: 10.244.0.0/16
- **Load Balancer**: MetalLB

### Storage Services
- **Nextcloud**: 192.168.0.140 (1700GB volume)
- **Samba**: 192.168.0.120
- **PostgreSQL**: Multi-tenant database
- **Redis**: 192.168.0.110

### Monitoring Stack
- **Prometheus**: 192.168.0.150
- **Grafana**: 192.168.0.160
- **ELK Stack**: 192.168.0.18
- **Beats Collector**: Log aggregation

### Development Tools
- **Jenkins**: 192.168.0.102 (20GB volume)
- **Jira**: 192.168.0.103 (20GB volume)
- **OpenWebUI**: 192.168.0.101 (10GB volume)
- **pgAdmin**: Database administration

### Infrastructure Services
- **Pi-hole DNS**: 192.168.0.91-92
- **Harbor Registry**: Container registry
- **Kubernetes Dashboard**: Cluster management UI
- **Temporal**: 192.168.0.51-52

### Message Queue
- **Apache Kafka**: Distributed streaming platform
- **Kafka UI**: Management interface

### External Access
- **Ngrok**: Secure tunneling
  - chater.singularis.work
  - jenkins.singularis.work
- **VPN Gateway**: Secure remote access

## System Requirements

### Host System
- Ubuntu Server Linux 6.8.0-62
- Docker Runtime
- containerd
- KVM Hypervisor
- Minimum 32GB RAM
- 2TB+ storage

### Network Configuration
- Static IP assignment
- DNS resolution via Pi-hole
- Load balancer IP range allocation

## Installation

### Prerequisites
```bash
# Install Ansible
apt-get update
apt-get install -y ansible

# Clone repository
git clone <repository-url>
cd racoon_server
```

### Configuration
1. Edit `vars.yaml` with environment-specific values
2. Update `inventory/` files with target hosts
3. Configure SSH key-based authentication

### Deployment
```bash
# Full deployment
ansible-playbook main.yaml

# Specific component deployment
ansible-playbook server_configration/basic_server_setup.yaml
ansible-playbook kube_configration/kuberentes_setup.yaml
ansible-playbook workload/workload_setup.yaml
ansible-playbook monitoring/monitoring_setup.yaml
```

### Post-Installation
```bash
# Configure kubectl
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Join worker nodes
kubeadm join 192.168.0.10:6443 --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash>
```

## Maintenance

### System Updates
```bash
# Run maintenance script
sudo ./update.sh
```

### Backup Procedures
- Database backups: PostgreSQL automated backups
- Volume snapshots: Persistent volume snapshots
- Configuration backup: Git repository

### Monitoring
- Prometheus metrics collection
- Grafana dashboards
- ELK log aggregation
- Alert manager notifications

## Security

### Network Security
- Firewall rules configured
- Network policy enforcement
- TLS/SSL certificates (cert-manager)

### Access Control
- RBAC implementation
- Service account management
- Secret management

### Authentication
- Password encryption: pbkdf2:sha256
- Token-based authentication
- Multi-factor authentication support

## Troubleshooting

### Common Issues
- Pod network connectivity: Check CNI configuration
- Load balancer IP conflicts: Verify MetalLB configuration
- DNS resolution: Check Pi-hole configuration
- Certificate issues: Verify cert-manager status

### Log Locations
- Kubernetes logs: `/var/log/kubernetes/`
- Application logs: ELK stack aggregation
- System logs: `/var/log/syslog`

## Architecture Diagram

The complete infrastructure architecture is shown in the diagram above, illustrating the relationships between components, network topology, and service dependencies.

## Version Information

- Kubernetes: Latest stable
- Docker: Latest stable
- Ansible: Latest stable
- Operating System: Ubuntu Server Linux 6.8.0-62