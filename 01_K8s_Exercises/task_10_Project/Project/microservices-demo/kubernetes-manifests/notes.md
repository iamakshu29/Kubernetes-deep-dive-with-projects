k8s/
├── namespace/
│ └── namespace.yaml
│
├── policies/
│ ├── resource-quota.yaml
│ ├── limit-range.yaml
│ └── network-policy.yaml
│
├── rbac/
│ ├── service-accounts/
│ │ ├── devops-admin.yaml
│ │ ├── deployer.yaml
│ │ ├── app.yaml
│ │ └── readonly.yaml
│ │
│ ├── roles/
│ │ ├── devops-admin.yaml
│ │ ├── deployer.yaml
│ │ └── readonly.yaml
│ │
│ └── role-bindings/
│ ├── devops-admin.yaml
│ ├── deployer.yaml
│ └── readonly.yaml
│
├── services/
│ ├── service-a/
│ │ ├── deployment.yaml
│ │ ├── service.yaml
│ │ ├── configmap.yaml
│ │ ├── hpa.yaml
│ │ └── pdb.yaml
│ │
│ ├── service-b/
│ │ ├── deployment.yaml
│ │ ├── service.yaml
│ │ ├── configmap.yaml
│ │ └── hpa.yaml
│ │
│ └── service-c/
│ ├── deployment.yaml
│ └── service.yaml
│
└── ingress/
└── ingress.yaml

---

Developer manifests
│
│ hard-coded environment variables
↓
Audit them
│
├── non-sensitive → ConfigMap
│
└── sensitive → Secret
│
↓
Later on EKS:
AWS Secrets Manager

---

Also look at:

replica count
rolling update strategy
maxUnavailable
maxSurge
PodDisruptionBudget
topology spread constraints
anti-affinit

---

✓ Namespace
✓ ResourceQuota
✓ LimitRange
✓ ServiceAccounts - Left as per specific Service
✓ Roles
✓ RoleBindings
✓ ConfigMaps
✓ NetworkPolicies
✓ HPA
✓ Kyverno Policies (LEFT - Add image signature verification policy)
Pod security audit - Done Already (LEFT- Namespace Labelling left)

→ Next:
Resource audit
HPA audit
PDB
Ingress/network architecture

Observability
CI/CD
Container/image security
EKS integration
