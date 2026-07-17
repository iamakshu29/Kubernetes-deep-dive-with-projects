# Task 01 — Namespaces, Contexts & Multi-Team Cluster Management

> Real-world relevance: At a company, a K8s cluster is shared by multiple teams.
> A DevOps engineer sets up isolation, access boundaries, and manages who talks to what.
> This is day-1 work when you join a company that runs K8s.

> **Cluster needed:** Any single-node cluster works fine.
> - **Easiest:** `minikube start` or `kind create cluster` — one command, done.
> - **Browser-based (no install):** [Killercoda](https://killercoda.com) → Kubernetes Playground.
> - Multi-node is NOT required here. All namespace and context concepts work on 1 node.

---

## What You Will Learn

- Why namespaces exist and how companies use them
- How to organise a cluster for multiple teams/environments
- kubectl context switching — how you manage multiple clusters in real work
- ResourceQuota and LimitRange — preventing one team from consuming all cluster resources

---

## Background — Read Before Starting

At a company, a single cluster typically has namespaces like:

```
dev         → developers test their apps here
staging     → pre-production environment
production  → live traffic
monitoring  → Prometheus, Grafana live here
infra       → ingress controllers, cert-manager, etc.
team-alpha  → dedicated namespace for one product team
team-beta   → another product team
```

Everything from here forward: you will pretend you are the DevOps engineer managing this cluster for two product teams.

---

## Exercise 1 — Create the Company Namespace Structure

**Scenario:** You have just been given admin access to a fresh cluster. Set it up for two teams.

**Your task:**
1. Create namespaces: `team-alpha`, `team-beta`, `staging`, `monitoring`
2. Label each namespace with `team=alpha`, `team=beta`, `env=staging`, `env=monitoring` respectively
3. Verify all namespaces exist with their labels
4. List only namespaces that belong to a specific team using label selectors

**You should know how to answer:**
- Why not just use one namespace for everything?
- What happens to resources when you delete a namespace?

---

## Exercise 2 — ResourceQuota (Preventing Resource Abuse)

**Scenario:** `team-alpha` is known to deploy too many pods and starve other teams. You need to cap them.

**Your task:**
Apply a ResourceQuota to `team-alpha` that enforces:
- Maximum 10 pods
- Maximum CPU requests: 4 cores total
- Maximum memory requests: 4Gi total
- Maximum 5 ConfigMaps
- Maximum 2 Services

Then:
1. Try to create 11 pods in `team-alpha` and observe what happens
2. Check quota usage with `kubectl describe`

**You should know how to answer:**
- What is the difference between requests and limits in a quota?
- What happens to existing pods if you add a quota after they are already running?

---

## Exercise 3 — LimitRange (Default Resource Limits)

**Scenario:** Developers in `team-beta` keep forgetting to set resource requests on their pods. This causes the scheduler to make poor decisions. You need to enforce defaults.

**Your task:**
Apply a LimitRange to `team-beta` that sets:
- Default CPU request: `100m`, limit: `500m`
- Default memory request: `128Mi`, limit: `256Mi`
- Min CPU: `50m`, Max CPU: `1`

Then:
1. Deploy a pod in `team-beta` **without any resource requests** and check what limits got applied
2. Try to deploy a pod requesting `2` CPU and observe the rejection

---

## Exercise 4 — Contexts (Managing Multiple Clusters)

**Scenario:** You manage 3 clusters — dev, staging, prod. You need to switch between them safely without risk of running a command on the wrong cluster.

**Your task:**
1. View your current kubeconfig with `kubectl config view`
2. Rename your current context to `k8s-dev` (it represents your dev cluster)
3. Set your default namespace for the `k8s-dev` context to `team-alpha` so you don't have to type `-n team-alpha` every time
4. Simulate having a second cluster by creating a second context pointing to the same cluster but with namespace `team-beta` — name it `k8s-dev-beta`
5. Switch between contexts and verify that `kubectl get pods` shows the right namespace without specifying `-n`

**Bonus task:** Write a one-liner shell alias that shows you the current context and namespace in your terminal prompt. This is something real DevOps engineers do.

**You should know how to answer:**
- What is the difference between a context, a cluster, and a user in kubeconfig?
- How do you prevent accidentally running `kubectl delete` on production?

---

## Exercise 5 — Namespace Cleanup

**Scenario:** `team-alpha` project is decommissioned. You need to clean it up safely.

**Your task:**
1. List all resources inside `team-alpha` before deleting (pods, services, configmaps, secrets, deployments)
2. Delete the namespace
3. Observe that all resources inside were automatically removed
4. What would have happened if a PersistentVolumeClaim was in that namespace? Research and write a one-paragraph answer.

---

## Completion Checklist

Before moving to Task 02, you should be able to do all of these without looking at notes:

- [ ] Create and label namespaces
- [ ] Apply and inspect ResourceQuotas
- [ ] Apply and test LimitRanges
- [ ] Switch contexts and set default namespaces
- [ ] Explain to an interviewer why namespace isolation matters at a company level

---

## Interview Questions This Task Prepares You For

- "How do you manage resource fairness in a shared cluster?"
- "How do you handle multiple environments in K8s?"
- "Walk me through how you manage kubeconfig when dealing with multiple clusters."
- "What happens when a namespace is deleted?"

---

## Mini Project — Multi-Team Cluster Onboarding

> Estimated time: 1.5–2 hours. Put this in GitHub under `k8s-practice/task-01/`.

**Scenario:** You just joined a company as the DevOps engineer. A new project is starting with two teams — `team-alpha` (backend) and `team-beta` (frontend). Your job is to onboard them onto the shared cluster.

**Deliverables — you must produce all of these:**

1. A YAML file `namespaces.yaml` that creates both team namespaces with proper team labels
2. A YAML file `quotas.yaml` applying ResourceQuota to each namespace:
   - `team-alpha`: max 8 pods, 2 CPU, 4Gi memory
   - `team-beta`: max 6 pods, 1 CPU, 2Gi memory
3. A YAML file `limitranges.yaml` setting default pod limits for each namespace so devs who forget resource specs don't cause issues
4. A shell script `switch-context.sh` (or PowerShell equivalent) that takes a team name as argument and switches kubectl context to that team's namespace
5. A `README.md` explaining: what you set up and why each decision was made

**Proof of completion:**
- `kubectl describe quota -n team-alpha` shows your quota applied
- `kubectl config current-context` changes when your script runs
- Deploy a pod that exceeds quota — screenshot the error

---

**Next: Task-02-Workloads.md**
