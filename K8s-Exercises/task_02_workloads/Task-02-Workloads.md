# Task 02 — Workloads: Deploying and Managing Applications

> Real-world relevance: This is what a DevOps engineer does every day.
> Deploying apps, rolling updates, handling failures, scaling — these are bread-and-butter skills.
> Every answer here should come from muscle memory, not notes.

> **Cluster needed:** 2-node cluster (1 control-plane + 1 worker) so you can see pod distribution.
> - **Use:** `kind create cluster --config kind-2node.yaml` — see **00-Setup.md Option A1** for the config file.
> - **Browser-based (no install):** Killercoda → "Kubernetes 2 Node Cluster" scenario.
> - **HPA exercise:** Requires `metrics-server` — installed as part of the add-ons step in 00-Setup.md Option A1.

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
  ```bash
  kubectl create deployment alpha-api --image=nginx:1.24 --dry-run=client -o yaml > alpha-api_deplopyement.yml
  kubectl apply -f alpha-api_deployment.yml
  kubectl get deployment
  ```
2. Expose it with a ClusterIP Service on port 80
  ```bash
  kubectl expose deployment alpha-api --name=alpha-api-svc --port=80 --target-port=80
  kubectl get svc
  ```
3. Verify pods are running and distributed across nodes
  ```bash
  kubectl get pods
  ```
4. Manually delete one pod — watch what happens and explain why
  - As we delete a pod, deployment tries to make the replicas to desired state as present in manifest files

**You should know how to answer:**
- **What is a ReplicaSet and how does it relate to a Deployment?**

  A ReplicaSet ensures a specified number of pod replicas are running at all times. A Deployment is a higher-level abstraction that owns and manages a ReplicaSet — it creates a new RS on every spec/image change and retains the old ones for rollback. You interact with the Deployment; the RS is managed automatically.

- **Why should you never edit a ReplicaSet directly?**

  Any manual change to an RS is immediately overwritten by the Deployment controller reconciling it back to the Deployment spec. RS edits also don't appear in rollout history, so `kubectl rollout undo` won't roll them back. Always edit the Deployment.

---

## Exercise 2 — Rolling Updates and Rollbacks

**Scenario:** A new image is ready. You need to deploy it with zero downtime.

**Your task:**
1. Update `alpha-api` to image `nginx:1.25` — do this imperatively (one kubectl command)
  ```bash
  kubectl set image deployment/alpha-api nginx=nginx:1.25
  ```
2. Watch the rollout happen in real-time

3. Check rollout history
  ```bash
  kubectl rollout history deployment/alpha-api
  ```
4. Simulate a bad deployment: update to image `nginx:does-not-exist`
  ```bash
  kubectl set image deployment/alpha-api nginx=nginx:does-not-exist
  ```
5. Watch pods fail — then rollback to the previous good version
  ```bash
  kubectl get pods -w
  kubectl rollout undo deployment/alpha-api
  kubectl describe deployment alpha-api | grep -i image
  ```
6. Confirm the app is healthy again
  ```bash
  kubectl get pods
  ```

**Dig deeper:**
- Set `maxSurge: 1` and `maxUnavailable: 0` on the Deployment and explain what that means for zero-downtime deploys
  - maxSurge: 1 allows Kubernetes to create one additional pod above the desired replica count during a rolling update. 
  - When combined with maxUnavailable: 0, Kubernetes does not terminate an old pod until the new pod is Ready, ensuring that all desired replicas remain available throughout the deployment.
- Set `minReadySeconds: 30` and observe how it slows down the rollout — when would you use this in production? NOT DONE YET
  - minReadySeconds tells Kubernetes:
    - Even after a pod becomes Ready, don't consider it "Available" until it has remained Ready continuously for the specified number of seconds.
  - 
**You should know how to answer:**
- **What rollout strategy does K8s use by default and what are the alternatives?**

  K8s has two built-in strategies: `RollingUpdate` (default — gradually replaces old pods while keeping the app available) and `Recreate` (kills all old pods first, then starts new ones — causes downtime). Blue-Green and Canary are deployment *patterns*, not K8s strategy types — they're implemented by running multiple Deployments and splitting traffic via Services or Ingress weights.

