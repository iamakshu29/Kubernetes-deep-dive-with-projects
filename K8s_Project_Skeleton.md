# Kubernetes Portfolio Project — Build Plan & Checklist

**Target audience for this project: DevOps/Platform Engineer interviews**
**Base infra: (KIND Cluster/EKS)**

---

## Phase 1: Foundation — Cluster & Base Workloads

**Steps:**
1. Provision EKS cluster inside AWS VPC (reuse subnets, NAT, security groups already built).
2. Set resourceQuota for the namespace to avoid noisy neighbour issues.
3. Set LimitRange for default resource requests and limits for new pods.
4. Set resource `requests`/`limits` on every container as a hard rule from the start — retrofitting these later breaks HPA and scheduling assumptions.
5. Deploy a stateless service as a `Deployment` (2+ replicas, rolling update strategy).
6. Deploy Postgres (or equivalent) as a `StatefulSet` with a `PersistentVolumeClaim` and a defined `StorageClass`.
7. Add liveness, readiness, and startup probes to every workload before moving to Phase 2 — HPA, rolling updates, and PDBs all depend on Kubernetes correctly knowing pod health.

**Checklist:**
- [ ] EKS cluster running inside AWS VPC
- [x] Create resourceQuota for the namespace
- [x] Create LimitRange as the default requests and limits for the new pods.
- [ ] Resource `requests`/`limits` defined on every container
- [ ] Stateless service running as `Deployment`
- [ ] Stateful service running as `StatefulSet` + PVC + StorageClass
- [ ] Liveness probe on every workload
- [ ] Readiness probe on every workload
- [ ] Startup probe where applicable (slow-starting services)

---

## Phase 2: Traffic & Networking

