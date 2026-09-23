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
✓ Helm - package all manifests into a chart
X Observability - Prometheus + Grafana + alerts
X ArgoCD - Not Required Here
X EKS integration - IAM, EKS Pod Identity, ALB controller, Secrets Manager

```
without app-side /metrics endpoints configured, Prometheus can only scrape what kube-prometheus-stack provides out of the box. But that's actually quite a lot:

What's available without any app changes:

Source	Metrics
cAdvisor (kubelet)	Container CPU/memory usage, throttling
node_exporter	Node CPU, memory, disk, network
kube-state-metrics	Pod status, restart count, deployment replicas, HPA status
API server	Request latency, errors (infra-level)
Useful alerts you can write with these:

Pod CPU throttling — container being throttled → resource limits too tight
Pod memory near limit — close to OOMKill
Pod CrashLoopBackOff — kube_pod_container_status_waiting_reason
Pod restart count high — indicates instability
Deployment not fully available — desired vs available replicas mismatch
HPA at max replicas — traffic pressure, might need to increase maxReplicas
Node CPU/memory high — cluster capacity warning
PodDisruptionBudget violated — if too many pods disrupted
For app-level metrics (request latency, error rate, throughput) you'd need to either:
Enable the opentelemetryCollector in the Helm chart (it's already in values.yaml with create: false)
Add prometheus.io/scrape: "true" annotations to pods
```
