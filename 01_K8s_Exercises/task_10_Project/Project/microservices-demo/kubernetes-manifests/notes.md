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

X Helm - package all manifests into a chart
X Observability - Prometheus + Grafana + alerts
X CI/CD - GitHub Actions / ArgoCD
X EKS integration - IAM, IRSA, ALB controller, Secrets Manager
X Image sig verification - Kyverno verifyImages (Cosign) - left as TODO in kyverno-policies.yml