**Steps:**
1. Deploy an Ingress Controller (e.g., ingress-nginx or AWS Load Balancer Controller).
2. Define Ingress rules routing to backing Services.
3. Verify full path: LB → Ingress Controller → Ingress rules → Service → Pod.
4. Apply `NetworkPolicy` to enforce namespace isolation — test it by attempting a blocked cross-namespace `curl` and confirming failure.
5. Install `cert-manager`; configure automated TLS issuance/rotation at the Ingress layer (Let's Encrypt or a private CA for a demo setup).

**Checklist:**
- [ ] Ingress Controller deployed
- [ ] Ingress rules routing correctly to Services
- [ ] Full LB → Pod path verified end-to-end
- [ ] NetworkPolicy applied and isolation demonstrated with a failing cross-namespace request
- [ ] cert-manager installed and issuing/rotating TLS certs automatically

---

## Phase 3: Scaling

**Steps:**
1. Install `metrics-server` (baseline CPU/memory metrics).
2. Install Prometheus + Prometheus Adapter to expose a custom metric (e.g., request rate or queue depth).
3. Configure HPA on the Deployment, targeting the custom metric — not just default CPU/memory.
4. Load-test to trigger a scaling event and capture it as a demoable artifact (screenshot or short recording of replica count changing).
5. Add a `PodDisruptionBudget` on the stateful workload to protect availability during node drains/rolling updates.

**Checklist:**
- [ ] metrics-server installed
- [ ] Prometheus + Prometheus Adapter installed and scraping a real custom metric
- [ ] HPA configured against the custom metric, targeting the Deployment's scale subresource
- [ ] Scaling event triggered and recorded
- [ ] PodDisruptionBudget applied to the stateful workload

---

## Phase 4: Config, Secrets & Security

**Steps:**
1. Use `ConfigMap` for all non-sensitive configuration.
2. Set up AWS Secrets Manager + External Secrets Operator (or Secrets Store CSI Driver) for all sensitive values — no secrets committed as native `Secret` objects in the primary path.
3. Apply Pod Security Admission at the `restricted` profile as the namespace-level floor.
4. Add image scanning (Trivy or Grype) as a required CI step — pipeline fails on critical CVEs.
5. Configure `ServiceAccount` + `Role` + `RoleBinding` scoped to least privilege for each workload that needs API access.
6. Apply `ResourceQuota` / `LimitRange` at the namespace level.

**Checklist:**
- [ ] ConfigMap used for non-sensitive config
- [ ] AWS Secrets Manager + External Secrets Operator (or CSI driver) wired up for all secrets
- [ ] PSA `restricted` profile enforced at namespace level
- [ ] Image scanning integrated into CI, blocking on critical vulnerabilities
- [ ] ServiceAccount + Role + RoleBinding configured per workload, least privilege verified
- [ ] ResourceQuota / LimitRange applied at namespace level

---

## Phase 5: Service Mesh (Istio — minimal, deliberate scope)

**Steps:**
1. Install Istio with a minimal profile — do not enable every feature.
2. Enable mTLS between two services and verify with a traffic capture or `istioctl` check.
3. Configure one `VirtualService` for traffic splitting (e.g., 90/10 canary split between two versions of one service).
4. Prepare a short explanation of which Istio features you deliberately did *not* enable, and why — this is as important as what you did include.

**Checklist:**
- [ ] Istio installed with minimal profile
- [ ] mTLS enabled and verified between two services
- [ ] VirtualService configured for a traffic split
- [ ] Written rationale for scope decisions (what was excluded and why)

---

## Phase 6: Multi-Cluster (stretch goal — not core deliverable)

**Steps:**
1. Spin up two local `kind` clusters.
2. Share a common root CA between them.
3. Configure Istio for cross-cluster service discovery via an east-west gateway.
4. Verify a service in cluster 1 can call a service in cluster 2 through the mesh.

**Checklist:**
- [ ] Two kind clusters running
- [ ] Shared CA/trust configured
- [ ] Cross-cluster service discovery working
- [ ] Cross-cluster call verified end-to-end

---

## Phase 7: Packaging

**Steps:**
1. Convert all manifests to Helm charts.
2. Structure as `base/` plus environment overlays: `overlays/dev`, `overlays/staging`, `overlays/prod`.
3. Parameterize environment-specific values (replica counts, resource limits, ingress hosts) via `values.yaml` per overlay.

**Checklist:**
- [ ] Helm charts created for all workloads
- [ ] `base/` + per-environment overlays structured correctly
- [ ] Environment-specific values parameterized cleanly

---

## Phase 8: GitOps & CI/CD Pipeline

**Steps:**
1. Split into two repos (or two directories): app source + CI, and deployment config (Helm charts/overlays).
2. Set up GitHub Actions: on push, build image, tag with git SHA, scan (Phase 4), push to ECR.
3. CI commits the new image tag into the target environment's overlay in the config repo.
4. Install ArgoCD; connect it to the config repo.
5. Configure ArgoCD auto-sync for dev; manual sync (or PR-gated promotion) for staging/prod.
6. Demo drift correction: manually edit a live resource, show ArgoCD detect and revert it.
7. (Differentiator) Install Argo Rollouts; configure a canary or blue-green rollout for one service.

**Checklist:**
- [ ] App repo and config repo (or directories) separated
- [ ] GitHub Actions building, tagging, scanning, and pushing images to ECR
- [ ] CI automatically updates image tag in config repo per environment
- [ ] ArgoCD installed and syncing from config repo
- [ ] Dev auto-sync configured
- [ ] Staging/prod promotion gated (manual sync or PR-based)
- [ ] Drift-and-self-heal demo working and recorded
- [ ] (Stretch) Argo Rollouts configured for canary/blue-green on one service

---

## Phase 9: Observability

**Steps:**
1. Confirm Prometheus + Grafana dashboards cover all workloads (not just the HPA custom metric).
2. Set up centralized logging — Loki (paired with Grafana) or an EFK stack.
3. Add distributed tracing (Jaeger or Tempo) — straightforward if Istio sidecars are already generating trace headers.

**Checklist:**
- [ ] Grafana dashboards covering all workloads
- [ ] Centralized logging in place and queryable
- [ ] Distributed tracing configured (if time permits)

---

## Phase 10: Backup & Disaster Recovery

**Steps:**
1. Install Velero (or document a manual PVC snapshot/restore procedure).
2. Take a backup of the stateful workload's data.
3. Simulate data loss (delete the PVC or corrupt data) and demonstrate restore.

**Checklist:**
- [ ] Backup mechanism in place for the stateful workload
- [ ] Restore procedure tested and demonstrated end-to-end

---

## Phase 11: Documentation

**Steps:**
1. Write a README covering: architecture diagram, why each major tool was chosen (ArgoCD vs. Flux, minimal Istio vs. full mesh, external secrets vs. native), and what was deliberately left out and why.
2. Include the interview-demoable moments explicitly: HPA scaling event, ArgoCD drift correction, NetworkPolicy isolation test, backup/restore.

**Checklist:**
- [ ] README with architecture diagram
- [ ] Tool-choice rationale documented for every major decision
- [ ] Explicit "what was excluded and why" section (Kyverno, Keycloak/AD, full multi-region)
- [ ] Demoable moments listed and reproducible

---

## Explicitly Excluded (do not add — no evidence this is expected, and adding it risks the resume-gap problem already identified)
- Kyverno / OPA Gatekeeper — omit unless a specific custom policy exists that can be defended under questioning
- Keycloak / Active Directory — no confirmed relevance to Salesforce's actual stack; skip entirely
- Full production multi-region — out of scope; Phase 6 (local kind clusters) is the appropriate substitute
- Custom operators/controllers for GitOps — ArgoCD's native CRDs are sufficient; hand-rolling one is unjustified scope creep

---

## Master Checklist (all phases, condensed)

- [ ] Cluster provisioned inside EKS VPC
- [ ] Resource requests/limits on all containers
- [ ] Deployment (stateless) + StatefulSet (stateful) with PVC/StorageClass
- [ ] Liveness/readiness/startup probes on all workloads
- [ ] Ingress Controller + Ingress rules, full traffic path verified
- [ ] NetworkPolicy isolation demonstrated
- [ ] cert-manager issuing/rotating TLS
- [ ] HPA wired to a custom Prometheus metric
- [ ] PodDisruptionBudget on stateful workload
- [ ] ConfigMap for config, External Secrets Operator/CSI driver for secrets
- [ ] PSA restricted profile enforced
- [ ] Image scanning in CI
- [ ] ServiceAccount/Role/RoleBinding least privilege
- [ ] ResourceQuota/LimitRange per namespace
- [ ] Istio minimal setup: mTLS + one VirtualService, scope rationale documented
- [ ] (Stretch) Multi-cluster Istio demo across two kind clusters
- [ ] Helm charts with base/ + environment overlays
- [ ] GitHub Actions CI: build, tag, scan, push
- [ ] ArgoCD GitOps: auto-sync dev, gated staging/prod, drift-correction demo
- [ ] (Stretch) Argo Rollouts canary/blue-green
- [ ] Prometheus/Grafana, centralized logging, (stretch) tracing
- [ ] Backup/restore demonstrated for stateful workload
- [ ] Full documentation with architecture, rationale, and exclusions