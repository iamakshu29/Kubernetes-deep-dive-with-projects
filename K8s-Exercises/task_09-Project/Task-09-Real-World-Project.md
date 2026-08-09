# Task 09 — Real-World Project: Production-Grade K8s Platform

> This is your capstone. No hand-holding. No step-by-step instructions.
> This is what a DevOps engineer is expected to build and maintain at a company.
> Build this, put it on GitHub, and walk through it in your next interview.

> **Cluster needed:** Persistent multi-node cluster. This project spans multiple sessions — ephemeral clusters won't work.
> - **Best option (free):** Oracle Cloud Free Tier — 2 ARM VMs (4 OCPU + 24GB RAM total), always free, persistent.
> - **Cloud experience option (recommended):** EKS cluster inside an AWS VPC — real cloud infra, ~$0.40–0.50/session. Your work lives in Git so `terraform destroy` loses nothing.
> - **NOT suitable:** Killercoda (sessions expire), kind (LoadBalancer + storage limited for full GitOps+monitoring stack).

---

## The App

**Choose one:**
- **Option A (Recommended):** Google's Online Boutique — `gcr.io/google-samples/microservices-demo` — a complete multi-service e-commerce demo (frontend, cart, payment, recommendation, etc.) with ready-made Docker images and pre-built Prometheus metrics. Good for showing you can manage a realistic multi-service architecture in interviews.
- **Option B:** An app you built yourself — gives you the ability to explain every line of code under questioning.

> This guide uses Google Online Boutique as the working example.

**Set resource `requests`/`limits` on every container from day one.** Retrofitting them later breaks HPA and scheduling assumptions.

---

## Architecture

```
GitHub Repository
  ├── app/          → Application source code + Dockerfile (if building your own)
  └── k8s/          → All manifests (or Helm charts)

CI (GitHub Actions or Jenkins)
  └── On push: build image → push to registry → update image tag in k8s/ → commit

ArgoCD (GitOps)
  └── Watches k8s/ → syncs changes to cluster automatically

Cluster Layout:
  ├── namespace: app-prod
  │     ├── frontend                     (Deployment + Service + Ingress + HPA)
  │     ├── cartservice, checkoutservice,
  │     │   productcatalogservice, ...    (Deployments + Services, each HPA-eligible)
  │     └── redis-cart                   (StatefulSet + Headless Service + PVC — cart persistence)
  ├── namespace: monitoring
  │     └── Prometheus + Grafana + Alertmanager + Loki
  ├── namespace: argocd
  │     └── ArgoCD server
  └── namespace: istio-system (Phase 5)
        └── Istio control plane

Security:
  ├── RBAC — dedicated ServiceAccount per component, least privilege
  ├── NetworkPolicies — only cartservice reaches redis-cart; default deny in app-prod
  ├── PSA — restricted profile enforced at namespace level
  ├── No root containers, readOnlyRootFilesystem where possible
  └── Secrets via External Secrets Operator + IRSA (EKS) — not plain Secret YAML
```

---

## Phase 1 — Foundation: Cluster & Base Workloads

**Steps:**
1. Provision cluster (EKS inside AWS VPC, or Oracle Free Tier + kubeadm).
2. Set resource `requests`/`limits` on every container — hard rule from the start.
3. Deploy the stateless services as `Deployments` (2+ replicas, `RollingUpdate` with `maxSurge: 1`, `maxUnavailable: 0`).
4. Deploy the stateful component (`redis-cart` for Google Boutique) as a `StatefulSet` with a headless service (`clusterIP: None`) and `volumeClaimTemplates` — NOT a Deployment. Pod restarts must re-attach to the same data.
5. Add liveness, readiness, and startup probes to every workload before Phase 2 — HPA, rolling updates, and PDBs all depend on K8s correctly knowing pod health.
6. Add `topologySpreadConstraints` to all multi-replica Deployments to spread pods across AZs — prevents all replicas landing on the same AZ and failing together during an AZ outage.
   ```yaml
   topologySpreadConstraints:
   - maxSkew: 1
     topologyKey: topology.kubernetes.io/zone
     whenUnsatisfiable: DoNotSchedule
     labelSelector:
       matchLabels:
         app: frontend
   ```

