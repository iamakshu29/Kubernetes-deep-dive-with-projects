# Task 02 — Workloads: Deploying and Managing Applications

> Real-world relevance: This is what a DevOps engineer does every day.
> Deploying apps, rolling updates, handling failures, scaling — these are bread-and-butter skills.
> Every answer here should come from muscle memory, not notes.

> **Cluster needed:** 2-node cluster (1 control-plane + 1 worker) so you can see pod distribution.
> - **Recommended:** `kind create cluster --config kind-2node.yaml` (see 00-Setup.md for config) or Multipass 2 VMs.
> - **Browser-based:** Killercoda "Kubernetes 2 Node Cluster" scenario.
> - **HPA exercise specifically** requires `metrics-server` installed — see 00-Setup.md add-ons step.
> - minikube with `--nodes 2` also works: `minikube start --nodes 2`

---

## What You Will Learn

- The difference between running a pod directly vs a Deployment — and why you never do the former in production
- Rolling updates and rollbacks — the safe way to deploy at a company
- How to handle apps that need ordered startup (StatefulSets)
- How to run background jobs and scheduled tasks
- Scaling: manual and automatic
- Health checks: why apps silently fail without them

---

## Background — Read Before Starting

At a company, nobody creates bare pods. The chain always looks like:

```
Developer pushes code
  → CI builds image, pushes to registry
    → DevOps updates Deployment image tag
      → K8s rolls out new pods gracefully
        → Old pods terminate after new ones are healthy
```

You are the DevOps engineer managing that last part — and you need to understand every step of it.

---

## Exercise 1 — Deployment Fundamentals

**Scenario:** `team-alpha` wants to deploy their Node.js API. Image: `nginx:1.24` (use nginx as a stand-in).

**Your task:**
1. Create a Deployment named `alpha-api` in namespace `team-alpha` with:
   - 3 replicas
   - Image: `nginx:1.24`
   - Label: `app=alpha-api`
   - Resource requests: CPU `100m`, memory `128Mi`
   - Resource limits: CPU `500m`, memory `256Mi`
2. Expose it with a ClusterIP Service on port 80
3. Verify pods are running and distributed across nodes
4. Manually delete one pod — watch what happens and explain why

**You should know how to answer:**
- What is a ReplicaSet and how does it relate to a Deployment?
- Why should you never edit a ReplicaSet directly?

---

## Exercise 2 — Rolling Updates and Rollbacks

**Scenario:** A new image is ready. You need to deploy it with zero downtime.

**Your task:**
1. Update `alpha-api` to image `nginx:1.25` — do this imperatively (one kubectl command)
2. Watch the rollout happen in real-time
3. Check rollout history
4. Simulate a bad deployment: update to image `nginx:does-not-exist`
5. Watch pods fail — then rollback to the previous good version
6. Confirm the app is healthy again

**Dig deeper:**
- Set `maxSurge: 1` and `maxUnavailable: 0` on the Deployment and explain what that means for zero-downtime deploys
- Set `minReadySeconds: 30` and observe how it slows down the rollout — when would you use this in production?

**You should know how to answer:**
- What rollout strategy does K8s use by default and what are the alternatives?
- How do you pause a rollout mid-way if you spot a problem?

---

## Exercise 3 — Health Checks (Probes)

**Scenario:** `team-beta`'s app starts up but takes 20 seconds to be ready. Without probes, K8s sends traffic too early and users get errors.

**Your task:**
Create a Deployment for `beta-app` that has:
1. A **readinessProbe** — HTTP GET to `/` on port 80, starts checking after 10 seconds, checks every 5 seconds
2. A **livenessProbe** — HTTP GET to `/` on port 80, starts after 30 seconds, checks every 10 seconds, fails after 3 consecutive failures
3. A **startupProbe** — allows 60 seconds for the app to start before liveness kicks in

Then:
- Break the readiness probe (point it to a wrong path like `/healthz`) and watch the pod stop receiving traffic
- Fix it and watch traffic resume
- Explain the difference between `0/1 Running` and `1/1 Running` in `kubectl get pods`

**You should know how to answer:**
- What is the difference between liveness, readiness, and startup probes?
- What happens if a liveness probe fails continuously?

---

## Exercise 4 — ConfigMaps and Secrets

**Scenario:** `alpha-api` needs a database URL and an API key. You must not hardcode these in the image.

**Your task:**
1. Create a ConfigMap `alpha-config` with:
   - `DB_HOST=postgres.team-alpha.svc.cluster.local`
   - `APP_ENV=production`
   - A full config file mounted as a volume: create `app.properties` with 3 key-value lines of your choice
2. Create a Secret `alpha-secrets` with:
   - `DB_PASSWORD=supersecret`
   - `API_KEY=abc123xyz`
3. Update the `alpha-api` Deployment to:
   - Inject ConfigMap values as environment variables
   - Inject Secret values as environment variables
   - Mount the `app.properties` file from the ConfigMap at `/etc/config/app.properties`
