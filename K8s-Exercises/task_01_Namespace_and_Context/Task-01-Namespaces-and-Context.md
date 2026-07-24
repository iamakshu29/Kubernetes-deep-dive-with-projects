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
- Pod Security Admission Standards

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
   ```bash
   kubectl create ns <ns-name>
   ```
2. Label each namespace with `team=alpha`, `team=beta`, `env=staging`, `env=monitoring` respectively
   ```bash
   kubectl label <resource_type> <resource_name> <key>=<value>
   kubectl label ns staging env=staging
   ```
3. Verify all namespaces exist with their labels
   ```bash
   kubectl get ns --show-labels
   ```
4. List only namespaces that belong to a specific team using label selectors
   ```bash
   kubectl get <resource_type> --selector=<key>=<value>
   kubectl get ns --selector=env=staging
   kubectl get ns --selector=env    # filter by key only
   ```

**You should know how to answer:**

- **Why not just use one namespace for everything?**

  Using one namespace gives zero isolation. Namespaces are needed for:
  - **RBAC** — scope roles per namespace; team-alpha cannot touch team-beta's resources
  - **ResourceQuota** — cap CPU/memory/pod counts per team independently
  - **NetworkPolicy** — block cross-team traffic at the network level
  - **Blast radius** — a bad deployment in one namespace cannot directly affect another
  - **Operational clarity** — `kubectl get pods -n team-alpha` shows only that team's workloads

- **What happens to resources when you delete a namespace?**

  All namespace-scoped resources are deleted immediately. Cluster-scoped resources (nodes, PVs, CRDs, ClusterRoles) remain unaffected.

---

## Exercise 2 — ResourceQuota (Preventing Resource Abuse)

> **⚠️ Important:** When using a `deployment` instead of standalone Pods, the quota `Forbidden` error surfaces at the **ReplicaSet** level (pod creation stage), not on the deployment itself. Check it with:
> ```bash
> kubectl describe rs <rs-name> -n team-alpha
> ```

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

   **Answer:** The API server returns a `Forbidden` error — quota exceeded.

2. Check quota usage with `kubectl describe`
   ```bash
   kubectl get resourcequota <quota_name> -n <ns_name>
   # OR
   kubectl describe ns team-alpha
   ```

**You should know how to answer:**

- **What is the difference between requests and limits in a quota?**

  In a ResourceQuota, both are namespace-level caps — they track different aggregates:

  | Field | What it caps |
  |---|---|
  | `requests.cpu` / `requests.memory` | Sum of all pod **requests** across the namespace (used by scheduler) |
  | `limits.cpu` / `limits.memory` | Sum of all pod **limits** across the namespace (runtime maximum) |

  > This is different from pod-level: at pod level `requests` = guaranteed minimum and `limits` = runtime maximum per container.

- **What happens to existing pods if you add a quota after they are already running?**

  Existing pods keep running unchanged. A quota only applies to **new resource creation** after it is set — existing pods are never restarted or evicted. However, once a pod is deleted and recreated (e.g., rolling update), the new pod must fit within the quota.

---

## Exercise 3 — LimitRange (Default Resource Limits)

**Scenario:** Developers in `team-beta` keep forgetting to set resource requests on their pods. This causes the scheduler to make poor decisions. You need to enforce defaults.

**Your task:**
Apply a LimitRange to `team-beta` that sets:
- Default CPU request: `100m`, limit: `500m`
- Default memory request: `128Mi`, limit: `256Mi`
- Min CPU: `50m`, Max CPU: `1`

> Verify LimitRange applied: `kubectl describe ns team-beta`

Then:
1. Deploy a pod in `team-beta` **without any resource requests** and check what limits got applied

   **Answer:** LimitRange defaults are injected automatically — `cpu request: 100m`, `cpu limit: 500m`, `memory request: 128Mi`, `memory limit: 256Mi`.

2. Try to deploy a pod requesting `2` CPU and observe the rejection

   **Answer:** Rejected — `maximum cpu usage per Container is 1, but limit is 2`.

---

## Exercise 4 — Contexts (Managing Multiple Clusters)

**Scenario:** You manage 3 clusters — dev, staging, prod. You need to switch between them safely without risk of running a command on the wrong cluster.

