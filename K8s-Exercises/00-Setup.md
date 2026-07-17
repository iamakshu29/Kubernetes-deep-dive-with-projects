# K8s Environment Setup Guide

> **Different tasks need different environments.** This guide explains all your options clearly and maps each task to the right cluster type. There is no single "do this once" setup.

---

## Cluster Options at a Glance

| Option                             | Cost                    | Best For                        | Persistent?              | Setup Time        |
| ------------------------------------| -------------------------| ---------------------------------| --------------------------| -------------------|
| **A — kind** (Docker-based, local) | Free                    | Tasks 01–05                     | Yes (until Docker stops) | 5 min             |
| **B — Oracle Cloud Free Tier**     | Always free             | Tasks 06–08, Final Project      | Yes (always running)     | 30 min once       |
| **C — AWS EC2 + Terraform**        | ~$0.30–0.50 per session | Tasks 07–08 (cloud experience)  | Per session              | 8 min per session |
| **D — Multipass** (local VMs)      | Free                    | Tasks 01–05, 07                 | Yes (start/stop VMs)     | 15 min once       |
| **Killercoda** (browser)           | Free                    | Tasks 01–05 (no install at all) | No (4hr sessions)        | 0 min             |

---

## Task → Cluster Mapping (Read This First)

| Task                      | What You Need                       | Use This                                          |
| ---------------------------| -------------------------------------| ---------------------------------------------------|
| Task 01 — Namespaces      | Single-node cluster                 | kind single-node **or** Killercoda                |
| Task 02 — Workloads       | 2-node + metrics-server             | kind 2-node (see Option A below)                  |
| Task 03 — Networking      | 2-node + **Calico CNI**             | kind + Calico (see Option A below)                |
| Task 04 — Storage         | 2-node, node-failure simulation     | kind 2-node for most; Oracle/AWS for node-failure |
| Task 05 — RBAC            | Single-node                         | kind or Killercoda                                |
| Task 06 — Observability   | 3-node, 6GB+ RAM                    | **Oracle Free Tier** (Prometheus stack is heavy)  |
| Task 07 — Troubleshooting | 2-node, real node stop              | **Oracle Free Tier** or **AWS**                   |
| Task 08 — Final Project   | Multi-node, persistent across weeks | **Oracle Free Tier** or **AWS**                   |

---

## Option A — kind (Recommended for Tasks 01–05)

kind (Kubernetes in Docker) runs K8s nodes as Docker containers on your laptop. It is free, fast, and real — not a simulation. This is the right tool for the first five tasks.

