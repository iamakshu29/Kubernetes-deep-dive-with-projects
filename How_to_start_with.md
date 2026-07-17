# How to Start — K8s Learning Repo

This repo is a structured, company-level K8s learning path built for someone who already knows the basics and wants production-grade proficiency. Not exam prep. Real DevOps engineer skills.

---

## What's in This Repo

```
K8s-Company-Level-Reference.md   → Theory: WHY each concept exists at a company level
                                    4 phase tables mapping topics to real DevOps responsibilities
                                    Quick concept-check tasks (skip if you already know K8s basics)

K8s-Exercises/
  00-Setup.md                    → Cluster setup guide — kind, Oracle Free Tier, AWS+Terraform
  ROADMAP.md                     → Full learning path overview, task descriptions, cluster guide
  Task-01 → Task-05              → Core K8s: namespaces, workloads, networking, storage, RBAC
  Task-05b-Helm.md               → Helm: packaging and deploying apps at scale
  Task-06 → Task-07              → Production: observability, troubleshooting
  Task-08-Real-World-Project.md  → Capstone: FastAPI + PostgreSQL + ArgoCD + CI/CD + Prometheus
```

---

## Pre-Requisites — Do These Before Anything Else

- [ ] Docker Desktop installed and running (required for kind clusters)
- [ ] kind installed: `choco install kind`
- [ ] kubectl installed: `choco install kubernetes-cli`
- [ ] Helm installed: `choco install kubernetes-helm`
- [ ] A GitHub account (mini-projects go here)
- [ ] For Tasks 06–08: Oracle Cloud Free Tier account OR AWS account with Terraform installed

Read **`K8s-Exercises/00-Setup.md`** — it covers all cluster options, when to use each, and has Terraform files for AWS if you go that route.

---

## File Reading Order

Do NOT try to read everything first. Use this pattern — one phase at a time:

```
1. K8s-Exercises/00-Setup.md          → Read once, set up your cluster
2. K8s-Exercises/ROADMAP.md           → Skim once to understand the full path
3. K8s-Company-Level-Reference.md     → Read one Phase table JUST BEFORE the matching task
4. K8s-Exercises/Task-XX              → Do the actual work here
```

---

## The Workflow — Per Task

| Before this task | Read this in the reference file first (5 min) | Then do |
|---|---|---|
| Task-01 | Phase 1 table | Task-01-Namespaces-and-Context.md |
| Task-02 | Phase 2 table | Task-02-Workloads.md |
| Task-03 | Phase 3 — service types, ingress, networking rows | Task-03-Networking-and-Ingress.md |
| Task-04 | Phase 3 — Persistent Storage, VolumeSnapshots rows | Task-04-Storage.md |
| Task-05 | Phase 3 — RBAC, Kyverno, PSA rows | Task-05-RBAC-and-Security.md |
| Task-05b | Phase 3 — Helm row | Task-05b-Helm.md |
| Task-06 | Phase 4 — Prometheus, SLO alerting, Cluster Autoscaler rows | Task-06-Observability.md |
| Task-07 | Phase 4 — Troubleshooting, cert expiry, node pressure rows | Task-07-Troubleshooting.md |
| Task-08 | Skim Phase 3 + 4 as a full review | Task-08-Real-World-Project.md |

---

## Where to Start Right Now

**Returning after a gap — run this to verify your cluster is working:**
```bash
kind get clusters
kubectl get nodes
```
If no cluster exists:
```bash
kind create cluster --name devops-lab --config K8s-Exercises/kind-2node.yaml
# kind-2node.yaml config is inside 00-Setup.md Option A1 — copy it out first
```

**Starting fresh — first command:**
```bash
# 1. Read 00-Setup.md Option A1 — copy out kind-2node.yaml, save it locally
# 2. Create cluster
kind create cluster --name devops-lab --config kind-2node.yaml
# 3. Install add-ons (ingress + metrics-server)
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl patch deployment metrics-server -n kube-system \
  --type='json' \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
# 4. Verify
kubectl get nodes   # both Ready
# 5. Open Task-01
```

---

## Rules for Getting the Most Out of This

1. **Do not just read — run every command.** K8s is muscle memory. Reading without doing builds false confidence.
2. **Complete each mini-project and push it to GitHub.** This is your portfolio. It proves you can do this.
3. **Write down your debugging steps.** Task-07 has an incident report format — use it from Task-01 onwards.
4. **When something breaks, don't Google immediately.** Spend 10 minutes debugging with `kubectl describe`, `kubectl logs`, and `kubectl get events` first. This is the real skill.
5. **The concept-check tasks in the reference file (1.1, 1.2 etc.) are optional if you already know K8s.** Skip them and go straight to the exercise task.

---

## Quick Cluster Reference

| Need | Command |
|---|---|
| Check what clusters exist | `kind get clusters` |
| Check nodes | `kubectl get nodes` |
| Create standard 2-node cluster | `kind create cluster --name devops-lab --config kind-2node.yaml` |
| Delete and recreate (clean state) | `kind delete cluster --name devops-lab && kind create cluster --name devops-lab --config kind-2node.yaml` |
| Switch to a different cluster context | `kubectl config use-context kind-devops-lab` |
| For Tasks 06-08 (heavy workloads) | See 00-Setup.md Option B (Oracle Free Tier) or Option C (AWS) |
