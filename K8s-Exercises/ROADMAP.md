# K8s Deep Dive — Learning Roadmap
> Goal: Company-level Kubernetes proficiency for a DevOps / Platform Engineering role.
> Not exam prep. Real skills, real scenarios, real projects.

---

## How to Use These Files

There are two layers. Use them together — one informs, the other builds skill.

### Layer 1 — `K8s-Company-Level-Reference.md` (outside this folder)
This is your **map and warm-up**. Read one phase at a time.
- Explains WHAT each K8s concept is and WHY it matters at a company
- Has short 5–15 min concept-check tasks (1.1, 2.3, 3.5 etc.) — just enough to verify you understood it
- Not a deep dive. Not a project. Just "do I get this concept?"

### Layer 2 — This folder (`K8s-Exercises/`)
This is your **actual lab**. One task at a time, in order.
- Each task is a 2–3 hour deep dive on one topic
- Real scenarios, debugging problems, interview prep questions
- Ends with a mini-project that produces GitHub-ready deliverables

---

## The Right Way to Work Through This

```
Open K8s-Company-Level-Reference.md
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
  │       └──▶ Task-03 → Task-04 → Task-05 (deep dives + mini projects)
  │
  └── Read Phase 4 (Weeks 8–10)
        Do quick tasks 4.1 → 4.4 inside that file
          │
          └──▶ Task-06 → Task-07 (deep dives + mini projects)
                │
                └──▶ Task-08 — Final Project (capstone, goes on GitHub + resume)
```

---

## Learning Flow (simplified)

```
00-Setup.md  ←  Do this FIRST, once only
    │
    ▼
Task-01  →  Task-02  →  Task-03  →  Task-04
                                        │
                                        ▼
                    Task-08 (Final)  ←  Task-07  ←  Task-06  ←  Task-05
```

---

## File Index

### `00-Setup.md`
**What:** Build a real 2-node kubeadm cluster on your laptop using Multipass (free, lightweight VMs).
**Cluster:** master VM + worker1 VM — real K8s, not a simulation.
**Do this once before starting any task.**

---

### `Task-01 — Namespaces, Contexts & Multi-Team Management`
**What you learn:**
- How companies organise clusters by teams and environments using namespaces
- ResourceQuota — cap CPU/memory/pod count per team
- LimitRange — enforce default resource settings so devs can't forget
- kubectl contexts — switching between clusters and namespaces safely

**Mini project:** Set up a full multi-team namespace structure with quotas, LimitRanges, and a context-switching script. Deliverables go to GitHub.

**Cluster:** Any single-node — minikube, kind, or Killercoda (browser, no install).

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

**Mini project:** Deploy a resilient 2-tier app (API + Redis) with probes, HPA, rolling updates. Show v1 → v2 rollout and rollback.

**Cluster:** kind 2-node or `minikube --nodes 2`. metrics-server required for HPA.

---

### `Task-03 — Networking, Services & Ingress`
**What you learn:**
- ClusterIP, NodePort, LoadBalancer — when to use each
- DNS and service discovery — how pods talk to each other by name
- Ingress — routing external traffic to multiple services via one IP
- NetworkPolicies — zero-trust between pods and namespaces
- Debugging network issues — the systematic approach

**Mini project:** 3 services behind one Ingress with path routing. NetworkPolicies that block frontend→database but allow api→database. Proven with curl from inside pods.

**Cluster:** kind + Calico CNI, or Killercoda (has Calico by default). Default kindnet does NOT enforce NetworkPolicies.

---

### `Task-04 — Storage: Persistent Data`
**What you learn:**
- Why pod storage is ephemeral and why that matters
- PersistentVolume, PersistentVolumeClaim, StorageClass — the full chain
- Dynamic provisioning — devs get storage without asking the platform team
- StatefulSets — the right way to run databases (ordered, stable identity, own PVC)
- emptyDir and sidecar patterns
- Debugging: PVC pending, permission denied, ReadWriteOnce conflicts

