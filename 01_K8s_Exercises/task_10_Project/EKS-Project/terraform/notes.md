Installing eksctl

```powershell as admin
choco install eksctl -y
```

Verify

```powershell
eksctl version
```

Create EKS Cluster using eksctl

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

Verify Cluster is ACTIVE or NOT

```bash
aws eks describe-cluster \
  --region ap-south-1 \
  --name my-eks-cluster \
  --query 'cluster.status'
```

Check addons present

```bash
eksctl get addons --cluster my-eks-cluster --region ap-south-1
```

After EKS

> VPC CNI → EKS Pod Identity → EBS CSI → AWS Load Balancer Controller

EBS CSI Driver

```bash
eksctl create addon \
  --cluster my-eks-cluster \
  --region ap-south-1 \
  --name aws-ebs-csi-driver \
  --force
```

EKS Pod Identity Agent → worker nodes
The Pod Identity Agent runs on your worker nodes as a Kubernetes DaemonSet.

EKS

```bash
eksctl create addon \
  --region ap-south-1 \
  --cluster my-eks-cluster \
  --name eks-pod-identity-agent
```

EKS Pod Identity Association → EKS/AWS control plane configuration

If you use --role-name, eksctl treats it as a role it needs to create/manage, which is why your earlier command complained about needing permission policies.

```bash
eksctl create podidentityassociation \
  --region ap-south-1 \
  --cluster my-eks-cluster \
  --namespace default \
  --service-account-name default-sa \
  --role-name example-role \
  --permission-policy-arns []
```

For Role User created already, just provide ARN

> This is for `google-microservice` Project

```bash
eksctl create podidentityassociation \
  --region ap-south-1 \
  --cluster my-eks-cluster \
  --namespace google-microservice \
  --service-account-name google-microservice-sa \
  --role-arn arn:aws:iam::025066281843:role/eks-pod-identity-demo-role
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
