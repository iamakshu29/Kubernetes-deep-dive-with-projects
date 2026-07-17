# Kubernetes — Company-Level Proficiency for DevOps Engineers
> Goal: Not exam prep. Learn what a DevOps/Platform engineer actually does with K8s at work — so you can speak from real experience in interviews and contribute on day one.

---

## What Does a DevOps Engineer Actually Do with K8s?

These are the real responsibilities at a company. Everything in this guide maps to one of these:

- Deploying and managing applications on the cluster
- Managing configuration and secrets for different environments
- Setting up CI/CD pipelines that deploy to K8s
- Making applications resilient (health checks, rollouts, autoscaling, PDBs)
- Spreading workloads across nodes/zones to prevent single-point failures
- Managing access for different teams (RBAC, namespaces)
- Enforcing security policies cluster-wide (Kyverno, PSA, securityContext)
- Setting up ingress, TLS, and routing for services (Ingress, cert-manager, Gateway API)
- Monitoring and troubleshooting production workloads (Prometheus, SLOs, incident response)
- Managing storage for stateful applications (PVC, StatefulSets, VolumeSnapshots)
- Packaging apps with Helm for repeatable, environment-aware deployments
- GitOps — making Git the source of truth for cluster state
- Keeping the cluster healthy (cert renewal, node pressure, upgrades)

---

## Roadmap — 4 Phases

### Phase 1: The Platform Mindset (Weeks 1–2)
> Understand K8s as a platform, not a list of resources

| Topic | What You Need to Understand |
|---|---|
| How K8s actually works | The control loop — controllers watch state and reconcile. Not scripts, not shell. |
| Namespaces | Isolation unit at a company. Teams get namespaces, not clusters. |
| Labels and Selectors | How everything is connected — services find pods via labels, not names |
| Pod lifecycle | Pending → Running → Succeeded/Failed/Unknown. What causes each. |
| Resource types mental model | What problem does each resource solve? Not syntax — purpose. |
| ResourceQuota + LimitRange | How platform teams prevent one team from starving another in a shared cluster |
| Pod Security Admission (PSA) | Namespace-level enforcement of security profiles — no root containers without opt-in. Replaced PodSecurityPolicy in K8s 1.25+. |

### Phase 2: Real Application Management (Weeks 3–4)
> What you do when you own an application running on K8s

| Topic | What You Need to Understand |
|---|---|
| Deployments | Rolling updates, rollbacks, strategy types — this is daily work |
| Health probes | Liveness vs Readiness vs Startup — wrong config = production outages |
| Resource requests and limits | Why this matters for scheduling, OOM kills, QoS classes |
| ConfigMaps and Secrets | How apps get configuration. The right patterns vs the wrong ones. |
| Services and DNS | How microservices talk to each other inside the cluster |
| StatefulSets | For databases — why Deployments are wrong for stateful apps |
| Init containers | Gate app startup on dependencies (DB ready, migration complete). Runs before the app starts. |
| PodDisruptionBudget (PDB) | Guarantees minimum available pods during node drains. Without this, maintenance can take your app down. |
| topologySpreadConstraints / podAntiAffinity | Spread replicas across nodes/zones so one node failure doesn't kill all replicas. |
| preStop hook + terminationGracePeriodSeconds | Prevent dropped requests during rolling updates — the most common cause of deployment-time 5xx errors. |

### Phase 3: Platform-Level Concerns (Weeks 5–7)
> What a DevOps engineer owns beyond just deploying apps