**Mini project:** PostgreSQL StatefulSet with PVC. Prove data survives pod deletion. Document what happens to the PVC if the StatefulSet is deleted.

**Cluster:** kind 2-node or Multipass. Multipass required for node-failure simulation.

---

### `Task-05 — RBAC & Security`
**What you learn:**
- Roles and ClusterRoles — namespaced vs cluster-wide permissions
- RoleBindings and ClusterRoleBindings — who gets what
- ServiceAccounts — identity for pods and CI/CD pipelines
- Pod securityContext — non-root, read-only filesystem, dropped capabilities
- Secrets security — why raw K8s secrets are not enough and what companies use instead

**Mini project:** Three ServiceAccounts (viewer, deployer, admin) with precise RBAC. A secure deployment that runs non-root with all capabilities dropped. Proven with `kubectl auth can-i` tests.

**Cluster:** Any single-node. Killercoda works perfectly.

---

### `Task-06 — Observability: Metrics, Logs & Alerting`
**What you learn:**
- metrics-server — `kubectl top` for quick resource checks
- Prometheus + Grafana via Helm — the industry standard stack
- PromQL — writing queries to answer real operational questions
- PrometheusRule — creating alerts that fire before users notice
- Logs — `kubectl logs` patterns + centralised logging with Loki
- ServiceMonitor — making Prometheus scrape your own app's metrics

**Mini project:** Full monitoring setup for team-alpha's API. Custom Grafana dashboard, two alert rules, triggered alert screenshot, exported dashboard JSON for GitHub.

**Cluster:** 3-node with 6GB+ RAM. Oracle Cloud Free Tier (always free) or Civo Cloud ($250 credit) recommended. Heavy stack — not suitable for Killercoda.

---

### `Task-07 — Troubleshooting: Debugging a Broken Cluster`
**What you learn:**
- The systematic debugging mindset — symptom → layer → cause
- Diagnosing: Pending, CrashLoopBackOff, ImagePullBackOff, OOMKilled
- Debugging service connectivity — endpoints, DNS, exec+curl
- Node NotReady — simulate and recover
- etcd backup and restore — disaster recovery

**Mini project:** A self-imposed broken cluster (4 simultaneous issues). Find and fix all of them, then write a proper incident report in post-mortem format.

**Cluster:** Multipass (master + worker1) for node-stop simulation and etcd access. Killercoda for Scenarios 1–4.

---

### `Task-08 — Real-World Final Project` ← Capstone
**What you build:**
A production-grade application platform on K8s — end to end.

| Component | What |
|---|---|
| Application | FastAPI (Python) + PostgreSQL StatefulSet |
| Packaging | Helm chart with dev/prod values |
| GitOps | ArgoCD watching GitHub repo, auto-sync |
| CI/CD | GitHub Actions or Jenkins — build image → update manifest → ArgoCD deploys |
| Security | RBAC per component, NetworkPolicies (zero-trust), non-root pods, Secrets |
| Observability | Prometheus metrics from FastAPI, Grafana dashboard, 3 alert rules |

**This goes on your GitHub. Walk through it in interviews.**

**Cluster:** Oracle Free Tier (best) or Multipass. Persistent across sessions — kind/Killercoda not suitable.

---

## Reference File

| File | Purpose |
|---|---|
| `K8s-Company-Level-Reference.md` | Overview of K8s concepts organised by DevOps work phases. Use as a theory reference while doing exercises. |

---

## Quick Cluster Decision Guide

| Situation | Use |
|---|---|
| Just starting, don't want to set up anything | Killercoda (browser, free, instant) |
| Local cluster, Tasks 01–05 | `kind create cluster` or `minikube start` |
| Need NetworkPolicies enforced | kind + Calico, or Killercoda |
| Need real node failure simulation | Multipass (Task 07) |
| Heavy workloads — Prometheus, ArgoCD | Oracle Free Tier or Civo Cloud |
| Final project (persistent, multi-session) | Oracle Free Tier or Multipass |

---

*Start with `00-Setup.md`. Come back to this file whenever you need to orient yourself.*