- **How do you pause a rollout mid-way if you spot a problem?**
  ```bash
  kubectl rollout pause deployment/alpha-api
  # inspect pods, logs, metrics...
  kubectl rollout resume deployment/alpha-api
  # or rollback entirely
  kubectl rollout undo deployment/alpha-api
  ```

---

## Exercise 3 — Health Checks (Probes)

**Scenario:** `team-beta`'s app starts up but takes 20 seconds to be ready. Without probes, K8s sends traffic too early and users get errors.
```bash
kubectl config use-context k8s-dev-beta # Switch context first
```
**Your task:**
Create a Deployment for `beta-app` that has:
```bash
kubectl create deployment beta-app --image=nginx:1.25 --dry-run=client -o yaml > beta-app_deployment.yml
```
1. A **readinessProbe** — HTTP GET to `/` on port 80, starts checking after 10 seconds (initialDelaySeconds), checks every 5 seconds (periodSeconds)
2. A **livenessProbe** — HTTP GET to `/` on port 80, starts after 30 seconds, checks every 10 seconds, fails after 3 consecutive failures (failureThreshold)
3. A **startupProbe** — allows 60 seconds for the app to start before liveness kicks in

Then:
- Break the readiness probe (point it to a wrong path like `/healthz`) and watch the pod stop receiving traffic
- Fix it and watch traffic resume
- Explain the difference between `0/1 Running` and `1/1 Running` in `kubectl get pods`

  The format is `ready-containers / total-containers`. `0/1 Running` means the pod is running but **not ready** — the readiness probe is failing or `initialDelaySeconds` hasn't elapsed. Traffic is only sent to pods showing `1/1`.

**You should know how to answer:**
- **What is the difference between liveness, readiness, and startup probes?**

  | Probe | Purpose | Failure action |
  |---|---|---|
  | **Readiness** | Is the app ready to serve traffic? | Pod removed from Service endpoints |
  | **Liveness** | Is the app alive and not stuck/deadlocked? | Container is **restarted** by kubelet |
  | **Startup** | Has the app finished its slow startup? | Blocks liveness & readiness until it passes; container restarted if it never does |

- **What happens if a liveness probe fails continuously?**

  kubelet **restarts the container** each time it exceeds `failureThreshold`. The pod stays in `Running` state but the `RESTARTS` count climbs. If it keeps failing it enters `CrashLoopBackOff`.

---

## Exercise 4 — ConfigMaps and Secrets

**Scenario:** `alpha-api` needs a database URL and an API key. You must not hardcode these in the image.

> Switch context first: `kubectl config use-context k8s-dev`

**Your task:**
1. Create a ConfigMap `alpha-config` with:
   - `DB_HOST=postgres.team-alpha.svc.cluster.local`
   - `APP_ENV=production`
   ```bash
   kubectl create configmap alpha-config --from-literal=DB_HOST=postgres.team-alpha.svc.cluster.local --from-literal=APP_ENV=production --dry-run=client -o yaml > alpha_config.yml
   ```
   - A full config file mounted as a volume: create `app.properties` with 3 key-value lines of your choice
   ```bash
   kubectl apply -f app_properties-configmap.yml
   ```
2. Create a Secret `alpha-secrets` with:
   - `DB_PASSWORD=supersecret`
   - `API_KEY=abc123xyz`
   ```bash
   kubectl create secret generic alpha-secrets --from-literal=DB_PASSWORD=supersecret --from-literal=API_KEY=abc123xyz --dry-run=client -o yaml > alpha_secrets.yml
   ```
3. Update the `alpha-api` Deployment to:
   - Inject ConfigMap values as environment variables
   - Inject Secret values as environment variables
   - Mount the `app.properties` file from the ConfigMap at `/etc/config/app.properties`
