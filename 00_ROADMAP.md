# K8s Deep Dive — Learning Roadmap
> Goal: Company-level Kubernetes proficiency for a DevOps / Platform Engineering role.
> Not exam prep. Real skills, real scenarios, real projects.

---

## What's in This Repo

```
00_Task_Overview/Kubernetes_Task_Overview.md   → Theory: WHY each concept exists at a company level
                                    4 phase tables mapping topics to real DevOps responsibilities
                                    Quick concept-check tasks (skip if you already know K8s basics)

01_K8s-Exercises/
  00-Setup.md                    → Cluster setup guide — kind, Oracle Free Tier, AWS+Terraform
  ROADMAP.md                     → Full learning path overview, task descriptions, cluster guide
  Task-01 → Task-05              → Core K8s: namespaces, workloads, networking, storage, RBAC
  Task-05b-Helm.md               → Helm: packaging and deploying apps at scale
  Task-06 → Task-07 → Task-08     → Production: ArgoCD (GitOps CD), observability, troubleshooting
  Task-09-Real-World-Project.md  → Capstone: FastAPI + PostgreSQL + ArgoCD + CI/CD + Prometheus
```
---

## File Reading Order

Do NOT try to read everything first. Use this pattern — one phase at a time:

```
1. 01_K8s-Exercises/00-Setup.md          → Read once, set up your cluster
2. 01_K8s-Exercises/ROADMAP.md           → Skim once to understand the full path
3. 00_Task_Overview/Kubernetes_Task_Overview.md     → Read one Phase table JUST BEFORE the matching task
4. 01_K8s-Exercises/Task-XX              → Do the actual work here
```

---
## How to Use These Files

There are two layers. Use them together — one informs, the other builds skill.

### Layer 1 — `Kubernetes_Task_Overview.md` (outside this folder)
This is your **map and warm-up**. Read one phase at a time.
- Explains WHAT each K8s concept is and WHY it matters at a company
- Has short 5–15 min concept-check tasks (1.1, 2.3, 3.5 etc.) — just enough to verify you understood it
- Not a deep dive. Not a project. Just "do I get this concept?"

### Layer 2 — This folder (`01_K8s_Exercises/`)
This is your **actual lab**. One task at a time, in order.
- Each task is a 2–3 hour deep dive on one topic
- Real scenarios, debugging problems, interview prep questions
- Ends with a mini-project that produces GitHub-ready deliverables

---

## The Right Way to Work Through This

```
Open Kubernetes_Task_Overview.md
  │
  ├── Read Phase 1 (Weeks 1–2)
  │     Do quick tasks 1.1, 1.2, 1.3 inside that file (15–30 mins)
  │       │
  │       └──▶ Open Task-01 here → deep dive → mini project → GitHub commit
  │
  ├── Read Phase 2 (Weeks 3–4)
  │     Do quick tasks 2.1 → 2.5 inside that file
  │       │
  │       └──▶ Open Task-02 here → deep dive → mini project → GitHub commit
  │
  ├── Read Phase 3 (Weeks 5–7)
  │     Do quick tasks 3.1 → 3.5 inside that file
  │       │
  │       └──▶ Task-03 → Task-04 → Task-05 → Task-05b (deep dives + mini projects)
  │
  └── Read Phase 4 (Weeks 8–10)
        Do quick tasks 4.1 → 4.4 inside that file
          │
          └──▶ Task-06 → Task-07 → Task-08 (deep dives + mini projects)
                │
                └──▶ Task-09 — Final Project (capstone, goes on GitHub + resume)
```

---

## File Index -> 01_K8s_Exercises/

### `00-Setup.md`
**What:** Cluster environment setup guide — covers all options (kind, Oracle Free Tier, AWS, Multipass) and maps each to the right task.
**Read this first.** Different tasks need different cluster types — this file explains which to use and when.

---

### `Task-01 — Namespaces, Contexts & Multi-Team Management`
**What you learn:**
- How companies organise clusters by teams and environments using namespaces
- ResourceQuota — cap CPU/memory/pod count per team
- LimitRange — enforce default resource settings so devs can't forget
- kubectl contexts — switching between clusters and namespaces safely
- Pod Security Admission — namespace-level enforcement of security profiles (no root containers cluster-wide)

**Mini project:** Set up a full multi-team namespace structure with quotas, LimitRanges, PSA labels, and a context-switching script. Deliverables go to GitHub.

**Cluster:** Any single-node — kind or Killercoda (browser, no install).

---

