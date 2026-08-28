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
✓ PDB - one per HPA service (minAvailable: 1)
✓ Ingress/network architecture - frontend only, single ingress resource
✓ RoleBindings
✓ PSA namespace label
✓ Rolling update
✓ Anti-affinity - added to all 8 HPA services
✓ 
✓ 
✓ 
✓ 
✓ 

---

Remaining Checklist:

Larger efforts:
□ Helm                  - package all manifests into a chart
□ Observability         - Prometheus + Grafana + alerts
□ CI/CD                 - GitHub Actions / ArgoCD
□ EKS integration       - IAM, IRSA, ALB controller, Secrets Manager
□ Image sig verification - Kyverno verifyImages (Cosign) - left as TODO in kyverno-policies.yml