4. Exec into a running pod and verify all env vars are present and the file is mounted correctly
   ```bash
   kubectl exec -it <pod_name> -- sh
   echo $ENV_VAR
   cat /etc/config/app.properties
   ```

**You should know how to answer:**
- **Why are Secrets not actually secure by default in K8s? What is the real solution?**

  Secrets are only base64-encoded in etcd — not encrypted. Anyone with etcd read access or RBAC `get secret` permission can decode them trivially. Real solutions:
  - **Encrypt etcd at rest** — enable `EncryptionConfiguration` in the API server
  - **RBAC** — restrict `get`/`list` Secret access to only the service accounts that need them
  - **External secret stores** — HashiCorp Vault, AWS Secrets Manager (via IRSA + External Secrets Operator). Secrets never live in etcd at all.

- **What happens to running pods if you update a ConfigMap?**

  Depends on how it's consumed:
  - **Env vars** (`envFrom` / `valueFrom`) — pod must be **restarted** to pick up new values; env is set at container start and does not refresh live.
  - **Volume mount** — the file updates automatically within ~1 minute (kubelet syncs it). No pod restart needed, but the app must re-read the file to notice the change.

---

## Exercise 5 — DaemonSet

**Scenario:** Your company uses Filebeat to ship logs from every node to Elasticsearch. It must run on every node — including new nodes added in the future.

**Your task:**
1. Create a DaemonSet that runs `nginx:latest` (stand-in for Filebeat) in namespace `monitoring`
   ```bash
   kubectl apply -f filebeat_daemonset.yml
   ```
2. Verify it is running on all nodes
   ```bash
   kubectl get pods -n monitoring -o wide
   ```
3. Add a new node (in this exercise: add a label to simulate targeting specific nodes using nodeSelector) label:disktype=ssd
4. Taint `k8s-worker1` with `logging=disabled:NoSchedule` and update the DaemonSet to tolerate it — then remove the toleration and observe what happens
   ```bash
   kubectl taint nodes devops-lab-worker logging=disabled:NoSchedule

   # Verify
   kubectl describe node devops-lab-worker | grep -i taint

   # Remove taint when done
   kubectl taint nodes devops-lab-worker logging=disabled:NoSchedule-
   ```
**Answer:** After removing the toleration, nothing immediately happens — the existing pod continues to run on the node because `NoSchedule` only affects **upcoming** pod scheduling, not existing pods.

**You should know how to answer:**
- **What is the difference between a DaemonSet and a Deployment with replicas = number of nodes?**

  A DaemonSet runs **exactly one pod per matching node** automatically — when a new node joins the cluster, the pod is scheduled there; when a node is removed, the pod is cleaned up. There's no replica count to maintain. A Deployment with `replicas = N` is a fixed count — it doesn't automatically follow node additions and doesn't guarantee one-per-node distribution.

- **When would you use a DaemonSet vs a sidecar container?**

  - **DaemonSet** — **node-scoped**: log collectors (Filebeat, Fluentd), node monitoring (Prometheus node-exporter), network plugins. Runs once per node regardless of how many pods are on it.
  - **Sidecar** — **pod-scoped**: log shipper for one specific app, Envoy proxy, secrets-sync container. Lives and dies with the pod.

---

## Exercise 6 — Jobs and CronJobs

**Scenario:** The data team needs a nightly database backup job that runs at 2am every day.

**Your task:**
1. Create a Job that runs `busybox` and executes: `echo "backup completed at $(date)"` — verify it completes
   ```bash
   kubectl create job my-job --image=busybox -- sh -c 'echo "backup completed at $(date)"'

   # Verify
   kubectl logs <job-pod>
   ```
2. Create a CronJob named `db-backup` in `team-alpha` that:
   - Runs at 2am daily
   - Uses `busybox` image
   - Prints a backup message
   - Keeps last 3 successful jobs and 1 failed job in history
   ```bash
   kubectl create cronjob db-backup --image=busybox --schedule="0 2 * * *" --dry-run=client -o yaml > db-backup_cronjob.yml
   ```