### `Task-02 — Workloads: Deploying and Managing Applications`
**What you learn:**
- Deployments, ReplicaSets — and why you never create bare pods
- Rolling updates and rollbacks — zero-downtime deploys
- Liveness, Readiness, Startup probes — gating traffic correctly
- ConfigMaps and Secrets — injecting config the right way
- DaemonSets — one pod per node (log agents, monitoring)
- Jobs and CronJobs — scheduled and one-off tasks
- Horizontal Pod Autoscaler — scaling on CPU/memory
- **Init containers** — gating app startup on dependencies
- **PodDisruptionBudget** — protecting availability during node maintenance
- **topologySpreadConstraints / podAntiAffinity** — spreading replicas across nodes/zones
- **preStop hooks + terminationGracePeriodSeconds** — zero-dropped-requests during rolling updates

**Mini project:** Deploy a resilient 2-tier app (API + Redis) with probes, HPA, PDB, anti-affinity, rolling updates. Show v1 → v2 rollout and rollback.

**Cluster:** kind 2-node — see 00-Setup.md Option A1. metrics-server required for HPA.

---

### `Task-03 — Networking, Services & Ingress` (V. Important)
**What you learn:**
- ClusterIP, NodePort, LoadBalancer — when to use each
- DNS and service discovery — how pods talk to each other by name
- Ingress — routing external traffic to multiple services via one IP
- NetworkPolicies — zero-trust between pods and namespaces
- Debugging network issues — the systematic approach
- **cert-manager** — automating TLS certificate lifecycle (the real company way)
- **MetalLB** — giving LoadBalancer services a real external IP on bare-metal/local clusters
- **ExternalName service** — connecting K8s services to external databases and APIs without hardcoding hostnames
- **externalTrafficPolicy** — preserving real client IPs through NodePort/LoadBalancer services
- **Gateway API** — the standard replacing Ingress; what it solves and why it matters for multi-team clusters

**Mini project:** 3 services behind one Ingress with path routing + TLS via cert-manager. NetworkPolicies enforcing zero-trust. LoadBalancer service exposed via MetalLB. Proven with curl from inside pods.

**Cluster:** kind + Calico CNI — see 00-Setup.md Option A2. Default kindnet does NOT enforce NetworkPolicies.

---

### `Task-04 — Storage: Persistent Data`
**What you learn:**
- Why pod storage is ephemeral and why that matters
- PersistentVolume, PersistentVolumeClaim, StorageClass — the full chain
- Dynamic provisioning — devs get storage without asking the platform team
- StatefulSets — the right way to run databases (ordered, stable identity, own PVC)
- emptyDir and sidecar patterns
- **VolumeSnapshots** — K8s-native PVC backup before risky operations
- Debugging: PVC pending, permission denied, ReadWriteOnce conflicts

**Mini project:** PostgreSQL StatefulSet with PVC. Prove data survives pod deletion. Take a VolumeSnapshot before a destructive operation and restore from it.

**Cluster:** kind 2-node — see 00-Setup.md Option A1. Node-failure simulation needs Oracle/AWS.

---

### `Task-05 — RBAC & Security`
**What you learn:**
- Roles and ClusterRoles — namespaced vs cluster-wide permissions
- RoleBindings and ClusterRoleBindings — who gets what
- ServiceAccounts — identity for pods and CI/CD pipelines
- Pod securityContext — non-root, read-only filesystem, dropped capabilities
- Secrets security — why raw K8s secrets are not enough and what companies use instead
- **Kyverno** — admission-time policy enforcement (resource limits required, no root, trusted registries only)

**Mini project:** Three ServiceAccounts (viewer, deployer, admin) with precise RBAC. A secure deployment. Kyverno policies enforcing security baselines. Proven with `kubectl auth can-i` tests.

**Cluster:** Any single-node — kind or Killercoda.

---

### `Task-06 — Helm: Packaging and Deploying Applications at Scale`
**What you learn:**
- What Helm solves that raw YAML cannot handle at scale
- Chart structure — templates, values, conditions, helpers
- Creating charts from scratch with per-environment values files
- Release lifecycle — install, upgrade, rollback, uninstall
- Helm hooks — pre-upgrade DB migrations
- Helm in CI/CD — `helm upgrade --install --rollback-on-failure` pattern
- Debugging: `helm template`, `helm diff`, `helm get`

**Mini project:** Package the Task 02 app stack as a Helm chart. Deploy dev and prod releases from the same chart with different values. Simulate a CI upgrade with rollback.

**Cluster:** kind single-node — see 00-Setup.md Option A.

---

### `Task-07 — ArgoCD: GitOps Continuous Deployment`
**What you learn:**
- GitOps — pull-based CD, Git as source of truth, drift detection
- Install ArgoCD, create Application manifests, auto-sync and self-heal
- The two-repo pattern — app repo vs GitOps repo
- App of Apps — managing multiple apps through a single root Application
- Sync waves and resource hooks — ordering deploys (DB migration before app)
- RBAC and AppProjects — team-scoped access control
- ApplicationSet — generate Applications for dev/staging/prod from one template
- Argo Rollouts — canary deployments with progressive traffic shifting