| Topic | What You Need to Understand |
|---|---|
| Service types | ClusterIP (internal), NodePort (node-level), LoadBalancer (cloud LB or MetalLB), ExternalName (DNS alias to external resource), Headless (direct pod DNS) |
| Ingress + TLS | How external traffic reaches apps. NGINX Ingress Controller routes by path/host. |
| cert-manager | Automates TLS certificate issuance and renewal. Let's Encrypt or internal CA. No more manual openssl. |
| MetalLB | Gives LoadBalancer services a real external IP on bare-metal/local clusters where no cloud LB exists. |
| externalTrafficPolicy | `Local` preserves real client IP through NodePort/LB. `Cluster` (default) SNAT's to node IP. Matters for logging, rate limiting. |
| Gateway API | The replacement for Ingress. HTTPRoute + Gateway separates platform concerns from app routing. Where the ecosystem is heading. |
| NetworkPolicies | Default: every pod can talk to every pod. Lock it down with zero-trust policies. Requires Calico or Cilium — not kindnet. |
| RBAC | How to give a team access to only their namespace. Service accounts for CI/CD. |
| Kyverno | Policy engine that enforces rules at admission time — require resource limits, block root containers, restrict registries. Complements RBAC. |
| Persistent Storage | PV, PVC, StorageClasses. How a DB keeps data after pod restart. |
| VolumeSnapshots | K8s-native PVC backup mechanism. Take a snapshot before a risky migration, restore if it goes wrong. |
| HPA and Autoscaling | HPA scales pods on CPU/memory/custom metrics. Cluster Autoscaler scales nodes when pods can't be scheduled. Both needed together. |
| Helm | Package manager for K8s. Templates + values files = one chart for dev/staging/prod. `helm upgrade --install --atomic` in CI/CD. |
| Multi-environment setup | How dev/staging/prod is managed. Helm values per environment. ArgoCD ApplicationSet for GitOps multi-env. |

### Phase 4: Production Reality (Weeks 8–10)
> The things that matter when something goes wrong at 2am

| Topic | What You Need to Understand |
|---|---|
| Troubleshooting methodology | Symptom → layer → cause. Never guess. Commands: describe, logs, events, exec, endpoints. |
| Monitoring with Prometheus + Grafana | Metrics collection, PromQL, alerting rules, dashboards. kube-prometheus-stack via Helm. |
| SLO-based alerting | Alert on user-facing indicators (success rate, latency), not infrastructure metrics (CPU). Error budgets drive deployment decisions. |
| Cluster Autoscaler | HPA scales pods. CA scales nodes. HPA + CA together = full auto-scaling. CA won't scale down nodes with PDB violations. |
| Secret management patterns | External Secrets Operator or Vault — not raw K8s secrets in Git |
| GitOps with ArgoCD | Git is the source of truth. CD is automated via reconciliation. Drift detection. |
| Node management | Draining (respects PDB), cordoning, upgrading nodes without downtime |
| Certificate expiry | kubeadm cluster certs expire after 1 year. `kubeadm certs check-expiration` + `renew all`. Automate or get paged at 3am. |
| Node pressure conditions | DiskPressure / MemoryPressure trigger pod eviction. QoS class (BestEffort → Burstable → Guaranteed) determines eviction order. |
| Security hardening | Pod Security Admission (restricted profile), Kyverno policies, running as non-root, read-only filesystems, dropped capabilities |

---

## SETUP — Cluster for These Exercises

The quick concept-check tasks in this file (1.1, 1.2, 2.1 etc.) run on a **kind single-node or 2-node cluster**.

**Full setup instructions, all options (kind, Oracle Free Tier, AWS), and task-to-cluster mapping are in `K8s-Exercises/00-Setup.md`.** Read that first.

**Quick start for these reference exercises (if kind is already installed):**
```bash
kind create cluster --name devops-lab
kubectl get nodes   # single control-plane node, Ready
```

For Tasks 1.1–2.5 (Phase 1 and 2 concept checks), a single-node cluster is sufficient.
For Tasks 3.1–4.4 (Phase 3 and 4), use the kind 2-node setup from `00-Setup.md` Option A1.

**Base images used in all exercises below:**
| Role | Image |
|---|---|
| Backend API | `hashicorp/http-echo` |
| Frontend | `nginx:alpine` |
| Database | `postgres:15` or `redis:7` |
| Debug / curl | `busybox` or `alpine` |

---

## EXERCISES — Phase 1: The Platform Mindset

> **Rules:** No answers provided here. Use `kubectl explain <resource>`, official docs at kubernetes.io, and `kubectl describe` to figure things out. The struggle is the learning.

---