3. Manually trigger the CronJob immediately (without waiting for schedule) and verify it ran
   ```bash
   # Manually trigger it by creating a Job from the CronJob
   kubectl create job backup-now --from=cronjob/db-backup
   ```

**You should know how to answer:**
- **What happens if a CronJob is still running when the next schedule fires?**

  Depends on `concurrencyPolicy` (default is `Allow`):

  | Policy | Behaviour |
  |---|---|
  | `Allow` (default) | Both jobs run concurrently |
  | `Forbid` | New run is **skipped** if previous is still running |
  | `Replace` | Previous job is killed, new one starts |

- **What does `concurrencyPolicy: Forbid` do?**

  If the previous job hasn't finished when the next schedule fires, the new run is **skipped entirely** — not queued. Use this for jobs that must not overlap (e.g., database backups that would conflict with each other running simultaneously).
---

## Exercise 7 — Horizontal Pod Autoscaler

**Scenario:** `alpha-api` gets traffic spikes during business hours. You need it to scale automatically.

**Your task:**
1. Ensure metrics-server is installed
   ```bash
   kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

   # Verify
   kubectl top pods
   ```
2. Create an HPA for `alpha-api` that:
   - Minimum 2 replicas, maximum 8 replicas
   - Target CPU utilisation: 50%
   ```bash
   kubectl autoscale deployment alpha-api --min=2 --max=8 --cpu-percent=50 --dry-run=client -o yaml > alpha-api_hpa.yaml
   kubectl get hpa
   ```
3. Generate artificial load (use busybox pod loop hitting the service)
   ```bash
   kubectl apply -f stress-test_pod.yml
   ```
4. Watch HPA scale up pods
   ```bash
   kubectl get hpa -w
   ```
5. Stop the load and watch it scale back down

**You should know how to answer:**
- **What metrics can HPA scale on beyond CPU?**

  - **Memory** — via `autoscaling/v2` with `resource: memory`
  - **Custom metrics** — app-specific metrics (requests/sec, queue depth) via the Prometheus Adapter
  - **External metrics** — cloud queue depth (SQS, Kafka, RabbitMQ) via an external metrics provider
  - **KEDA** — Kubernetes Event Driven Autoscaling, extends HPA with 50+ scalers (Kafka, Redis, Azure Queue, cron schedules, etc.) and supports scale-to-zero

- **What is the cooldown period for scale-down and why does it exist?**

  In K8s HPA it's the **stabilization window** — default 300 seconds (5 min) for scale-down, 0 for scale-up. It prevents **thrashing**: if you scale down immediately after load drops, the next spike causes scale-up again, creating constant oscillation. The window waits until metrics are consistently low before scaling down. Configurable via `behavior.scaleDown.stabilizationWindowSeconds`.

---

## Exercise 8 — Init Containers

**Scenario:** `team-alpha`'s API must not start until the database is accepting connections. In production, apps that start before their dependencies are ready cause cascading failures that are hard to debug.

**Your task:**
```bash
# Generate the init container pod manifest
kubectl run nginx-pod --image=nginx:1.25 --dry-run=client -o yaml > init_cont-pod.yml
```
1. Create a pod with an `initContainer` that runs `busybox` and loops until a service named `postgres` in `team-alpha` is resolvable via DNS:
   ```bash
   until nslookup postgres.team-alpha.svc.cluster.local; do echo "waiting for DB..."; sleep 2; done
   ```
   ```bash
   # Generate postgres deployment manifest
   kubectl create deployment postgres --image=postgres:15 --replicas=3 --dry-run=client -o yaml > postgres_deployment.yml
   ```
2. Start the pod WITHOUT the postgres Service existing — watch the init container loop
   ```bash
   kubectl apply -f init_cont-pod.yml
   kubectl get pods
   kubectl logs nginx-pod -c wait-for-postgres --follow
   ```