4. Exec into a running pod and verify all env vars are present and the file is mounted correctly

**You should know how to answer:**
- Why are Secrets not actually secure by default in K8s? What is the real solution? (hint: etcd encryption / Vault)
- What happens to running pods if you update a ConfigMap?

---

## Exercise 5 — DaemonSet

**Scenario:** Your company uses Filebeat to ship logs from every node to Elasticsearch. It must run on every node — including new nodes added in the future.

**Your task:**
1. Create a DaemonSet that runs `nginx:latest` (stand-in for Filebeat) in namespace `monitoring`
2. Verify it is running on all nodes
3. Add a new node (in this exercise: add a label to simulate targeting specific nodes using nodeSelector)
4. Taint `k8s-worker1` with `logging=disabled:NoSchedule` and update the DaemonSet to tolerate it — then remove the toleration and observe what happens

**You should know how to answer:**
- What is the difference between a DaemonSet and a Deployment with replicas = number of nodes?
- When would you use a DaemonSet vs a sidecar container?

---

## Exercise 6 — Jobs and CronJobs

**Scenario:** The data team needs a nightly database backup job that runs at 2am every day.

**Your task:**
1. Create a Job that runs `busybox` and executes: `echo "backup completed at $(date)"` — verify it completes
2. Create a CronJob named `db-backup` in `team-alpha` that:
   - Runs at 2am daily
   - Uses `busybox` image
   - Prints a backup message
   - Keeps last 3 successful jobs and 1 failed job in history
3. Manually trigger the CronJob immediately (without waiting for schedule) and verify it ran

**You should know how to answer:**
- What happens if a CronJob is still running when the next schedule fires?
- What does `concurrencyPolicy: Forbid` do?

---

## Exercise 7 — Horizontal Pod Autoscaler

**Scenario:** `alpha-api` gets traffic spikes during business hours. You need it to scale automatically.

**Your task:**
1. Ensure metrics-server is installed (`kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml`)
2. Create an HPA for `alpha-api` that:
   - Minimum 2 replicas, maximum 8 replicas
   - Target CPU utilisation: 50%
3. Generate artificial load (use `kubectl run` with a busybox loop hitting the service)
4. Watch HPA scale up pods with `kubectl get hpa -w`
5. Stop the load and watch it scale back down

**You should know how to answer:**
- What metrics can HPA scale on beyond CPU? (hint: custom metrics, Prometheus adapter, KEDA)
- What is the cooldown period for scale-down and why does it exist?

---

## Completion Checklist

- [ ] Create and manage Deployments with proper resource limits
- [ ] Perform rolling updates and rollbacks confidently
- [ ] Add meaningful health probes to any Deployment
- [ ] Inject config via ConfigMaps and Secrets
- [ ] Deploy a DaemonSet with node targeting
- [ ] Create Jobs and CronJobs
- [ ] Set up and observe HPA in action

---

## Interview Questions This Task Prepares You For

- "Walk me through how you deploy a new version of an app with zero downtime."
- "What happens if a pod's liveness probe keeps failing?"
- "How do you handle environment-specific configuration in K8s?"
- "How do you ensure an app doesn't bring down the cluster by consuming all resources?"
- "Explain HPA — how does it work and what are its limitations?"

---

## Mini Project — Deploy a Resilient 2-Tier Application

> Estimated time: 2–3 hours. Put this in GitHub under `k8s-practice/task-02/`.

**Scenario:** `team-alpha` needs their new API deployed. It's a backend API + Redis cache. Your job is to deploy it properly — not just "make it run" but make it production-ready on a dev cluster.

**Application:**
- Backend: `hashicorp/http-echo` — args: `-text="Hello from alpha-api v1"`
- Cache: `redis:7-alpine`

**Deliverables — all as YAML files in a `manifests/` folder:**

1. `redis-deployment.yaml` — Redis with proper resource limits, a readiness probe checking port 6379
2. `api-deployment.yaml` — The API with:
   - 2 replicas
   - Resource requests and limits set
   - Readiness probe and liveness probe configured
   - An environment variable `REDIS_HOST` pointing to the Redis service DNS name
   - Image version as `v1` (use a label, not just latest)
3. `services.yaml` — ClusterIP service for Redis (internal only), ClusterIP for API
4. `hpa.yaml` — HPA for the API: min 2, max 6, target 60% CPU
5. `configmap.yaml` — A ConfigMap for non-sensitive API config (e.g. log level, app name)

**Proof of completion:**
- Show rolling update from `v1` to `v2` (change the `-text` arg) with zero downtime
- Show rollback to `v1` in a single command
- Show HPA in `kubectl get hpa` with current replica count
- `kubectl describe pod` shows probes configured on the API pod

---

**Next: Task-03-Networking-and-Ingress.md**