**Deliverables:**
- K8s manifests for all services
- Every container has `requests` and `limits`

**Checklist:**
- [ ] Cluster running and `kubectl get nodes` shows Ready
- [x] Resource `requests`/`limits` defined on every container
- [x] Stateless services running as `Deployments` (2+ replicas)
- [ ] `redis-cart` running as `StatefulSet` + PVC + StorageClass
- [ ] `topologySpreadConstraints` applied across AZs
- [ ] Liveness probe on every workload
- [ ] Readiness probe on every workload
- [ ] Startup probe where applicable

---

## Phase 2 — Traffic & Networking

**Steps:**
1. Deploy an Ingress Controller (ingress-nginx or AWS Load Balancer Controller for EKS).
2. Define Ingress rules routing external traffic to the API service.
3. Verify the full path: `LB → Ingress Controller → Ingress rule → Service → Pod`.
4. Apply `NetworkPolicy` to enforce isolation — test it by attempting a blocked `curl` and confirming failure:
   - Only `cartservice` pods can reach `redis-cart` on port 6379
   - Only the ingress controller can reach `frontend` on its port
   - Backend services cannot reach each other arbitrarily — only allowed paths are explicitly permitted
   - Default deny-all ingress in `app-prod` namespace
5. Install `cert-manager`; configure automated TLS issuance/rotation at the Ingress layer (Let's Encrypt or a self-signed CA for a local setup).

**Checklist:**
- [ ] Ingress Controller deployed
- [ ] Ingress rules routing correctly to the API Service
- [ ] Full `LB → Pod` path verified end-to-end (curl from outside)
- [ ] NetworkPolicy applied — only cartservice reaches redis-cart; blocked request demonstrated
- [ ] cert-manager installed and issuing/rotating TLS certs automatically

---

## Phase 3 — Scaling

**Steps:**
1. Install `metrics-server` (baseline CPU/memory metrics).
2. Install Prometheus + Prometheus Adapter to expose a custom metric — Google Online Boutique services emit Prometheus metrics natively (e.g., `http_requests_total` from the frontend); configure scraping via `ServiceMonitor`.
3. Configure HPA on a Deployment targeting the custom metric — not just default CPU.
4. Load-test to trigger a scaling event and capture it (screenshot or `kubectl get hpa -w` output) — this is a demoable interview artifact.
   > Google Online Boutique ships a built-in `loadgenerator` deployment. Enable it, or run a manual test:
   ```bash
   kubectl run -it --rm load --image=busybox --restart=Never -- \
     sh -c "while true; do wget -q -O- http://frontend/; done"
   ```
5. Add a `PodDisruptionBudget` on the `redis-cart` StatefulSet and on any high-traffic Deployment.
6. Install **Karpenter** (EKS) or Cluster Autoscaler for node-level autoscaling — HPA scales pods; when no node has capacity, Karpenter provisions the right instance type in seconds. Configure a `NodePool` and `EC2NodeClass`.

**Checklist:**
- [ ] metrics-server installed
- [ ] Prometheus + Prometheus Adapter scraping a real custom metric from an app service
- [ ] HPA configured against the custom metric
- [ ] Scaling event triggered and recorded
- [ ] PodDisruptionBudget applied to redis-cart StatefulSet and high-traffic Deployments
- [ ] Karpenter (or Cluster Autoscaler) installed and provisioning nodes on demand

---

## Phase 4 — Config, Secrets & Security

**Steps:**
1. Use `ConfigMap` for all non-sensitive configuration (DB host, port, feature flags).
2. Set up External Secrets Operator wired to AWS Secrets Manager (or Vault) for all sensitive values — no passwords committed as native `Secret` YAML in the primary path.
   > **For EKS:** Use **IRSA** (IAM Roles for Service Accounts) — annotate the ESO ServiceAccount with an IAM role ARN that has `secretsmanager:GetSecretValue` permission. No static AWS credentials are stored in the cluster. ESO + IRSA is the production-standard pattern on EKS.
3. Apply Pod Security Admission at the `restricted` profile as the namespace-level floor for `app-prod`.
4. Add image scanning (Trivy or Grype) as a required CI step — pipeline fails on critical CVEs.
5. Configure `ServiceAccount` + `Role` + `RoleBinding` scoped to least privilege for each workload that calls the K8s API.
6. Apply `ResourceQuota` / `LimitRange` at namespace level.

**Security specifics:**
- All containers: `runAsNonRoot: true`, `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`
- `readOnlyRootFilesystem: true` where possible (add emptyDir mounts for writable paths if needed)
- `automountServiceAccountToken: false` on pods that don't call the K8s API

**Checklist:**
- [ ] ConfigMap used for non-sensitive config
- [ ] External Secrets Operator + AWS Secrets Manager + IRSA wired for all secrets (no static credentials in cluster)
- [ ] PSA `restricted` profile enforced on `app-prod`
- [ ] Image scanning in CI blocking on critical CVEs
- [ ] ServiceAccount + Role + RoleBinding per workload, least privilege verified
- [ ] ResourceQuota / LimitRange applied

---

## Phase 5 — Service Mesh (Istio — differentiator, not required core)

> Do this phase if you want to stand out. Prepare a clear rationale for what you chose NOT to enable — that answer is as valuable as the implementation.

**Steps:**
1. Install Istio with a **minimal profile** — do not enable every feature.
2. Enable mTLS between `frontend` and a backend service (e.g., `productcatalogservice`) and verify with `istioctl x check-inject` or a traffic capture.
3. Configure one `VirtualService` for traffic splitting (e.g., 90/10 canary between two versions of the API).
4. Document which Istio features you deliberately did NOT enable, and why.

**Checklist:**
- [ ] Istio installed with minimal profile
- [ ] mTLS enabled and verified between two services
- [ ] VirtualService configured for a traffic split
- [ ] Written rationale for scope decisions (what was excluded and why)

---

## Phase 6 — GitOps with ArgoCD

**Install ArgoCD:**
```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

**Steps:**
1. Push all K8s manifests to GitHub under a `k8s/` directory.
2. Create an ArgoCD `Application` that watches your GitHub repo and syncs to `app-prod`.
3. Make a change (change replica count) → push to GitHub → watch ArgoCD sync it automatically.
4. Break something intentionally — watch ArgoCD detect `OutOfSync`.
5. Configure auto-sync for dev; manual/PR-gated promotion for staging/prod.
6. **Demo drift correction:** manually edit a live resource, show ArgoCD detect and revert it — this is a key interview demo moment.

> **This is GitOps.** The Git repo is the source of truth. No one runs `kubectl apply` manually in production.

**Checklist:**
- [ ] App repo and config manifests separated (or two directories)
- [ ] ArgoCD installed and syncing from GitHub
- [ ] Dev auto-sync configured
- [ ] Staging/prod promotion gated (manual sync or PR-based)
- [ ] Drift-and-self-heal demo working and recorded

---

## Phase 7 — CI/CD Pipeline

**Minimum pipeline (GitHub Actions or Jenkins):**
```
1. Checkout code
2. Build Docker image (tag with git commit SHA — never use 'latest' in production)
3. Run Trivy image scan — fail on critical CVEs
4. Push to registry (ECR or Docker Hub)
5. Update image tag in k8s/ manifest (sed or yq)
6. Commit and push manifest change to Git
7. ArgoCD auto-syncs
```
> **Why not `latest`?** Using `latest` makes deployments non-reproducible and breaks ArgoCD's drift detection — ArgoCD cannot tell if the running image is newer or older than what's in Git. Git SHA tags make every deployment auditable.

**Checklist:**
- [ ] CI building, tagging (git SHA), scanning, and pushing images
- [ ] CI automatically updates image tag in config repo per environment
- [ ] Pipeline fails on critical image vulnerabilities

---

## Phase 8 — Observability

**Steps:**
1. Prometheus + Grafana already deployed. Add `ServiceMonitor` resources to scrape each app service.
   > Google Online Boutique services expose Prometheus metrics natively — no instrumentation library needed. Configure `ServiceMonitor` to point at their `/metrics` endpoints.
2. Create a Grafana dashboard showing:
   - Request rate to the API / frontend
   - Error rate (4xx, 5xx)
   - Response time (p50, p95)
   - Pod CPU and memory usage
3. Create alerts:
   - Frontend/API error rate > 5%
   - Pod memory near limit
   - Any stateful pod restarted
4. Set up centralized logging — Loki + Grafana (or EFK stack).
5. *(Stretch)* Add distributed tracing with Jaeger or Tempo.

**Checklist:**
- [ ] Prometheus scraping real metrics from the app services via ServiceMonitor
- [ ] Grafana dashboard covering request rate, error rate, latency, CPU/memory
- [ ] Alerting rules configured for error rate, memory, pod restarts
- [ ] Centralized logging in place and queryable in Grafana

---

## Phase 9 — Helm Packaging

**Steps:**
1. Convert all manifests to Helm charts.
2. Structure as `base/` plus environment overlays: `overlays/dev`, `overlays/staging`, `overlays/prod`.
3. Parameterize environment-specific values (replica counts, resource limits, ingress hosts) via `values.yaml` per overlay.
4. ArgoCD syncs from the Helm chart — test a values change in dev promotes correctly.

**Checklist:**
- [ ] Helm charts created for all workloads
- [ ] `base/` + per-environment overlays structured correctly
- [ ] Environment-specific values parameterized cleanly
- [ ] ArgoCD deploying from Helm chart

---

## Phase 10 — Backup & Disaster Recovery

**Steps:**
1. Install Velero (or use cloud-native snapshots — AWS EBS snapshots for EKS via the `aws-ebs-csi-driver`).
2. Take a backup of the `redis-cart` StatefulSet's data.
3. Simulate data loss (delete the PVC or corrupt data) and demonstrate restore.

**Checklist:**
- [ ] Backup mechanism in place for the stateful workload
- [ ] Restore procedure tested and demonstrated end-to-end

---

## Phase 11 — Documentation

Write a `README.md` covering:
- Architecture diagram (even ASCII art is fine)
- How to deploy from scratch
- How the GitOps flow works (code push → image build → manifest update → ArgoCD sync)
- Security decisions you made and why
- **What you deliberately excluded and why** (see section below)
- What you would do differently with more time (shows self-awareness)
- Demoable moments: HPA scaling event, ArgoCD drift correction, NetworkPolicy isolation test, backup/restore

---

## Explicitly Excluded — Know Why You Skipped These

This section matters in interviews. Knowing what you deliberately did NOT do and why shows senior-level judgment.

| Excluded | Reason |
|---|---|
| Kyverno / OPA Gatekeeper | PSA `restricted` + RBAC covers the needed floor. Kyverno adds value for org-specific custom rules (registry restrictions, label enforcement) but is out of scope for a portfolio project unless a specific policy can be defended under questioning. |
| Keycloak / Active Directory | No confirmed relevance to the target stack. Cloud IAM (AWS IAM + IRSA) handles service identity; human user auth is handled by the cloud provider IdP. |
| Full production multi-region | Out of scope. Phase 5 Istio with a traffic split is the appropriate demo substitute. |
| Custom operators / controllers | ArgoCD's native CRDs are sufficient. Hand-rolling a controller is unjustified scope creep without a concrete use case. |

---

## Master Checklist

- [ ] Cluster provisioned (EKS or Oracle Free Tier)
- [ ] Resource requests/limits on all containers
- [ ] Deployment (stateless) + StatefulSet (stateful) with PVC/StorageClass
- [ ] Liveness/readiness/startup probes on all workloads
- [ ] Ingress Controller + Ingress rules, full traffic path verified
- [ ] NetworkPolicy isolation demonstrated (blocked request shown)
- [ ] cert-manager issuing/rotating TLS
- [ ] HPA wired to a custom Prometheus metric, scaling event recorded
- [ ] PodDisruptionBudget on stateful workload
- [ ] Karpenter (or Cluster Autoscaler) installed; node provisioned on demand
- [ ] ConfigMap for config; External Secrets Operator + IRSA for secrets
- [ ] PSA `restricted` enforced on `app-prod`
- [ ] Image scanning in CI, blocking on critical CVEs
- [ ] ServiceAccount/Role/RoleBinding least privilege per workload
- [ ] ResourceQuota/LimitRange per namespace
- [ ] ArgoCD GitOps: auto-sync dev, gated staging/prod, drift-correction demo
- [ ] CI: build, tag (SHA), scan, push, update manifest
- [ ] Prometheus/Grafana dashboards + alerting
- [ ] Centralized logging (Loki)
- [ ] Helm charts with base/ + environment overlays
- [ ] Backup/restore demonstrated for the stateful workload (redis-cart)
- [ ] Full README with architecture, rationale, exclusions, and demo moments
- [ ] *(Stretch)* Istio mTLS + VirtualService traffic split
- [ ] *(Stretch)* Argo Rollouts canary/blue-green on the API
- [ ] *(Stretch)* Distributed tracing (Jaeger or Tempo)

---

## What This Project Proves in an Interview

| What You Built | What It Shows |
|---|---|
| Multi-namespace cluster with RBAC + NetworkPolicies | Production cluster management |
| GitOps with ArgoCD (drift correction demo) | Modern deployment practices |
| CI/CD pipeline updating manifests on every push | Full dev → prod pipeline ownership |
| HPA scaling on a custom metric with a recorded demo | Hands-on autoscaling, not just config |
| Prometheus metrics + Grafana dashboards + alerting | Owning observability end-to-end |
| StatefulSet for Postgres with backup/restore | Running stateful workloads correctly |
| Multi-service app (Google Boutique or own) | You can explain the architecture and each service's role |
| Helm charts with environment overlays | Real packaging and environment promotion |
| Explicitly excluded section in README | Senior-level judgment on scope |

---

## Completion Check

You are done when you can demo this live and answer:

- "How does a code change get from GitHub to running in production in your setup?"
- "How do you ensure Redis is not accessible from every service — only cartservice should reach it?"
- "What happens if the API pod crashes?"
- "How do you know the API is healthy right now?"
- "Walk me through your GitOps setup — what happens if someone manually edits a live resource?"
- "Why IRSA instead of storing AWS credentials as a Secret in the cluster?"
- "What is PSA and how is it enforced in your cluster?"
- "You have HPA configured — what metric is it scaling on and why that metric?"

---

**Put the GitHub link on your resume.**

---

## What You Can Skip (and When to Add It)

| Item | Skip? | Add when |
|---|---|---|
| External Secrets Operator + IRSA | Skip — use plain K8s Secrets | After you're on EKS and familiar with AWS IAM |
| Karpenter / Cluster Autoscaler | Skip | Only if deploying on EKS |
| topologySpreadConstraints | Skip | Add as a polish step before interviews |
| Phase 5 — Istio / Service Mesh | Skip entirely | Not in curriculum; put in "Explicitly Excluded" |
| Phase 10 — Velero / Backup | Skip | Not in curriculum; put in "Explicitly Excluded" |


