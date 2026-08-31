# Task 10 — Real-World Project: Production-Grade K8s Platform

> This is your capstone. No hand-holding. No step-by-step instructions.
> This is what a DevOps engineer is expected to build and maintain at a company.
> Build this, put it on GitHub, and walk through it in your next interview.

> **Cluster needed:** Persistent multi-node cluster. This project spans multiple sessions — ephemeral clusters won't work.
>
> - **Best option (free):** Oracle Cloud Free Tier — 2 ARM VMs (4 OCPU + 24GB RAM total), always free, persistent.
> - **Cloud experience option (recommended):** EKS cluster inside an AWS VPC — real cloud infra, ~$0.40–0.50/session. Your work lives in Git so `terraform destroy` loses nothing.
> - **NOT suitable:** Killercoda (sessions expire), kind (LoadBalancer + storage limited for full GitOps+monitoring stack).

---

## The App

Google's Online Boutique — `gcr.io/google-samples/microservices-demo` — a complete multi-service e-commerce demo (frontend, cart, payment, recommendation, etc.) with ready-made Docker images and pre-built Prometheus metrics. Good for showing you can manage a realistic multi-service architecture in interviews.

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
2. Clone the Online Boutique repo and read the README. The repo already provides working manifests in `kubernetes-manifests/` — this is your starting point, not a blank file. Your job is to adapt and harden them, not write from scratch.
3. Set resource `requests`/`limits` on every container — hard rule from the start.
4. Deploy the stateless services as `Deployments`.
5. Add liveness, readiness probes to every workload
6. Add Anti-Affinity to Pods to spread pods across AZs — prevents all replicas landing on the same AZ and failing together during an AZ outage.

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
   - Default deny-all ingress in project namespace
5. Install `cert-manager`; configure automated TLS issuance/rotation at the Ingress layer (Let's Encrypt or a self-signed CA for a local setup).

---

## Phase 3 — Scaling

**Steps:**

1. Install `metrics-server` (baseline CPU/memory metrics).
2. Install Prometheus + Prometheus Adapter to expose a custom metric — Google Online Boutique services emit Prometheus metrics natively (e.g., `http_requests_total` from the frontend); configure scraping via `ServiceMonitor`.
3. Configure HPA on a Deployment targeting the custom metric — not just default CPU.
4. Load-test to trigger a scaling event and capture it (screenshot or `kubectl get hpa -w` output) — this is a demoable interview artifact.
   > Google Online Boutique ships a built-in `loadgenerator` deployment. Enable it.
5. Add a `PodDisruptionBudget` on high-traffic Deployments.

---

## Phase 4 — Config, Secrets & Security

**Steps:**

1. Use `ConfigMap` for all non-sensitive configuration (DB host, port, feature flags).
2. Apply Pod Security Admission at the `restricted` profile as the namespace-level floor for `app-prod`.
3. Add image scanning (Trivy or Grype) as a required CI step — pipeline fails on critical CVEs.
4. Configure `ServiceAccount` + `Role` + `RoleBinding` scoped to least privilege for each workload that calls the K8s API.
5. Apply `ResourceQuota` / `LimitRange` at namespace level.

**Security specifics:**

- All containers: `runAsNonRoot: true`, `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`
- `readOnlyRootFilesystem: true` where possible (add emptyDir mounts for writable paths if needed)
- `automountServiceAccountToken: false` on pods that don't call the K8s API.

---

## Phase 5 — Observability

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

---

## Phase 6 — Helm Packaging

**Steps:**

1. Convert all manifests to a Helm chart.
2. Structure the chart with a single `templates/` directory and separate values files per environment.
3. Deploy with environment-specific values:

---

## Phase 7 — Documentation

Write a `README.md` covering:

- How to deploy from scratch
- Security decisions you made and why
- **What you deliberately excluded and why** (see section below)
- What you would do differently with more time (shows self-awareness)
- Demoable moments: HPA scaling event, ArgoCD drift correction, NetworkPolicy isolation test, backup/restore

---

## Master Checklist

- [ ] Cluster provisioned (EKS or Oracle Free Tier)
- [x] Resource requests/limits on all containers
- [x] Deployment (stateless) + StatefulSet (stateful) with PVC/StorageClass
- [x] Liveness/readiness/startup probes on all workloads
- [x] Ingress Controller + Ingress rules, full traffic path verified
- [x] NetworkPolicy isolation demonstrated (blocked request shown)
- [x] cert-manager issuing/rotating TLS
- [ ] HPA wired to a custom Prometheus metric, scaling event recorded
- [x] PodDisruptionBudget
- [x] ConfigMaps
- [x] PSA `restricted` enforced on `app-prod`
- [x] ServiceAccount/Role/RoleBinding least privilege per workload
- [x] ResourceQuota/LimitRange per namespace
- [ ] Prometheus/Grafana dashboards + alerting
- [ ] Centralized logging (Loki)
- [x] Helm chart with `values.yaml` + `values-dev.yaml` + `values-prod.yaml`
- [ ] Full README with architecture, rationale, exclusions, and demo moments

---
