```bash
eksctl create cluster \
  --name my-eks-cluster \
  --region ap-south-1 \
  --nodegroup-name my-nodes \
  --node-type t3.medium \
  --nodes 2 \
  --nodes-min 1 \
  --nodes-max 3 \
  --managed
```

AFter EKS

> VPC CNI → EKS Pod Identity → EBS CSI → AWS Load Balancer Controller

EKS Pod Identity Agent → worker nodes
The Pod Identity Agent runs on your worker nodes as a Kubernetes DaemonSet.

EKS

```bash
eksctl create addon \
  --cluster my-eks-cluster \
  --name eks-pod-identity-agent
```

EKS Pod Identity Association → EKS/AWS control plane configuration

```bash
eksctl create podidentityassociation \
  --cluster my-eks-cluster \
  --namespace backend \
  --service-account-name backend-sa \
  --role-name backend-s3-role
```

Pod Identity Agent = worker-node component.
Pod Identity Association = EKS/AWS-side configuration connecting a ServiceAccount to an IAM role.

```
EKS
│
├── AWS-managed control plane
│
└── Managed Node Group
    ├── t3.medium
    └── 2 nodes initially
         ├── min: 1
         └── max: 3
```

THEN

```bash
aws eks update-kubeconfig \
  --region ap-south-1 \
  --name my-eks-cluster
```

VERIFY

```bash
kubectl get nodes
kubectl get pods -A
```

RUN

```bash
eksctl get cluster
```

DELETE

```bash
eksctl delete cluster \
  --name my-eks-cluster \
  --region ap-south-1
```