### Task 1.1 — Namespace Isolation
**Scenario:** Your company has two teams — `team-alpha` and `team-beta`. They share a cluster but must not see each other's workloads by default.

**What to accomplish:**
- Create two namespaces for the teams
- Deploy an `nginx:alpine` pod in each namespace
- Verify each team's pod only appears when querying their namespace
- Set your kubeconfig context to default to `team-alpha` so `-n` flag is not needed every time

**Think about this:** What happens to all resources inside a namespace when you delete the namespace?

---

### Task 1.2 — Labels and Selectors Deep Dive
**Scenario:** You have 5 pods running. Some belong to `app: frontend`, some to `app: backend`. Some are `env: prod`, some are `env: staging`.

**What to accomplish:**
- Deploy 5 pods manually (not via Deployment) with varying label combinations
- Without deleting anything, list only prod pods using label selectors
- List only backend pods
- List pods that are BOTH backend AND prod
- Create a Service and deliberately point it to the wrong pods via a mislabelled selector — confirm nothing is reachable through it

**Think about this:** This is exactly how services find pods in production. A wrong label in a Service selector is a real and common production bug.

---

### Task 1.3 — Watch the Control Loop in Action
**Scenario:** You want to see K8s reconciliation happen live.

**What to accomplish:**
- Create a Deployment with 3 replicas
- While watching `kubectl get pods -w`, manually delete one pod
- Observe what happens and measure how fast it recovers
- Identify: which K8s component is responsible for this? Where does it run in your cluster?
- Scale the Deployment to 0 replicas, then back to 3 — using only imperative commands, not YAML edits

**Think about this:** If the component responsible for reconciliation crashes, what happens to your already-running pods?

---

## EXERCISES — Phase 2: Real Application Management

---

### Task 2.1 — Deploy a Multi-Tier Application
**Scenario:** Company requirement — deploy a backend API and a frontend. The frontend must be reachable from a browser. The backend must only be reachable from inside the cluster.

**What to accomplish:**
- Deploy `hashicorp/http-echo` as a backend (use arg `-text="Hello from backend"`)
- Deploy `nginx:alpine` as a frontend
- Make the frontend accessible from your browser on your laptop
- Make the backend reachable from within the frontend pod but not from outside
- Prove it: exec into the frontend pod and curl the backend. Then try to curl the backend from your laptop directly — it should fail.

**Think about this:** What service types are you choosing for each, and why? Be ready to explain this in an interview.

---

### Task 2.2 — Health Probes Done Right
**Scenario:** An app takes 30 seconds to start but K8s kills it before it's ready. Another app has a deadlock but K8s reports it as healthy.

**What to accomplish:**
- Deploy `nginx:alpine` with a Readiness probe checking `/` on port 80
- Add a Liveness probe — then manually break something inside the running pod and watch what K8s does
- Add a StartupProbe to handle the slow-start case
- Set a probe with a deliberately wrong port number — watch what happens to the rollout

**Think about this:** What is the exact difference in K8s behaviour when a Liveness probe fails vs when a Readiness probe fails? These have completely different outcomes.

---

### Task 2.3 — Configuration and Secrets
**Scenario:** Your app needs non-sensitive config (log level, feature flags) and sensitive config (DB password). Dev and prod have different values.

**What to accomplish:**
- Create a ConfigMap with non-sensitive config values
- Create a Secret with a fake DB password
- Inject the ConfigMap as environment variables into a pod
- Mount the Secret as a file at `/etc/secrets/db-password` — not as an env var
- Update the ConfigMap value while the pod is running — does the pod see the update automatically? Why or why not?

**Think about this:** Why is mounting secrets as files considered more secure than environment variables? This is a real interview question.

---

### Task 2.4 — Rolling Updates and Rollbacks
**Scenario:** You deployed a bad version of your app to production. You need to roll back immediately.

**What to accomplish:**
- Deploy `nginx:1.24` with 3 replicas
- Update to `nginx:1.25` with a strategy of `maxUnavailable: 0` and `maxSurge: 1` — watch it roll out pod by pod
- Now update to a broken image (`nginx:doesnotexist`) — observe what happens to the Deployment
- Roll back to the last working version using a single command
- Find: how many rollout history versions does K8s keep by default? How do you increase this?