**Requirement:** Docker Desktop installed and running on Windows. [Download here](https://www.docker.com/products/docker-desktop/)

### Install kind on Windows

```powershell
# With Chocolatey
choco install kind

# Or direct binary
curl.exe -Lo kind.exe https://kind.sigs.k8s.io/dl/v0.23.0/kind-windows-amd64 # or the latest you want
Move-Item .\kind.exe C:\Windows\kind.exe

kind version   # verify
```

Install kubectl (if not already installed):
```powershell
choco install kubernetes-cli
kubectl version --client
```

Install Helm (if not already installed):
```powershell
choco install kubernetes-helm
```
---

### A1 — Standard 2-node cluster (Tasks 01, 02, 04, 05)

Save this as `kind-2node.yaml` in your working directory:

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    kubeadmConfigPatches:
    - |
      kind: InitConfiguration
      nodeRegistration:
        kubeletExtraArgs:
          node-labels: "ingress-ready=true"
    extraPortMappings:
    - containerPort: 80
      hostPort: 80
      protocol: TCP
    - containerPort: 443
      hostPort: 443
      protocol: TCP
  - role: worker
```

```bash
kind create cluster --name devops-lab --config kind-2node.yaml
kubectl cluster-info --context kind-devops-lab # To get cluster-info
kubectl get nodes   # expect: 1 control-plane + 1 worker, both Ready
```

**Install add-ons once (needed for Tasks 02 onwards):**

```bash
# Ingress Controller (Task 03 onwards)
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

# Metrics Server (required for HPA in Task 02)
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Patch metrics-server to work inside kind (disables TLS verification for local cluster only)
kubectl patch deployment metrics-server -n kube-system \
  --type='json' \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

# Verify
kubectl get nodes
kubectl get pods -n ingress-nginx
kubectl top nodes   # wait ~60 sec after metrics-server install
```

---

### A2 — kind with Calico CNI (Task 03 — NetworkPolicies)

**Why this matters:** kind's default networking (kindnet) does NOT enforce NetworkPolicies. If you apply a NetworkPolicy with the default setup, it looks like it works but traffic is never actually blocked. For Task 03's zero-trust networking exercises, you must use Calico.

Save as `kind-calico.yaml`:

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  disableDefaultCNI: true
  podSubnet: "192.168.0.0/16"
nodes:
  - role: control-plane
    extraPortMappings:
    - containerPort: 80
      hostPort: 80
      protocol: TCP
    - containerPort: 443
      hostPort: 443
      protocol: TCP
  - role: worker
```

```bash
kind create cluster --name calico-lab --config kind-calico.yaml

# Install Calico CNI
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml

# Wait ~2 minutes for Calico pods to start
kubectl get nodes         # both Ready
kubectl get pods -n calico-system
```

---

### kind daily workflow

```bash
kind get clusters                            # list all kind clusters
kubectl config get-contexts                  # see available contexts

# Switch between clusters
kubectl config use-context kind-devops-lab
kubectl config use-context kind-calico-lab

# Delete and recreate (clean start for a task)
kind delete cluster --name devops-lab
kind create cluster --name devops-lab --config kind-2node.yaml

# Note: kind clusters stop if Docker Desktop restarts
# Recreating takes under 2 minutes — your practice YAML is in files, nothing is lost
```

---

## Option B — Oracle Cloud Free Tier (Recommended for Tasks 06–08)

**Always free. No card charged after signup.** You get 2 ARM VMs with 4 OCPUs + 24GB RAM total — real Linux servers, not containers. This is what companies use. Persistent — your cluster is there when you come back next week.

This is the right environment for the heavy tasks: Prometheus, Grafana, ArgoCD, etcd backup, node management, the final project.

### One-Time Account Setup

1. Create account: https://www.oracle.com/cloud/free/
   - A credit card is required to sign up, but free-tier VMs are never charged
   - Choose a region near you (e.g., `ap-mumbai-1` for India)

2. Create 2 VMs in the OCI console:
   - Shape: `VM.Standard.A1.Flex` (ARM — this is the always-free shape)
   - OCPUs: 2 each | RAM: 12GB each (4 OCPU + 24GB total = free tier limit)
   - OS: Ubuntu 22.04
   - Create and download an SSH key pair during setup

3. Open firewall ports in your VCN Security List:
   - `22` (SSH), `6443` (K8s API), `2379-2380` (etcd), `10250` (kubelet), `80`, `443`

---

### Install K8s (run on BOTH VMs)

SSH into each VM and run:

```bash
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl containerd
sudo apt-mark hold kubelet kubeadm kubectl

sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd && sudo systemctl enable containerd

sudo swapoff -a && sudo sed -i '/ swap / s/^/#/' /etc/fstab

sudo modprobe overlay && sudo modprobe br_netfilter
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system
```

### Initialize cluster (control-plane VM only)

```bash
# Replace <CONTROL_PLANE_PRIVATE_IP> with the VM's private IP (shown in OCI console)
sudo kubeadm init --pod-network-cidr=192.168.0.0/16 --apiserver-advertise-address=<CONTROL_PLANE_PRIVATE_IP>

mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Install Calico CNI
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml

# The init output shows a kubeadm join command — copy it for the worker
```

### Join the worker node

```bash
# SSH into the worker VM, run the join command from the control-plane init output
sudo kubeadm join <CONTROL_PLANE_PRIVATE_IP>:6443 --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash>
```

### Access from your Windows machine

On the control-plane VM:
```bash
cat $HOME/.kube/config
```

Copy the content to `C:\Users\<you>\.kube\config` on Windows. Change the `server:` value to use the control-plane VM's **public IP**.

```
kubectl get nodes   # verify from Windows
```

---

## Option C — AWS EC2 with Terraform (Cloud Experience Path)

**Use this if:** You specifically want AWS on your resume, or you are practicing real cloud infrastructure skills alongside K8s.

### Honest Comparison — AWS vs Oracle Free Tier

| Factor | AWS EC2 | Oracle Free Tier |
|--------|---------|-----------------|
| Cost | ~$0.30–0.50 per working session | **$0 always** |
| Resume value | AWS is more recognised | Still valuable (OCI) |
| Setup per session | `terraform apply` (~8 min) | Already running — SSH in |
| Real cloud experience | ✅ VPCs, Security Groups, EBS | ✅ VCN, OCI VMs |
| Node stop simulation | ✅ Stop EC2 from console/CLI | ✅ Stop VM from OCI console |
| etcd access | ✅ SSH into control-plane | ✅ SSH into control-plane |

**Recommendation:** Oracle Free Tier for learning (zero cost, always ready). Use AWS if you want to practice Terraform + cloud infra together, or specifically need AWS for a job.

### Terraform Files for AWS

Save these in a folder named `k8s-aws/` on your machine.

**`variables.tf`:**
```hcl
variable "aws_region" {
  default = "ap-south-1"
}

variable "master_instance_type" {
  # t3.medium (2 vCPU, 4GB) — good for Tasks 01-07
  # Use t3.large (8GB) for Task 06/08 with Prometheus+Grafana
  default = "t3.medium"
}

variable "worker_instance_type" {
  default = "t3.small"
}

variable "ssh_public_key_path" {
  default = "~/.ssh/id_rsa.pub"
}

variable "your_ip_cidr" {
  description = "Your public IP in CIDR format — e.g. 203.0.113.10/32. Find it: curl ifconfig.me"
}
```

**`main.tf`:**
```hcl
terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter { name = "name",               values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"] }
  filter { name = "virtualization-type", values = ["hvm"] }
}

resource "aws_key_pair" "k8s_key" {
  key_name   = "k8s-lab-key"
  public_key = file(var.ssh_public_key_path)
}

resource "aws_security_group" "k8s_sg" {
  name        = "k8s-lab-sg"
  description = "K8s lab cluster security group"

  ingress { from_port = 22;   to_port = 22;   protocol = "tcp"; cidr_blocks = [var.your_ip_cidr] }
  ingress { from_port = 6443; to_port = 6443; protocol = "tcp"; cidr_blocks = [var.your_ip_cidr] }
  ingress { from_port = 80;   to_port = 80;   protocol = "tcp"; cidr_blocks = ["0.0.0.0/0"] }
  ingress { from_port = 443;  to_port = 443;  protocol = "tcp"; cidr_blocks = ["0.0.0.0/0"] }
  # Allow all traffic within the security group (inter-node communication)
  ingress { from_port = 0; to_port = 0; protocol = "-1"; self = true }
  egress  { from_port = 0; to_port = 0; protocol = "-1"; cidr_blocks = ["0.0.0.0/0"] }
}

resource "aws_instance" "k8s_master" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.master_instance_type
  key_name               = aws_key_pair.k8s_key.key_name
  vpc_security_group_ids = [aws_security_group.k8s_sg.id]
  user_data              = file("user-data-master.sh")

  root_block_device { volume_size = 20; volume_type = "gp3" }
  tags = { Name = "k8s-master", Role = "control-plane" }
}

resource "aws_instance" "k8s_worker" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.worker_instance_type
  key_name               = aws_key_pair.k8s_key.key_name
  vpc_security_group_ids = [aws_security_group.k8s_sg.id]
  user_data              = file("user-data-worker.sh")

  root_block_device { volume_size = 20; volume_type = "gp3" }
  tags = { Name = "k8s-worker1", Role = "worker" }
}
```

**`outputs.tf`:**
```hcl
output "master_public_ip" { value = aws_instance.k8s_master.public_ip }
output "worker_public_ip" { value = aws_instance.k8s_worker.public_ip }
output "ssh_master"       { value = "ssh -i ~/.ssh/id_rsa ubuntu@${aws_instance.k8s_master.public_ip}" }
output "ssh_worker"       { value = "ssh -i ~/.ssh/id_rsa ubuntu@${aws_instance.k8s_worker.public_ip}" }
```

**`user-data-master.sh`** (runs automatically at first boot):
```bash
#!/bin/bash
set -e
exec > /var/log/k8s-bootstrap.log 2>&1

apt-get update
apt-get install -y apt-transport-https ca-certificates curl gpg containerd

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | \
  gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | \
  tee /etc/apt/sources.list.d/kubernetes.list

apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd && systemctl enable containerd

swapoff -a && sed -i '/ swap / s/^/#/' /etc/fstab
modprobe overlay && modprobe br_netfilter
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system

# Use private IP for K8s API server
PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
kubeadm init --pod-network-cidr=192.168.0.0/16 --apiserver-advertise-address=$PRIVATE_IP

mkdir -p /home/ubuntu/.kube
cp /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
chown ubuntu:ubuntu /home/ubuntu/.kube/config

kubectl --kubeconfig=/home/ubuntu/.kube/config apply -f \
  https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml

# Save join command for the worker node
kubeadm token create --print-join-command > /home/ubuntu/worker-join.sh
chown ubuntu:ubuntu /home/ubuntu/worker-join.sh
echo "Master bootstrap complete. Join command: ~/worker-join.sh"
```

**`user-data-worker.sh`** (installs prerequisites; you run the join command manually):
```bash
#!/bin/bash
set -e
exec > /var/log/k8s-bootstrap.log 2>&1

apt-get update
apt-get install -y apt-transport-https ca-certificates curl gpg containerd

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | \
  gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | \
  tee /etc/apt/sources.list.d/kubernetes.list

apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd && systemctl enable containerd

swapoff -a && sed -i '/ swap / s/^/#/' /etc/fstab
modprobe overlay && modprobe br_netfilter
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system
echo "Worker prerequisites installed. SSH in and run the join command from the master."
```

### AWS Session Workflow

```bash
# --- Start a session (~8 min to a running cluster) ---
cd k8s-aws
terraform apply -var="your_ip_cidr=$(curl -s ifconfig.me)/32" -auto-approve
terraform output   # get IPs

# Wait ~5 min for user-data to finish running on the master
ssh -i ~/.ssh/id_rsa ubuntu@<master_public_ip>
cat ~/worker-join.sh   # copy this join command

# On the worker
ssh -i ~/.ssh/id_rsa ubuntu@<worker_public_ip>
sudo bash -c "$(ssh ubuntu@<master_ip> 'cat ~/worker-join.sh')"

# Get kubeconfig to your Windows machine
# Copy master ~/.kube/config to C:\Users\<you>\.kube\config
# Replace server IP with master_public_ip

# --- Do your K8s work ---
kubectl get nodes   # both Ready

# --- End a session (destroys EC2 — saves cost) ---
terraform destroy -var="your_ip_cidr=$(curl -s ifconfig.me)/32" -auto-approve
# Your YAML files and Helm charts are in Git — nothing K8s-related is lost
```

**Estimated cost:** 2 instances for 4 hours = ~$0.40. Running 3 sessions per week = ~$5/month maximum.

---

## Option D — Multipass (When It Works — Local VMs)

Multipass runs real Ubuntu VMs on Windows. It is equivalent to Oracle Free Tier for learning but runs locally. Good option if you want it — but currently giving you errors.

### Common Multipass Errors and Fixes

| Error | Fix |
|-------|-----|
| `Hypervisor not found` | Enable Hyper-V: open "Turn Windows features on/off" → enable Hyper-V. Requires Windows Pro/Enterprise. |
| `failed to launch instance` | Install VirtualBox, then run: `multipass set local.driver=virtualbox` |
| `WSL2 error` | Try switching backend: `multipass set local.driver=hyperv` (run PowerShell as Admin) |
| Network/port errors | Run as Administrator: `netsh winsock reset` → restart Windows |

Until Multipass is fixed, use **kind** for Tasks 01-05 and **Oracle Free Tier** for Tasks 06-08. You are not missing anything — the experience is equivalent.

When Multipass is working, the setup is identical to Option B (kubeadm bootstrap script). Reference the `multipass shell k8s-master` command instead of SSH.

---

## Quick Decision — What to Use Right Now

```
Starting today, want to begin immediately?
  └─▶ Option A (kind): kind create cluster → open Task 01 in 5 minutes

Need Prometheus / ArgoCD / etcd for Tasks 06-08?
  └─▶ Option B (Oracle Free Tier): one-time 30-min setup, free forever

Want real AWS cloud experience on your resume?
  └─▶ Option C (AWS + Terraform): terraform apply → cluster in 8 min, ~$0.40/session

Need to simulate a node going NotReady (Task 07)?
  └─▶ Oracle: stop VM from OCI console
       AWS: aws ec2 stop-instances --instance-ids <worker-id>
       Multipass (if working): multipass stop k8s-worker1

Just want to try something quickly with zero install?
  └─▶ Killercoda (browser): https://killercoda.com → Kubernetes Playground
```

---

## Images to Use Across All Exercises

| Role | Image |
|------|-------|
| Backend API | `hashicorp/http-echo` |
| Frontend | `nginx:alpine` |
| Database | `postgres:15` or `redis:7` |
| Debug / curl inside pods | `busybox` or `alpine` |

---

*Next: Open `Task-01-Namespaces-and-Context.md`. Come back here when a task says it needs a different cluster type.*
