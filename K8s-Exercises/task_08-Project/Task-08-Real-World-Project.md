# Task 08 — Real-World Project: End-to-End Platform on K8s

> This is your capstone. No hand-holding. No step-by-step instructions.
> This is what a DevOps engineer is expected to build and maintain at a company.
> Build this, put it on GitHub, and walk through it in your next interview.

> **Cluster needed:** Persistent multi-node cluster. This project spans multiple sessions — ephemeral clusters won't work.
> - **Best option (free):** [Oracle Cloud Free Tier](https://www.oracle.com/cloud/free/) — 2 ARM VMs (4 OCPU + 24GB RAM total), always free, persistent. Full setup in **00-Setup.md Option B**.
> - **Cloud experience option:** AWS EC2 + Terraform — real cloud infra, ~$0.40–0.50/session. Your work lives in Git so `terraform destroy` loses nothing. Setup in **00-Setup.md Option C**.
> - **NOT suitable:** Killercoda (sessions expire after 4 hours), kind (LoadBalancer and storage are limited for the full GitOps+monitoring stack).

---

## The Project: A Production-Grade App Platform

You will build a complete platform that runs a real microservices application on your local K8s cluster with everything a company would expect: CI/CD, monitoring, security, GitOps.

---

## Architecture

```
GitHub Repository
  └── Source code + Kubernetes manifests (or Helm chart)

Jenkins / GitHub Actions
  └── On push: build Docker image → push to registry → update manifest

ArgoCD (GitOps)
  └── Watches the Git repo → syncs changes to cluster automatically

Cluster Layout:
  ├── namespace: app-prod
  │     ├── frontend (Deployment + Service + Ingress)
  │     ├── api (Deployment + Service)
  │     └── postgres (StatefulSet + Headless Service + PVC)
  ├── namespace: monitoring
  │     ├── Prometheus + Grafana + Alertmanager
  │     └── Loki + Promtail
  └── namespace: argocd
        └── ArgoCD server

Security:
  ├── RBAC — separate SA per component
  ├── NetworkPolicies — only api can reach postgres
  ├── No root containers
  └── Secrets managed via environment variables (or Vault if you go advanced)
```

---

## Phase 1 — Application Setup

**Choose one of these as your app (they have ready Docker images):**
- Option A: `gcr.io/google-samples/microservices-demo` (Google's Online Boutique — full microservices)
- Option B: A simple Python FastAPI app you write yourself (show off your Python skills) + postgres

**Recommended: Option B** — write the FastAPI app yourself. It does not need to be complex:
- `GET /` → returns `{"status": "ok"}`
- `GET /items` → reads from postgres and returns rows
- `POST /items` → writes to postgres

Why: You can explain every line of code in the interview. With Option A you are just deploying someone else's work.

**Deliverables:**
- Dockerfile for the FastAPI app
- K8s manifests (or Helm chart) for frontend, api, postgres
- Everything in separate namespaces, proper labels, resource limits on all containers

---

## Phase 2 — GitOps with ArgoCD

**Install ArgoCD:**
```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

**Your task:**
1. Push all your K8s manifests to a GitHub repository under a `k8s/` directory
2. Create an ArgoCD Application that watches your GitHub repo and syncs to `app-prod` namespace
3. Make a change to your Deployment (change replica count) → push to GitHub → watch ArgoCD sync it automatically
4. Break something intentionally and watch ArgoCD detect `OutOfSync`
5. Configure auto-sync so manual approval is not needed (appropriate for dev, not prod — understand the difference)

**This is GitOps.** Code is the source of truth. No one should run `kubectl apply` manually in production.

---

## Phase 3 — CI/CD Pipeline

**Option A (Simpler):** GitHub Actions
- On push to `main`: build Docker image → push to Docker Hub → update image tag in `k8s/` manifests → commit → ArgoCD picks up the change

**Option B (You know Jenkins — use it):** Jenkins pipeline
- Same flow but with a Jenkinsfile

Minimum pipeline steps:
```
1. Checkout code
2. Build Docker image (tag with git commit SHA)
3. Push to registry
4. Update image tag in k8s manifest file (sed or yq)
5. Commit and push manifest change to Git
6. ArgoCD auto-syncs
```

---

## Phase 4 — Security Hardening

Before calling this production-ready, apply:

1. **RBAC:** Create ServiceAccounts for the api and frontend pods — they should not use the default SA
2. **NetworkPolicies:**
   - Only `api` pods can reach `postgres` on port 5432
   - Only `ingress-controller` pods can reach `frontend` on port 80
   - `frontend` cannot talk to `postgres` directly
   - Default deny all in `app-prod` namespace
3. **Pod Security:**
   - All containers run as non-root
   - `readOnlyRootFilesystem: true` where possible
   - Drop all capabilities except what is needed
4. **Secrets:** Move all passwords/keys out of plain YAML into K8s Secrets (minimum) or Vault (advanced)

---

## Phase 5 — Observability

1. Prometheus + Grafana already deployed (from Task 06)
2. Add a ServiceMonitor for your FastAPI app — instrument it with the `prometheus-fastapi-instrumentator` Python library
3. Create a Grafana dashboard showing:
   - Request rate to the API
   - Error rate (4xx, 5xx)
   - Response time (p50, p95)
   - Pod CPU and memory usage
4. Create alerts for:
   - API error rate > 5%
   - Pod memory near limit
   - Postgres pod restarted

---

## Phase 6 — Document It

Write a `README.md` in your GitHub repo that explains:
- Architecture diagram (even ASCII art is fine)
- How to deploy from scratch
- How the GitOps flow works
- Security decisions you made and why
- What you would do differently with more time (show self-awareness)

---

## What This Project Proves in an Interview

| What You Built | What It Shows |
|---|---|
| Multi-namespace cluster with proper RBAC | You understand production cluster management |
| GitOps with ArgoCD | You know modern deployment practices |
| CI/CD pipeline updating manifests | You understand the full dev → prod pipeline |
| NetworkPolicies between components | You think about security, not just functionality |
| Prometheus metrics + Grafana dashboards | You can own observability, not just deploy apps |
| StatefulSet for postgres | You know how to run stateful workloads |
| Custom app (FastAPI) | You can write and deploy your own services |

---

## Stretch Goals (If You Want to Go Deeper)

- **Helm:** Package your app as a Helm chart instead of raw manifests. Add `values.yaml` for environment overrides.
- **Sealed Secrets or External Secrets Operator:** Proper secrets management
- **Horizontal Pod Autoscaler:** Scale the API based on request rate using KEDA
- **Multi-environment:** Add a `staging` branch that deploys to a separate namespace via ArgoCD
- **Cluster upgrade:** Upgrade your kubeadm cluster from 1.29 to 1.30 without downtime

---

## Completion Check

You are done when you can demo this live and answer:
- "How does a code change get from GitHub to running in production in your setup?"
- "How do you ensure the database is not accessible from the frontend directly?"
- "What happens if the API pod crashes?"
- "How do you know the API is healthy right now?"
- "Walk me through your GitOps setup."

---

**You now have a real K8s portfolio project. Put the GitHub link on your resume.**