---

### Task 2.5 — Resource Requests, Limits, and Quotas
**Scenario:** A noisy-neighbour pod is consuming all CPU on a node. Other apps are degraded.

**What to accomplish:**
- Deploy a pod with NO resource settings — what QoS class does it get assigned?
- Deploy a pod with only requests set — what class?
- Deploy a pod with requests equal to limits — what class?
- Create a `LimitRange` in `team-alpha` namespace that sets a default request and limit for all pods
- Create a `ResourceQuota` in `team-alpha` that caps total CPU and memory for the namespace
- Try to deploy a pod that exceeds the quota — what does the error look like?

**Think about this:** Why do companies always enforce ResourceQuota per team namespace in a shared cluster?

---

## EXERCISES — Phase 3: Platform-Level Concerns

---

### Task 3.1 — Ingress and TLS
**Scenario:** Three microservices, one domain, different URL paths. All traffic over HTTPS.

**What to accomplish:**
- Deploy 3 instances of `hashicorp/http-echo` with different response texts
- Create one Ingress that routes `/api/users`, `/api/orders`, and `/` to the three services respectively
- Access all three paths from your browser via `localhost`
- Add TLS: generate a self-signed certificate with `openssl`, store it as a Secret, attach it to your Ingress

**Think about this:** What does `cert-manager` automate that you just did manually? Why do companies use it?

---

### Task 3.2 — RBAC for Teams
**Scenario:** A developer should view pods and read logs in their namespace but not modify anything. A CI/CD pipeline needs to deploy (create/update) workloads in the same namespace.

**What to accomplish:**
- Create a ServiceAccount for the developer with read-only access to pods and logs in `team-alpha` only
- Create a ServiceAccount for CI/CD with permission to create and update Deployments and Services in `team-alpha`
- Verify both using `kubectl auth can-i`
- Try to delete a pod using the developer SA — it should be denied
- Extract the CI/CD ServiceAccount token and use it to authenticate a kubectl command — simulating what Jenkins or GitHub Actions does

---

### Task 3.3 — Persistent Storage
**Scenario:** Your PostgreSQL pod restarted and all the data is gone.

**What to accomplish:**
- Deploy `postgres:15` as a plain Deployment with no persistent volume — write data, delete the pod, confirm data is lost
- Redeploy PostgreSQL as a StatefulSet with a PersistentVolumeClaim
- Write data again, delete the pod, verify the data survives the restart
- Find: what is the reclaim policy on your PV? What happens to the data if you delete the PVC?
- Simulate a node failure: cordon one worker node, delete the pod, observe where it gets rescheduled and whether data is still accessible

---

### Task 3.4 — Horizontal Pod Autoscaler
**Scenario:** Traffic spikes happen. Your app needs to scale out automatically and scale back in when traffic drops.

**What to accomplish:**
- Deploy an app with CPU requests defined (HPA requires this)
- Create an HPA targeting 50% average CPU, minimum 1 pod, maximum 5 pods
- Generate CPU load inside a pod (use a shell loop or `stress`) — watch pods scale out
- Stop the load — watch pods scale back in
- Find: what is the default cooldown period before scale-down triggers? Why is scale-down deliberately slower than scale-up?

---

### Task 3.5 — Build a Helm Chart from Scratch
**Scenario:** Every environment deployment means manually editing YAML. This is error-prone and not scalable.

**What to accomplish:**
- Take the multi-tier app from Task 2.1 and convert it into a Helm chart
- Chart must support: configurable image tag, replica count, resource limits, and service type
- Create separate `values-dev.yaml` and `values-prod.yaml` with meaningfully different settings
- Deploy to `team-alpha` namespace using dev values
- Upgrade the chart with a new image tag — without touching any YAML directly
- Roll back the Helm release to the previous version

**Think about this:** Where does Helm store its release state? What namespace is it in?

---

