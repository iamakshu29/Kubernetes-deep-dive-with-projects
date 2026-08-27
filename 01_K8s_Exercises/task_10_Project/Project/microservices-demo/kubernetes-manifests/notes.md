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
✓ Resource audit - Will be in-process as we level up


→ Next:
PDB
Ingress/network architecture

Observability
CI/CD
Container/image security
EKS integration

---

Remaining Checklist:

Short (do first):
□ RoleBindings          - roleBinding.yml is still empty
□ PSA namespace label   - add pod-security.kubernetes.io/enforce: restricted to namespace.yml
□ Rolling update        - add maxUnavailable + maxSurge to all Deployments
□ Anti-affinity         - add to all HPA services (minReplicas:2 needs pods on different nodes)
□ Topology spread       - complement to anti-affinity for zone-level spreading
□ Secrets               - move sensitive values out of ConfigMaps into Secrets

Medium:
□ PDB                   - one per HPA service (minAvailable: 1)
□ Ingress               - frontend only, single ingress resource

Larger efforts:
□ Helm                  - package all manifests into a chart
□ Observability         - Prometheus + Grafana + alerts
□ CI/CD                 - GitHub Actions / ArgoCD
□ EKS integration       - IAM, IRSA, ALB controller, Secrets Manager
□ Image sig verification - Kyverno verifyImages (Cosign) - left as TODO in kyverno-policies.yml