**Your task:**
1. View your current kubeconfig with `kubectl config view`
   ```bash
   kubectl config view
   ```
   > Contains 3 objects: **cluster** (API server endpoint + cert), **user** (credentials/token), **context** (cluster + user + optional namespace).

2. Rename your current context to `k8s-dev` (it represents your dev cluster)
   ```bash
   # Changes only the context name
   kubectl config rename-context <current_name> <updated_name>
   kubectl config rename-context kind-devops-lab k8s-dev

   # Verify
   kubectl config get-contexts
   ```

3. Set your default namespace for the `k8s-dev` context to `team-alpha` so you don't have to type `-n team-alpha` every time
   ```bash
   kubectl config get-contexts
   kubectl config set-context <context_name> --namespace=team-alpha

   # Verify — team-alpha pods should appear without -n flag
   kubectl get pods
   ```

4. Simulate having a second cluster by creating a second context pointing to the same cluster but with namespace `team-beta` — name it `k8s-dev-beta`
   ```bash
   kubectl config set-context k8s-dev-beta --cluster=kind-devops-lab --user=kind-devops-lab --namespace=team-beta
   kubectl config get-contexts
   ```

5. Switch between contexts and verify that `kubectl get pods` shows the right namespace without specifying `-n`
   ```bash
   kubectl config get-contexts                  # list all contexts

   kubectl config use-context <context_name>                    
   kubectl config use-context k8s-dev-beta
   
   kubectl get pods                               # should show team-beta pods
   kubectl config get-contexts                    # verify active context (*)
   ```

**Bonus task:** Write a one-liner shell alias that shows you the current context and namespace in your terminal prompt. This is something real DevOps engineers do.
```
echo "Context: $(kubectl config current-context), $(kubectl config view --minify | grep namespace)"

# For alias
alias kctx='echo "Context: $(kubectl config current-context), $(kubectl config view --minify | grep namespace)" 2>/dev/null || echo default'
```


**You should know how to answer:**

- **What is the difference between a context, a cluster, and a user in kubeconfig?**

  - **Cluster** — where to connect: API server endpoint + certificate authority
  - **User** — how to authenticate: token, client cert, or auth plugin (e.g., exec)
  - **Context** — binding of cluster + user + optional default namespace

- **Why do we use contexts?**

  Contexts let you switch between different Kubernetes clusters or namespaces without modifying the kubeconfig or passing flags on every command.

- **How do you prevent accidentally running `kubectl delete` on production?**

  Use separate contexts per environment. Always verify active context before destructive commands (`kubectl config current-context`). Enforce RBAC to restrict delete permissions in production. Route all production changes through CI/CD, not manual `kubectl`. Use `--dry-run=client` when testing. Add a context-aware shell prompt so the active cluster is always visible.

---

## Exercise 5 — Namespace Cleanup

**Scenario:** `team-alpha` project is decommissioned. You need to clean it up safely.

**Your task:**
1. List all resources inside `team-alpha` before deleting (pods, services, configmaps, secrets, deployments)
   ```bash
   kubectl get all,cm,secret,pvc -n team-alpha
   ```
2. Delete the namespace
   ```bash
   kubectl delete ns team-alpha
   ```