## EXERCISES — Phase 4: Production Reality

---

### Task 4.1 — Troubleshooting Scenarios
**Scenario:** Things are broken. Diagnose without being told what's wrong.

Deploy each of the following and find the root cause yourself:

**Broken Scenario A:**
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: broken-a
spec:
  containers:
  - name: app
    image: nginx:alpine
    resources:
      requests:
        memory: "200Gi"
```

**Broken Scenario B:**
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: broken-b
  labels:
    app: backend
spec:
  containers:
  - name: app
    image: nginx:alpine
    ports:
    - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: backend-svc
spec:
  selector:
    app: backend-service
  ports:
  - port: 80
    targetPort: 80
```
The pod is Running. The Service exists. But nothing can reach the pod through the Service. Why?

**Broken Scenario C:**
A pod is in CrashLoopBackOff. It starts, runs 2 seconds, then crashes. The container is not currently running. How do you retrieve the logs from the crashed (previous) container instance?

---

### Task 4.2 — NetworkPolicies (Zero Trust Inside the Cluster)
**Scenario:** By default every pod can reach every other pod. Lock it down to least-privilege.

**What to accomplish:**
- Deploy three pods: `frontend`, `backend`, `database`
- Confirm they can all reach each other (curl between them)
- Apply NetworkPolicies so that:
  - `frontend` → `backend`: allowed
  - `backend` → `database`: allowed
  - `database` → anything: blocked
  - `frontend` → `database`: blocked
  - External ingress → `frontend`: allowed (via Ingress controller namespace)
  - Everything else: denied by default
- Verify each rule works and each blocked path fails correctly

---

### Task 4.3 — GitOps with ArgoCD
**Scenario:** Your team wants to stop running `helm upgrade` manually. Every Git push should trigger a deployment.

**What to accomplish:**
- Install ArgoCD into your kind cluster
- Push your Helm chart from Task 3.5 to a GitHub repository
- Create an ArgoCD Application resource pointing to that repo
- Make a change to `values-dev.yaml` in Git — ArgoCD should detect and sync it
- Manually edit a Deployment in the cluster (drift the live state from Git) — observe ArgoCD detect and repair the drift
- Understand and configure the difference between auto-sync and manual sync

---

### Task 4.4 — Monitoring Stack
**Scenario:** You need visibility into pod health, resource usage, and alerts when things go wrong.

**What to accomplish:**
- Install `kube-prometheus-stack` via Helm (includes Prometheus, Grafana, AlertManager, default dashboards)
- Access Grafana and explore the default Kubernetes workload dashboards
- Write a PromQL query that returns all pods that have restarted more than 3 times
- Create a PrometheusRule alert that fires when any pod in `team-alpha` is in CrashLoopBackOff
- Trigger the alert intentionally — confirm it appears in AlertManager

---

## What to Say in Interviews

After completing these exercises, you can answer these common interview questions from real experience:

| Question | Exercise It Maps To |
|---|---|
| How do you handle zero-downtime deployments? | Task 2.4 — rolling strategy, probes gating traffic |
| How do you manage secrets in K8s? | Task 2.3 — file vs env var, and why |
| How do you handle multi-tenancy in a shared cluster? | Tasks 1.1, 2.5, 3.2, 4.2 |
| How does your CI/CD pipeline deploy to K8s? | Tasks 3.2, 3.5, 4.3 |
| How do you debug a production issue? | Task 4.1 — methodology: events → describe → logs → exec |
| How do you handle autoscaling? | Task 3.4 — HPA, cooldown, metrics |
| How does your team manage multiple environments? | Task 3.5 — Helm values per env |

---

## Free Platforms to Practice

| Platform | Best For |
|---|---|
| **kind** (local) | All exercises above — full control, persistent |
| **Killercoda** | Scenarios without local setup, good for Phase 1–2 |
| **Oracle Cloud Free Tier** | Persistent cloud cluster, real node management, Phase 4 |
| **Civo Cloud** ($250 credit) | Managed K3s, test real LoadBalancer and cloud integrations |

---

*Last updated: July 2026*
