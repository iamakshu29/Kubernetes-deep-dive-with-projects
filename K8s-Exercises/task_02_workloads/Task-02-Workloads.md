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
# kubectl create deployment alpha-api --image=nginx:1.24 --dry-run=client -o yaml > alpha-api_deplopyement.yml
# kubectl apply -f alpha-api_deployment.yml
# kubectl get deployment

2. Expose it with a ClusterIP Service on port 80
# kubectl expose deployment alpha-api --name=alpha-api-svc --port=80 --target-port=80
# kubectl get svc

3. Verify pods are running and distributed across nodes
# kubectl get pods
4. Manually delete one pod — watch what happens and explain why
  - As we delete a pod, deployment tries to make the replicas to desired state as present in manifest files

**You should know how to answer:**
- What is a ReplicaSet and how does it relate to a Deployment?
  - It main task is to make the replicas defined in manifest files and Deployment kind of superset replicaset feature of maintaining desired replicas.
- Why should you never edit a ReplicaSet directly?
  - WHY ?? I dont know

---

## Exercise 2 — Rolling Updates and Rollbacks

**Scenario:** A new image is ready. You need to deploy it with zero downtime.

**Your task:**
1. Update `alpha-api` to image `nginx:1.25` — do this imperatively (one kubectl command)
# kubectl set image deployment/alpha-api nginx=nginx:1.25

2. Watch the rollout happen in real-time

3. Check rollout history
# kubectl rollout history deployment/alpha-api

4. Simulate a bad deployment: update to image `nginx:does-not-exist`
# kubectl set image deployment/alpha-api nginx=nginx:does-not-exist

5. Watch pods fail — then rollback to the previous good version
# kubectl get pods -w
# kubectl rollout undo deployment/alpha-api
# kubectl describe deployment alpha-api | grep -i image
6. Confirm the app is healthy again
# kubectl get pods

**Dig deeper:**
- Set `maxSurge: 1` and `maxUnavailable: 0` on the Deployment and explain what that means for zero-downtime deploys
  - maxSurge: 1 allows Kubernetes to create one additional pod above the desired replica count during a rolling update. 
  - When combined with maxUnavailable: 0, Kubernetes does not terminate an old pod until the new pod is Ready, ensuring that all desired replicas remain available throughout the deployment.
- Set `minReadySeconds: 30` and observe how it slows down the rollout — when would you use this in production? NOT DONE YET
  - minReadySeconds tells Kubernetes:
    - Even after a pod becomes Ready, don't consider it "Available" until it has remained Ready continuously for the specified number of seconds.
  - 
**You should know how to answer:**
- What rollout strategy does K8s use by default and what are the alternatives?
  - RollingUpdate is default, ReCreate, Blue-Green and Canary are alternatives
- How do you pause a rollout mid-way if you spot a problem?
  - 

---

## Exercise 3 — Health Checks (Probes)

**Scenario:** `team-beta`'s app starts up but takes 20 seconds to be ready. Without probes, K8s sends traffic too early and users get errors.
# Switch context first
# kubectl config use-context k8s-dev-beta
**Your task:**
Create a Deployment for `beta-app` that has:
# kubectl create deployment beta-app --image=nginx:1.25 --dry-run=client -o yaml > beta-app_deployment.yml
1. A **readinessProbe** — HTTP GET to `/` on port 80, starts checking after 10 seconds (initialDelaySeconds), checks every 5 seconds (periodSeconds)
2. A **livenessProbe** — HTTP GET to `/` on port 80, starts after 30 seconds, checks every 10 seconds, fails after 3 consecutive failures (failureThreshold)
3. A **startupProbe** — allows 60 seconds for the app to start before liveness kicks in

Then:
- Break the readiness probe (point it to a wrong path like `/healthz`) and watch the pod stop receiving traffic
- Fix it and watch traffic resume
- Explain the difference between `0/1 Running` and `1/1 Running` in `kubectl get pods`
  - Inital delay seconds once its completed it go from 0/1 running to 1/1 running

