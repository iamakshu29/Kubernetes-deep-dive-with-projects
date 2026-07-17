# K8s Hands-On Setup — Before You Start Any Task

> Do this ONCE. Every exercise in this series runs on this environment.

---

## What You Are Building

```
[Your Laptop]
  └── Multipass
        ├── k8s-master   (2 CPU, 2GB RAM) — Control Plane
        └── k8s-worker1  (1 CPU, 2GB RAM) — Worker Node
```

This is a real 2-node cluster using kubeadm — not a simulation. You will manage it the same way a DevOps engineer does at a company.

---

## Step 1 — Install Multipass

Multipass gives you lightweight real Ubuntu VMs on Windows without Hyper-V complexity.

Download: https://multipass.run/install

Verify after install:
```
multipass version
```

---

## Step 2 — Launch VMs

Run these one at a time. Wait for each to finish.

```
multipass launch 22.04 --name k8s-master  --cpus 2 --memory 2G --disk 20G
multipass launch 22.04 --name k8s-worker1 --cpus 1 --memory 2G --disk 20G
```

Check both are running:
```
multipass list
```

---

## Step 3 — Install K8s on Both Nodes

Shell into master first:
```
multipass shell k8s-master
```

Inside the VM, run this script — it installs containerd + kubeadm + kubelet + kubectl:

```bash
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# Install containerd
sudo apt-get install -y containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

# Disable swap (K8s requirement)
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Enable required kernel modules
sudo modprobe overlay
sudo modprobe br_netfilter
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system
```

Exit the VM and repeat the exact same steps on `k8s-worker1`:
```
multipass shell k8s-worker1
# run the same script above
```

---

## Step 4 — Initialize the Cluster (Master Only)

Shell into master:
```
multipass shell k8s-master
```

Run:
```bash
sudo kubeadm init --pod-network-cidr=192.168.0.0/16
```

After it finishes, you will see a `kubeadm join ...` command at the bottom. **Copy it — you need it in Step 5.**

Set up kubectl access on master:
```bash
mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

Install Calico CNI (networking plugin — pods cannot communicate without this):
```bash
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml
```

Wait ~60 seconds, then confirm nodes are Ready:
```bash
kubectl get nodes
```

---

## Step 5 — Join the Worker Node

Shell into worker1:
```
multipass shell k8s-worker1
```

Paste the `kubeadm join` command you copied from Step 4 with `sudo`:
```bash
sudo kubeadm join <master-ip>:6443 --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash>
```

Back on master, verify:
```bash
kubectl get nodes
# Both nodes should show STATUS: Ready
```

---

## Step 6 — Access Cluster From Your Windows Machine (Optional)

On master, print the kubeconfig:
```bash
cat $HOME/.kube/config
```

Copy the content to `C:\Users\<you>\.kube\config` on Windows.

Replace the `server:` IP with the master VM's IP (get it with `multipass list`).

Install kubectl on Windows: https://kubernetes.io/docs/tasks/tools/install-kubectl-windows/

Test:
```
kubectl get nodes
```

---

## Your Cluster is Ready

You now have the same setup a DevOps engineer uses when:
- Setting up a dev/staging cluster
- Onboarding a new team environment
- Practicing before touching production

**Next: Open Task-01-Namespaces-and-Context.md and start exercising.**

---

## Quick Reference — Multipass Commands

```
multipass list                        # see all VMs and their IPs
multipass shell k8s-master            # SSH into master
multipass shell k8s-worker1           # SSH into worker
multipass stop k8s-master k8s-worker1 # stop VMs (saves RAM)
multipass start k8s-master k8s-worker1# resume VMs
multipass delete k8s-master           # delete VM
multipass purge                       # permanently remove deleted VMs
```

> Stop VMs when not using them. They consume RAM even idle.