3. Create the postgres Service — watch the init container succeed and the main container start
   ```bash
   kubectl apply -f postgres_deployment.yml
   kubectl expose deployment postgres --name=postgres-svc --port=5431 --target-port=5432
   kubectl get svc
   kubectl port-forward svc/postgres-svc 5431:5432
   ```
4. Understand the sequencing: init containers run to completion in order before any app container starts
   ```bash
   kubectl logs nginx-pod -c wait-for-postgres --follow
   kubectl logs nginx-pod
   ```

5.
**Second scenario — DB migration pattern:**
Add a second init container that runs after the DNS check and simulates a DB migration:
```bash
echo "Running DB migration v3..."
sleep 5
echo "Migration complete"
```
Observe the order: `initContainer-1` → `initContainer-2` → `app` container.

**Dig deeper:**
- **What happens if an init container fails? What is the restart behavior?**

  The main container never starts. The init container is retried with exponential backoff (as long as the pod's `restartPolicy` is `Always` or `OnFailure`). If `restartPolicy: Never`, the pod fails permanently. The pod stays in `Init:CrashLoopBackOff` if the init container keeps failing.

- **How is an init container different from a `postStart` lifecycle hook?**

  A `postStart` hook runs **concurrently** with the container's main process immediately after it starts — it does NOT block the container and there's no guarantee it finishes before the next lifecycle step. An init container runs **sequentially before any app container starts** and must complete successfully before the next init container (or main container) begins.

- **When would you use a sidecar container vs an init container?**

  - **Init container** — one-time setup that must complete before the app starts: DNS/port check, DB migration, config file generation.
  - **Sidecar** — something that runs continuously alongside the app for its entire lifetime: log shipping, metrics collection, Envoy proxy, secrets rotation.

**You should know how to answer:**
- "How do you ensure your app doesn't start before its database is ready?"
  - we use the initContainer to check the DB readiness by pining it until it response back.
- "What is the difference between an init container and a sidecar?"
  - answered above.

---

## Exercise 9 — Production Resilience: PDB, Anti-Affinity, Graceful Shutdown

This is what separates a K8s deployment that works from one that is production-ready. These three concepts are almost always missing in junior setups and are the first thing a senior engineer adds.

### Part A — Pod Disruption Budget (PDB)

**Scenario:** You have 3 replicas of `alpha-api`. A DevOps engineer runs `kubectl drain node1` to perform maintenance. Without a PDB, K8s might evict all 3 pods at once if they all happen to be on that node. Your app goes down during maintenance.

**Your task:**
1. Create a PDB for `alpha-api` that guarantees at minimum 2 pods are always available:
   ```yaml
   apiVersion: policy/v1
   kind: PodDisruptionBudget
   metadata:
     name: alpha-api-pdb
     namespace: team-alpha
   spec:
     minAvailable: 2
     selector:
       matchLabels:
         app: alpha-api
   ```
2. Simulate a node drain: `kubectl drain <node> --ignore-daemonsets --delete-emptydir-data`
3. Watch what happens — K8s will only evict pods one at a time, respecting the PDB
4. Observe `kubectl get pdb -n team-alpha` — it shows current allowed disruptions
5. Try setting `minAvailable: 3` (same as replica count) and drain again — observe that drain blocks

**You should know how to answer:**
- "What is a PodDisruptionBudget and when does it apply?" (Node drains, evictions — NOT pod crashes)
- "What is the difference between `minAvailable` and `maxUnavailable` in a PDB?"

---

### Part B — Pod Anti-Affinity (High Availability)

**Scenario:** `alpha-api` has 3 replicas. All 3 land on the same node. That node goes down — all replicas die at once. Your app has zero availability. This is a real and common production failure.

**Your task:**
1. Add `podAntiAffinity` to the `alpha-api` Deployment so that no two replicas can run on the same node:
   ```yaml
   affinity:
     podAntiAffinity:
       requiredDuringSchedulingIgnoredDuringExecution:
       - labelSelector:
           matchLabels:
             app: alpha-api
         topologyKey: kubernetes.io/hostname
   ```
2. With a 2-node cluster: scale to 3 replicas — observe the 3rd pod goes `Pending` because no eligible node exists. This is the correct behavior — it is better to have a pending pod than to violate HA constraints silently.
3. Understand the difference: `requiredDuringScheduling` (hard rule — pod stays Pending if violated) vs `preferredDuringScheduling` (soft rule — K8s tries but won't block scheduling)
4. Change to `preferred` and observe all 3 replicas schedule, but K8s spreads them as best it can

**Topology Spread Constraints (modern alternative to anti-affinity):**
Replace the anti-affinity with a `topologySpreadConstraint`:
```yaml
topologySpreadConstraints:
- maxSkew: 1
  topologyKey: kubernetes.io/hostname
  whenUnsatisfiable: DoNotSchedule
  labelSelector:
    matchLabels:
      app: alpha-api
```
This is more flexible — it says "no node should have more than 1 extra replica compared to any other node." This is what modern production clusters use.

**You should know how to answer:**
- "How do you ensure your replicas are spread across nodes/availability zones?"
- "What is `topologyKey` and what values can it take?" (hostname, zone, region)
- "When would you use `DoNotSchedule` vs `ScheduleAnyway` in a topology constraint?"

---

### Part C — Graceful Shutdown and Zero-Downtime Rolling Updates

**Scenario:** You run a rolling update on `alpha-api`. The old pods receive a `SIGTERM` and are removed from the load balancer. But between the SIGTERM and actual pod termination, some requests are still in-flight and get dropped. This is a real production issue that causes 5xx errors during every deployment.

**Your task:**
1. Add a `preStop` lifecycle hook to delay termination by 5 seconds, giving the load balancer time to stop routing traffic to the pod before it shuts down:
   ```yaml
   lifecycle:
     preStop:
       exec:
         command: ["/bin/sh", "-c", "sleep 5"]
   ```
2. Set `terminationGracePeriodSeconds: 60` at the pod spec level — this is the total time K8s waits for a pod to exit gracefully before force-killing it
3. Run a rolling update while generating continuous traffic to the service — count dropped requests before and after adding the `preStop` hook
4. Understand the full termination sequence:
   - Pod removed from Service endpoints (traffic stops routing)
   - `preStop` hook executes (app finishes in-flight requests)
   - `SIGTERM` sent to container
   - K8s waits up to `terminationGracePeriodSeconds` for clean exit
   - `SIGKILL` sent if process is still running

**You should know how to answer:**
- "How do you prevent dropped requests during a rolling update?"
- "What is `terminationGracePeriodSeconds` and what happens when it expires?"
- "What is the difference between `preStop` and a `SIGTERM` handler in the app?"

---

## Completion Checklist

- [x] Create and manage Deployments with proper resource limits
- [x] Perform rolling updates and rollbacks confidently
- [x] Add meaningful health probes to any Deployment
- [x] Inject config via ConfigMaps and Secrets
- [x] Deploy a DaemonSet with node targeting
- [x] Create Jobs and CronJobs
- [x] Set up and observe HPA in action
- [x] Use init containers to gate app startup on dependencies
- [ ] Apply PodDisruptionBudget to protect availability during maintenance
- [ ] Use podAntiAffinity or topologySpreadConstraints to spread replicas across nodes
- [ ] Configure preStop hooks and terminationGracePeriodSeconds for zero-downtime shutdown

---

## Interview Questions This Task Prepares You For

---

**"Walk me through how you deploy a new version of an app with zero downtime."**

Use a rolling update (default strategy). Set `maxUnavailable: 0` and `maxSurge: 1` so old pods are never terminated until a new pod is Ready. Add a `readinessProbe` so K8s knows when the new pod can actually serve traffic. Add a `preStop: sleep 5` hook to let the load balancer drain in-flight requests before SIGTERM is sent. This combination eliminates dropped requests during rollout.

---

**"What happens if a pod's liveness probe keeps failing?"**

kubelet restarts the container every time it exceeds `failureThreshold`. The pod stays in `Running` state but the `RESTARTS` count climbs. After repeated failures it enters `CrashLoopBackOff`. Common causes: app deadlocked, OOMKilled, or the probe path/port is misconfigured.

---

**"How do you handle environment-specific configuration in K8s?"**

Use ConfigMaps for non-sensitive config (DB host, log level, feature flags) and Secrets for sensitive values (passwords, API keys). Maintain separate ConfigMap/Secret values per environment — either via separate namespaces with different manifests, or via GitOps with environment-specific overlays using Kustomize or Helm values files. The app image stays identical across environments; only the injected config changes.

---

**"How do you ensure an app doesn't bring down the cluster by consuming all resources?"**

At namespace level: `ResourceQuota` caps total CPU/memory/pods per namespace. `LimitRange` sets default requests/limits per container and enforces min/max bounds so a misconfigured pod can't request unlimited CPU. There's no native cluster-wide quota in vanilla K8s — protection is enforced by applying quotas to every namespace. In cloud environments, Cluster Autoscaler handles node-level scaling but doesn't prevent a single namespace from consuming all node resources.

---

**"Explain HPA — how does it work and what are its limitations?"**

HPA watches the metrics-server (or custom metrics API) and adjusts the `replicas` field on a Deployment based on target utilisation thresholds. It runs a control loop every 15 seconds. Limitations: requires metrics-server installed, can't scale to 0 replicas (use KEDA for that), has a 5-minute scale-down stabilization window to prevent thrashing, doesn't account for I/O or queue-depth bottlenecks without a custom metrics adapter.

---

**"How do you prevent your app from going down during node maintenance?"**

Use Deployments so replicas are rescheduled automatically when a node is drained. Add a `PodDisruptionBudget` (`minAvailable: 2` on 3 replicas) so `kubectl drain` only evicts one pod at a time. Use `podAntiAffinity` or `topologySpreadConstraints` to ensure replicas are on different nodes so a single drain doesn't take all of them offline simultaneously.

---

**"All 3 replicas of our app are on the same node and the node went down. How do you prevent this?"**

This is the anti-affinity problem. If all replicas are on one node and it crashes, all 3 die at once — full downtime while they reschedule. Prevention: add `podAntiAffinity` with `requiredDuringSchedulingIgnoredDuringExecution` and `topologyKey: kubernetes.io/hostname` to the Deployment. This forces each replica onto a different node. For cloud environments use `topologyKey: topology.kubernetes.io/zone` to spread across availability zones.

---

**"We see 5xx errors during every deployment. What could cause that and how do you fix it?"**

Root cause: during rolling update, there's a race condition — pods receive `SIGTERM` and start shutting down but the load balancer hasn't finished draining in-flight requests yet. Fix: add `preStop: exec: ["/bin/sh", "-c", "sleep 5"]` to give the LB time to stop routing before the container exits. Also set `terminationGracePeriodSeconds: 60` and ensure the app handles `SIGTERM` gracefully by finishing in-flight requests before exiting.

---

**"What is a PodDisruptionBudget and when does it apply?"**

A PDB defines the minimum number of pods that must stay available during **voluntary disruptions** — `kubectl drain`, cluster upgrades, node auto-scaling. It does NOT protect against involuntary disruptions like node crashes. Example: `minAvailable: 2` on a 3-replica Deployment means `kubectl drain` can only evict 1 pod at a time.

---

**"How do you ensure a pod waits for its database to be ready before starting?"**

Use an init container that loops until the DB DNS resolves or the port is reachable. The main app container doesn't start until all init containers complete successfully.

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
# kubectl create configmap redis-config --from-literal=app_name=redis_app --from-literal=log_level=DEBUG

**Proof of completion:** #LEFT#
- Show rolling update from `v1` to `v2` (change the `-text` arg) with zero downtime
- Show rollback to `v1` in a single command
- Show HPA in `kubectl get hpa` with current replica count
- `kubectl describe pod` shows probes configured on the API pod

---

**Next: Task-03-Networking-and-Ingress.md**