3. Observe that all resources inside were automatically removed
4. What would have happened if a PersistentVolumeClaim was in that namespace?

   **Answer:** The PVC is deleted with the namespace (it's namespace-scoped). What happens to the underlying PV depends on the reclaim policy:

   | Reclaim Policy | What happens to storage |
   |---|---|
   | `Delete` | Storage backend (EBS, Azure Disk, GCE PD) is **permanently deleted** |
   | `Retain` | PV stays in `Released` state — data survives, admin must manually recover |
   | `Recycle` *(deprecated)* | Volume is scrubbed and made available again |

   > Always use `Retain` for production storage — `Delete` reclaim policy + namespace deletion = permanent data loss.
---

## Exercise 6 — Pod Security Admission Standards

**Scenario:** Security team requires that `team-alpha` namespace enforces strict security posture — no root containers, no privilege escalation, no host namespaces. You must do this at the namespace level so it applies automatically to every pod deployed there, without relying on developers remembering to set `securityContext`.

**Background:** Pod Security Admission (PSA) is built into K8s 1.25+. It replaces the old PodSecurityPolicy. You label a namespace to enforce one of three profiles:
- `privileged` — no restrictions
- `baseline` — blocks the most dangerous settings
- `restricted` — enforced least-privilege (runs as non-root, no privilege escalation, seccomp applied)

The label you select defines what action the control plane takes if a potential violation is detected:
    Mode	     Description
- `enforce` -	Policy violations will cause the pod to be rejected.
- `audit`	- Policy violations will trigger the addition of an audit annotation to the event recorded in the audit log, but are otherwise allowed.
- `warn`	- Policy violations will trigger a user-facing warning, but are otherwise allowed.

**Your task:**
1. Label `team-alpha` to enforce on `baseline` violations and warns and audit `restricted` profile:
  - enforce=baseline - hard floor, blocks only the truly dangerous stuff
  - warn=restricted - tells developers "this pod would fail once we tighten enforcement"
  - audit=restricted - logs it for a compliance report

   ```bash
   kubectl label namespace team-alpha \
     pod-security.kubernetes.io/enforce=baseline \
     pod-security.kubernetes.io/enforce-version=latest \
     pod-security.kubernetes.io/warn=restricted \
     pod-security.kubernetes.io/warn-version=latest \
     pod-security.kubernetes.io/audit=restricted \
     pod-security.kubernetes.io/audit-version=latest
   ```

  ```bash
  kubectl run nginx --image=nginx --dry-run=client -o yaml > psa_pod.yml
  ```
2. Try to deploy a pod that runs as root (no `securityContext`) in `team-alpha` — observe the admission rejection message
  ```bash
    $ kubectl run nginx --image=nginx:1.25
    Warning: would violate PodSecurity "restricted:latest": allowPrivilegeEscalation != false (container "nginx" must set securityContext.allowPrivilegeEscalation=false), unrestricted capabilities (container "nginx" must set securityContext.capabilities.drop=["ALL"]),( runAsNcontainer "nginx" must set securityContext.seccompProfile.type to "RuntimeDefault" or "Localhost")
    pod/nginx created
  ```
> **Note:** Pod is allowed because `restricted` is in `warn`/`audit` mode only here. If it were in `enforce` mode, the pod would be rejected entirely.

3. Deploy the same pod with a proper `securityContext` that satisfies `restricted`:
4. Leave `monitoring` namespace as `privileged` — understand why Prometheus node-exporter and some system tools legitimately need it

**Dig deeper:**

- **What is the difference between `enforce`, `warn`, and `audit` modes?**

  | Mode | Behaviour |
  |---|---|
  | `enforce` | Pod is **rejected** — API server blocks it entirely |
  | `warn` | Pod is created, but a warning is printed to the client |
  | `audit` | Pod is created silently, but the violation is recorded in audit logs |

- **Why did PodSecurityPolicy get removed and what problem did it cause that PSA solves?**

  PSP was removed because it was overly complex:
  - Required PSP object + RBAC Role + RoleBinding just to activate — easy to misconfigure
  - Could silently mutate Pods by injecting defaults, making behaviour unpredictable
  - Policy selection (which PSP applied to which pod) was confusing

  PSA replaces it with a simple namespace-label approach:
  - Label a namespace → enforcement is automatic, no extra objects needed
  - Three predefined profiles: `privileged`, `baseline`, `restricted`
  - PSA only validates, never mutates — behaviour is fully predictable

  For custom rules beyond PSA (registries, label requirements) → use Kyverno or OPA Gatekeeper.

**You should know how to answer:**

- **"How do you prevent developers from deploying root containers without trusting them to set securityContext themselves?"**

  Label the namespace with PSA `enforce=restricted`. The API server validates every pod at admission — pods missing required security fields are rejected before scheduling, regardless of what the developer put in their YAML. For custom rules beyond PSA (image registry restrictions, label requirements) → add Kyverno or OPA Gatekeeper.

- **What is the `restricted` PSA profile and what does it require on every pod?**

  The most secure built-in PSA profile. Every pod must have:
  - `runAsNonRoot: true`
  - `allowPrivilegeEscalation: false`
  - `capabilities.drop: ["ALL"]`
  - `seccompProfile.type: RuntimeDefault` or `Localhost`

---

## Completion Checklist

Before moving to Task 02, you should be able to do all of these without looking at notes:

- [x] Create and label namespaces
- [x] Apply and inspect ResourceQuotas
- [x] Apply and test LimitRanges
- [x] Switch contexts and set default namespaces
- [x] Apply Pod Security Admission labels to enforce security profiles on namespaces
- [x] Explain to an interviewer why namespace isolation matters at a company level

---

## Interview Questions This Task Prepares You For

---

**"How do you manage resource fairness in a shared cluster?"**

- **ResourceQuota** — namespace-level cap: total CPU, memory, pod count, services, configmaps. Prevents one team from starving others.
- **LimitRange** — pod/container-level: sets default requests/limits for pods that don't specify them, and enforces min/max bounds per container. Stops accidental `requests.cpu: 100` pods.
- Together: ResourceQuota = namespace ceiling, LimitRange = per-pod guardrails within that ceiling.

---

**"How do you handle multiple environments in K8s?"**

- **Lightweight isolation** (dev/staging sharing a cluster) — separate namespaces per environment with ResourceQuota, LimitRange, and NetworkPolicies.
- **Strict isolation** (production) — dedicated cluster with its own kubeconfig context. Switch via `kubectl config use-context`.
- GitOps tools (ArgoCD, Flux) deploy to the correct environment by targeting the right context/namespace.

---

**"Walk me through how you manage kubeconfig when dealing with multiple clusters."**

- `~/.kube/config` holds three sections: cluster endpoints, user credentials, and contexts (cluster + user + namespace).
- Multiple clusters: merge into one kubeconfig, or use `KUBECONFIG=~/.kube/dev:~/.kube/prod` to point to multiple files at once.
- Each cluster gets a descriptive context name (`k8s-prod`, `k8s-dev`). Switch with `kubectl config use-context <name>`.
- Set a default namespace per context to avoid `-n` flag mistakes.
- Use `kubectx` / a shell prompt showing active context in production to prevent accidents.

---

**"What happens when a namespace is deleted?"**

- All namespace-scoped resources are **immediately and permanently deleted**: pods, deployments, services, configmaps, secrets, PVCs, ingresses.
- Cluster-scoped resources are unaffected: nodes, PersistentVolumes, ClusterRoles, CRDs.
- PV fate depends on reclaim policy: `Delete` → storage deleted permanently; `Retain` → PV stays in Released state, admin must manually clean up.
- Before deleting a production namespace: back up secrets/configmaps and ensure PVs use `Retain`.

---

**"How do you enforce that no pod in a namespace can run as root, without relying on developers to set it?"**

- Label the namespace with PSA `enforce=restricted`. API server validates every pod at admission — no required `securityContext` fields = pod rejected.
- Restricted requires: `runAsNonRoot: true`, `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, `seccompProfile.type: RuntimeDefault`.
- Enforced at control plane level — developers cannot bypass it via their YAML.
- For custom rules (block specific registries, enforce labels) → Kyverno or OPA Gatekeeper on top of PSA.

---

**"What replaced PodSecurityPolicy and how does it work?"**

- **Pod Security Admission (PSA)**, built into Kubernetes 1.25+.
- PSP removed because: required PSP + RBAC roles + bindings to activate, could silently mutate pods, policy selection was unpredictable — too complex and error-prone.
- PSA approach: label a namespace with a profile (`privileged` / `baseline` / `restricted`) and a mode (`enforce` / `warn` / `audit`). API server validates every pod at admission. No mutation, no extra objects — just namespace labels.

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
  - Default CPU request: `100m`, limit: `500m`
  - Default memory request: `128Mi`, limit: `256Mi`
  - Min CPU: `50m`, Max CPU: `1`
4. A shell script `switch-context.sh` that takes a team name as argument and switches kubectl current context to that team's namespace
5. A `README.md` explaining: what you set up and why each decision was made

**Proof of completion:**
- `kubectl describe quota -n team-alpha` shows your quota applied
- `kubectl config current-context` changes when your script runs
- Deploy a pod that exceeds quota — screenshot the error

---

**Next: Task-02-Workloads.md**