**You should know how to answer:**
- What is the difference between liveness, readiness, and startup probes?
- What happens if a liveness probe fails continuously?

---

## Exercise 4 — ConfigMaps and Secrets

**Scenario:** `alpha-api` needs a database URL and an API key. You must not hardcode these in the image.
# kubectl config use-context k8s-dev
**Your task:**
1. Create a ConfigMap `alpha-config` with:
   - `DB_HOST=postgres.team-alpha.svc.cluster.local`
   - `APP_ENV=production`
# kubectl create configmap alpha-config --from-literal=DB_HOST=postgres.team-alpha.svc.cluster.local --from-literal=APP_ENV=production --dry-run=client -o yaml > alpha_config.yml
   
   - A full config file mounted as a volume: create `app.properties` with 3 key-value lines of your choice
# kubectl apply -f app_properties-configmap.yml
2. Create a Secret `alpha-secrets` with:
   - `DB_PASSWORD=supersecret`
   - `API_KEY=abc123xyz`
# kubectl create secret alpha-secrets --from-literal=DB_PASSWORD=supersecret --from-literal=API_KEY=abc123xyz --dry-run=client -o yaml > alpha_secrets.yml

3. Update the `alpha-api` Deployment to:
   - Inject ConfigMap values as environment variables
   - Inject Secret values as environment variables
   - Mount the `app.properties` file from the ConfigMap at `/etc/config/app.properties`
4. Exec into a running pod and verify all env vars are present and the file is mounted correctly
# kubectl exec -it <pod_name> -- sh
# echo $ENV_VAR
# cat /etc/config/app.properties

**You should know how to answer:**
- Why are Secrets not actually secure by default in K8s? What is the real solution? (hint: etcd encryption / Vault)
- What happens to running pods if you update a ConfigMap?
  - it needs to be restart/recreate to get the updated configMap variables value

---

## Exercise 5 — DaemonSet

**Scenario:** Your company uses Filebeat to ship logs from every node to Elasticsearch. It must run on every node — including new nodes added in the future.

**Your task:**
1. Create a DaemonSet that runs `nginx:latest` (stand-in for Filebeat) in namespace `monitoring`
# kubectl apply -f filebeat_daemonset.yml
2. Verify it is running on all nodes
# kubectl get pods -n monitoring -o wide

3. Add a new node (in this exercise: add a label to simulate targeting specific nodes using nodeSelector) label:disktype=ssd
4. Taint `k8s-worker1` with `logging=disabled:NoSchedule` and update the DaemonSet to tolerate it — then remove the toleration and observe what happens
# kubectl taint nodes devops-lab-worker logging=disabled:NoSchedule

# Verify using
# kubectl describe node devops-lab-worker | grep -i taint

# Untainted the Node for later purposes
# kubectl taint nodes devops-lab-worker logging=disabled:NoSchedule-
**Answer**
After removing toleration nothing happened, pod continues to run on node as NoSchedules effects on upcoming pod, not the existing one.

**You should know how to answer:**
- What is the difference between a DaemonSet and a Deployment with replicas = number of nodes?
- When would you use a DaemonSet vs a sidecar container?
**Answer**
  - when we need node level metrics or logs we use daemon set
  - when we need metrics or logs we use sidecar container. 
  - Daemon set is node-scoped and side car container is pod-scoped

---

## Exercise 6 — Jobs and CronJobs

**Scenario:** The data team needs a nightly database backup job that runs at 2am every day.

**Your task:**
1. Create a Job that runs `busybox` and executes: `echo "backup completed at $(date)"` — verify it completes
# kubectl create job my-job --image=busybox -- sh -c 'echo "backup completed at $(date)"'
## To verify
# kubectl logs <job-pod>
2. Create a CronJob named `db-backup` in `team-alpha` that:
   - Runs at 2am daily
   - Uses `busybox` image
   - Prints a backup message
   - Keeps last 3 successful jobs and 1 failed job in history