**Mini project:** Full GitOps setup — App of Apps root, Helm chart with per-env values, PreSync migration hook, RBAC AppProject, canary rollout for the prod environment. Pipeline-to-cluster flow end-to-end.

**Cluster:** kind 2-node or Oracle Free Tier (2GB RAM minimum for ArgoCD).

---

### `Task-08 — Observability: Metrics, Logs & Alerting`
**What you learn:**
- metrics-server — `kubectl top` for quick resource checks
- Prometheus + Grafana via Helm — the industry standard stack
- PromQL — writing queries to answer real operational questions
- PrometheusRule — creating alerts that fire before users notice
- Logs — `kubectl logs` patterns + centralised logging with Loki
- ServiceMonitor — making Prometheus scrape your own app's metrics
- **SLO-based alerting** — alerting on user-facing indicators, not just infrastructure metrics
- **Cluster Autoscaler** — how node-level scaling works and how it interacts with HPA

**Mini project:** Full monitoring setup for team-alpha's API. SLO breach alert, Grafana dashboard, triggered alert screenshot, exported dashboard JSON for GitHub.

**Cluster:** Oracle Free Tier or AWS EC2 — see 00-Setup.md Options B/C. Prometheus stack is too heavy for local kind without 8GB+ RAM.

---

### `Task-09 — Troubleshooting: Debugging a Broken Cluster`
**What you learn:**
- The systematic debugging mindset — symptom → layer → cause
- Diagnosing: Pending, CrashLoopBackOff, ImagePullBackOff, OOMKilled
- Debugging service connectivity — endpoints, DNS, exec+curl
- Node NotReady — simulate and recover
- etcd backup and restore — disaster recovery
- **Certificate expiry** — how to check, renew, and automate before a 3am outage
- **DiskPressure / MemoryPressure** — node eviction conditions and QoS class impact

**Mini project:** A self-imposed broken cluster (4 simultaneous issues). Find and fix all of them, then write a proper incident report in post-mortem format.

**Cluster:** kind 2-node for Scenarios 1–4 and 6. Oracle Free Tier or AWS for Scenarios 5 (node stop) and 6 (etcd).

---

### `Task-10 — Real-World Final Project` ← Capstone
**What you build:**
A production-grade application platform on K8s — end to end.

| Component     | What                                                                                       |
| ---------------| --------------------------------------------------------------------------------------------|
| Application   | FastAPI (Python) + PostgreSQL StatefulSet                                                  |
| Packaging     | **Helm chart** with dev/prod values (from Task-05b)                                        |
| GitOps        | ArgoCD watching GitHub repo, auto-sync                                                     |
| CI/CD         | GitHub Actions or Jenkins — build image → update manifest → ArgoCD deploys                 |
| Security      | RBAC per component, Kyverno policies, NetworkPolicies (zero-trust), non-root pods, Secrets |
| Observability | Prometheus metrics from FastAPI, SLO-based Grafana dashboard, 3 alert rules                |

**This goes on your GitHub. Walk through it in interviews.**

**Cluster:** Oracle Free Tier (best) or AWS EC2. Persistent across sessions — kind/Killercoda not suitable.

---

## Reference File

| File                          | Purpose                                                                                                    |
| -------------------------------| ------------------------------------------------------------------------------------------------------------|
| `Kubernetes_Task_Overview.md` | Overview of K8s concepts organised by DevOps work phases. Use as a theory reference while doing exercises. |

---

## Quick Cluster Decision Guide

| Situation | Use |
|---|---|
| Just starting, want to begin in 5 minutes | `kind create cluster` (Option A in 00-Setup.md) |
| No install at all, browser only | Killercoda (Tasks 01–05 only) |
| Local cluster, Tasks 01–05 | kind 2-node (Option A) |
| NetworkPolicies must be enforced (Task 03) | kind + Calico (Option A2 in 00-Setup.md) |
| Heavy workloads — Prometheus, ArgoCD, etcd (Tasks 06–08) | Oracle Free Tier (Option B) — always free |
| Real node failure simulation (Task 07) | Oracle Free Tier **or** AWS EC2 (Options B/C) |
| Want AWS/cloud experience on resume | AWS EC2 + Terraform (Option C) — ~$0.40/session |
| Final project (must persist across weeks) | Oracle Free Tier (best) **or** AWS (Option B/C) |

> All setup instructions, Terraform files, and kubeadm scripts are in `00-Setup.md`.