# kubectl create cronjob db-backup --image=busybox --schedule="0 2 * * *" --dry-run=client -o yaml > db-backup_cronjob.yml

3. Manually trigger the CronJob immediately (without waiting for schedule) and verify it ran
# You can manually trigger a Kubernetes CronJob by creating a Job from it.
# kubectl create job backup-now --from=cronjob/db-backup

**You should know how to answer:**
- What happens if a CronJob is still running when the next schedule fires?
  - 
- What does `concurrencyPolicy: Forbid` do?
  - when using concurrencyPolicy: Forbid, long-running Jobs may cause scheduled times to be skipped, but a new Job can be created once the previous Job completes.
---

## Exercise 7 — Horizontal Pod Autoscaler

**Scenario:** `alpha-api` gets traffic spikes during business hours. You need it to scale automatically.

**Your task:**
1. Ensure metrics-server is installed (`kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml`)
# To verify
# kubectl top pods
2. Create an HPA for `alpha-api` that:
   - Minimum 2 replicas, maximum 8 replicas
   - Target CPU utilisation: 50%
# kubectl autoscale deployment alpha-api --min=2 --max=8 --cpu-percent=50 --dry-run=client -o yaml > alpha-api_hpa.yaml
# kubectl get hpa
3. Generate artificial load (use `kubectl run` with a busybox loop hitting the service)
# kubectl apply -f stress-test_pod.yml
4. Watch HPA scale up pods with `kubectl get hpa -w`
5. Stop the load and watch it scale back down

**You should know how to answer:**
- What metrics can HPA scale on beyond CPU? (hint: custom metrics, Prometheus adapter, KEDA)
- What is the cooldown period for scale-down and why does it exist?

---

## Exercise 8 — Init Containers

**Scenario:** `team-alpha`'s API must not start until the database is accepting connections. In production, apps that start before their dependencies are ready cause cascading failures that are hard to debug.

**Your task:**
1. Create a pod with an `initContainer` that runs `busybox` and loops until a service named `postgres` in `team-alpha` is resolvable via DNS:
   ```bash
   until nslookup postgres.team-alpha.svc.cluster.local; do echo "waiting for DB..."; sleep 2; done
   ```
2. Start the pod WITHOUT the postgres Service existing — watch the init container loop
3. Create the postgres Service — watch the init container succeed and the main container start
4. Understand the sequencing: init containers run to completion in order before any app container starts

**Second scenario — DB migration pattern:**
Add a second init container that runs after the DNS check and simulates a DB migration:
```bash
echo "Running DB migration v3..."
sleep 5
echo "Migration complete"
```
Observe the order: `initContainer-1` → `initContainer-2` → `app` container.

**Dig deeper:**
- What happens if an init container fails? What is the restart behavior?
- How is an init container different from a `postStart` lifecycle hook?
- When would you use a sidecar container vs an init container?

**You should know how to answer:**
- "How do you ensure your app doesn't start before its database is ready?"
- "What is the difference between an init container and a sidecar?"

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
- [ ] Use init containers to gate app startup on dependencies
- [ ] Apply PodDisruptionBudget to protect availability during maintenance
- [ ] Use podAntiAffinity or topologySpreadConstraints to spread replicas across nodes
- [ ] Configure preStop hooks and terminationGracePeriodSeconds for zero-downtime shutdown

---

## Interview Questions This Task Prepares You For

- "Walk me through how you deploy a new version of an app with zero downtime."
- "What happens if a pod's liveness probe keeps failing?"
- "How do you handle environment-specific configuration in K8s?"
- "How do you ensure an app doesn't bring down the cluster by consuming all resources?"
- "Explain HPA — how does it work and what are its limitations?"
- "How do you prevent your app from going down during node maintenance?"
- "All 3 replicas of our app are on the same node and the node went down. How do you prevent this?"
- "We see 5xx errors during every deployment. What could cause that and how do you fix it?"
- "What is a PodDisruptionBudget and when does it apply?"
- "How do you ensure a pod waits for its database to be ready before starting?"
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
