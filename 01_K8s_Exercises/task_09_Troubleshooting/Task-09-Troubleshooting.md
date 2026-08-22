# Task 09 — Troubleshooting: Debugging a Broken Cluster

> Real-world relevance: This is the most valued skill in an interview AND on the job.
> Anyone can deploy apps when things work. The engineer who can diagnose broken systems
> under pressure is the one who gets promoted and handles incidents.

> **Cluster needed:** 2-node cluster. Node failure scenarios (Scenario 5) require a real VM you can stop.
> - **For Scenarios 1–4 and 6 (pod debugging, service issues):** kind 2-node works fine — see **00-Setup.md Option A1**.
> - **For Scenario 5 (NotReady node simulation):** Use Oracle Free Tier or AWS EC2 — stop the worker VM from the OCI/AWS console. kind nodes are Docker containers and behave differently when stopped. Setup: **00-Setup.md Options B/C**.
> - **For Scenario 6 (etcd backup/restore):** Oracle Free Tier or AWS — you need direct SSH access to the control-plane node.
> - **Browser-based (Scenarios 1–4 only):** Killercoda has specific "broken cluster" scenarios.

---

## The Debugging Mindset

Before touching any command, always ask:
1. What is the symptom? (pod not running, app unreachable, node offline)
2. At which layer is the failure? (infrastructure, cluster, workload, app)
3. What changed recently?

Work top-down or bottom-up — but be systematic. Never guess randomly.

---

## Your Debugging Command Arsenal

Memorise these. They are your toolkit.

```bash
# Cluster health
kubectl get nodes
kubectl get pods -A
kubectl get events --sort-by='.lastTimestamp' -A

# Pod investigation
kubectl describe pod <pod> -n <ns>
kubectl logs <pod> -n <ns>
kubectl logs <pod> -n <ns> --previous
kubectl exec -it <pod> -n <ns> -- /bin/sh

# Node investigation
kubectl describe node <node>
kubectl top node
kubectl top pod -A

# Control plane (on master VM)
kubectl get pods -n kube-system
journalctl -u kubelet -f
sudo crictl ps

# Networking
kubectl get endpointslice <service> -n <ns>
kubectl exec -it <pod> -- curl <service>:<port>
kubectl exec -it <pod> -- nslookup <service>
```

---

## Scenario 1 — Pod is Stuck in `Pending`

**Simulate it:** Create a pod requesting 100 CPUs (more than your cluster has).
```bash
    # To check the Node's requests and limits 
    kubectl describe node <node-name>

    # update the requested CPU more than the node CPU limits
    kubectl create deploy test-pod --image=nginx:1.25 --dry-run=client -o yaml > test-deploy.yml
```
**Your task:**
1. Identify WHY the pod is pending (do not just read the answer — run the commands and find it)
- The pod is stuck in `Pending` because the scheduler cannot find a node with enough allocatable CPU to satisfy the request. Running `kubectl describe pod <pod> -n prac` shows it in the **Events** section: `0/2 nodes are available: 2 Insufficient cpu. preemption: 0/2 nodes are available: 2 No preemption victims found...`

2. Identify which specific condition is blocking scheduling
- The scheduler compares `pod.spec.containers[].resources.requests.cpu` against `node.status.allocatable.cpu` — not node limits (nodes don't have limits). When `requests.cpu` exceeds the node's `allocatable.cpu`, the **Filter** phase of scheduling fails with `Insufficient cpu` and the pod stays `Pending`.

3. Resolve it by adjusting the resource request to something reasonable
4. Understand the `describe pod` output — specifically the `Events` section at the bottom

**Second simulation:** Create a pod with a `nodeSelector` for a label that no node has.
1. Find why it is pending
  - `kubectl describe pod` Events section shows: `0/2 nodes are available: 2 node(s) didn't match Pod's node affinity/selector`. The scheduler's Filter phase eliminates all nodes because none carry the label specified in `nodeSelector`.

2. Fix it by adding the label to a node
  - `kubectl label node <node-name> <key>=<value>`
  
3. Explain: what is the difference between nodeSelector, nodeAffinity, and taints/tolerations for node targeting?
  - **nodeSelector** — The simplest mechanism. You put a map of key-value pairs in the pod spec; the scheduler only places the pod on nodes that have all those exact labels. No operators, no soft rules — it is a hard requirement and exact match only.
  - **nodeAffinity** — Also defined in the **pod spec** (not on the node). Nodes carry labels; the pod declares rules that reference those labels using operators (`In`, `NotIn`, `Exists`, etc.). Supports two modes: `requiredDuringSchedulingIgnoredDuringExecution` (hard — pod stays Pending if no match) and `preferredDuringSchedulingIgnoredDuringExecution` (soft — scheduler tries to match but will place anywhere if it can't).
  - **Taints and Tolerations** — Works in the opposite direction. A taint on a node **repels** pods. A toleration in the pod spec allows the pod to be scheduled onto a tainted node — it does not attract the pod there, it only removes the repulsion. Taint effects are: `NoSchedule` (no new pods without toleration), `PreferNoSchedule` (soft version), and `NoExecute` (evicts existing pods without toleration too).

**Third simulation — StatefulSet pod stuck Pending:** Create a StatefulSet with a `volumeClaimTemplates` entry requesting a `storageClassName` that does not exist.
1. Find why `postgres-0` is Pending — hint: the block is on the PVC, not the pod itself
  - `postgres-0` will be stuck in `Pending`. The StatefulSet controller creates the PVC first; because the `storageClassName` does not exist, no provisioner can satisfy the claim and the PVC stays `Pending` indefinitely. Kubernetes will not start `postgres-0` until its PVC is `Bound` — so the pod never leaves `Pending`. `kubectl describe pod postgres-0` shows: `persistentvolumeclaim "postgres-data-postgres-0" is not bound`.
2. Follow the lookup chain: `kubectl describe pod` → `kubectl describe pvc` → `kubectl get storageclass`
3. Fix it by correcting the `storageClassName` to one that exists in your cluster
4. Key insight: StatefulSets wait for a pod's PVC to bind before starting the next pod in order — one bad `storageClassName` blocks the entire rollout at `postgres-0`, whereas a Deployment would just have all pods Pending simultaneously and the failure is more obvious

---

## Scenario 2 — Pod in `CrashLoopBackOff`

**Simulate it:** Deploy a pod with command `exit 1`.
```bash
    kubectl create deploy test-deploy --image=busybox:latest -n prac --dry-run=client -o yaml > test-deploy.yml
```
**Your task:**
1. Identify the exit code from the pod status
  - The exit code is found in `kubectl describe pod <pod>` under `Containers` → `Last State: Terminated` → `Exit Code: <number>`.
  - Always check `Exit Code` in the describe output, not just the status string.

2. Get logs from the crashed container (it is dead — how do you get logs from a dead pod?)
  - `kubectl logs <pod> -p` — the `-p` flag fetches logs from the **previous** (already terminated) container instance. Without `-p`, `kubectl logs` targets the current container state which may not exist or may be empty after a crash. For a container that crashes immediately with no output, logs will be empty even with `-p`, but `-p` is still always the correct first command to run.

3. Distinguish between these crash patterns by simulating each:
   - **Container exits immediately (bad command):** `kubectl describe pod` → `Last State: Terminated`, `Reason: Error`, `Exit Code: 1` (or `127` if command not found). Status cycles: `Error` → `CrashLoopBackOff`. Backoff delay doubles each time (10s → 20s → 40s → up to 5min). Logs are usually empty.
   - **Liveness probe fails:** The container DOES start and run — it is not crashing. Kubernetes itself kills and restarts it after the probe fails `failureThreshold` times. `kubectl describe pod` Events section shows: `Liveness probe failed: HTTP probe failed with statuscode: 404`. This also results in `CrashLoopBackOff` but the distinction is the container ran fine — the probe was misconfigured.
   - **OOMKilled:** The container starts, runs, and allocates memory beyond its `limits.memory`. The Linux kernel OOM killer sends SIGKILL. `kubectl describe pod` → `Last State: Terminated`, `Reason: OOMKilled`, `Exit Code: 137`. No log is produced at the moment of kill.

4. For OOMKilled: find the exact OOM event and identify which container caused it
  - `kubectl describe pod <pod>` → `Containers` section → look for `Last State: Terminated` with `Reason: OOMKilled` and `Exit Code: 137`. The container name listed in that block is the one that caused it.
  - Exit code `137` = `128 + 9` — the `9` is SIGKILL, sent by the kernel OOM killer when the container exceeded its memory limit. This is the definitive identifier for OOMKill.

---

## Scenario 3 — Pod in `ImagePullBackOff`

**Simulate it:** Deploy a pod with image `nginx:does-not-exist-version`.
```bash
    kubectl create deploy test-deploy --image=nginx:does-not-exist-version -n prac --dry-run=client -o yaml > test-deploy.yml
```
**Your task:**
1. Find the exact error message
  - `Failed to pull image "nginx:does-not-exist-version": rpc error: code = NotFound desc = failed to pull and unpack image "docker.io/library/nginx:does-not-exist-version": failed to resolve reference "docker.io/library/nginx:does-not-exist-version": docker.io/library/nginx:does-not-exist-version: not found`

2. Distinguish between:
   - **Image tag does not exist:** `kubectl describe pod` Events section shows `rpc error: code = NotFound` or `not found`. The registry responded with HTTP 404 — the image tag simply doesn't exist. Status is `ImagePullBackOff`.
   - **Image is private:** Events section shows `unauthorized: authentication required` or `access denied` or `pull access denied`. The image exists in the registry but the cluster has no valid credentials to pull it. The key word to look for is `unauthorized` — that tells you it is an auth problem, not a missing tag.

3. Fix the image tag issue — change the image to a valid tag e.g. `nginx:1.25` and apply.

4. Simulate a private registry: create an `imagePullSecret` with fake credentials, attach it to a pod, and observe the auth failure message (different from "image not found")
  - Create the secret:
    ```bash
    kubectl create secret docker-registry my-pull-secret \
      --docker-server=registry.example.com \
      --docker-username=fake-user \
      --docker-password=fake-password \
      -n prac
    ```
  - Attach it in the pod spec under `spec.imagePullSecrets: [{name: my-pull-secret}]`.
  - The auth failure message will say `unauthorized: incorrect username or password` — clearly different from the `not found` you see for a missing tag.
  ```bash
      kubectl apply -f pull-secret.yml
      kubectl apply -f private-deploy.yml
  ```

**You should know how to answer:**
- What is an imagePullSecret and how do you attach it to a pod?
  - An `imagePullSecret` is a Kubernetes Secret of type `kubernetes.io/dockerconfigjson` that stores registry credentials (server, username, password encoded as base64 JSON). The kubelet reads it when the container runtime needs to pull a private image.
  - Create: `kubectl create secret docker-registry <name> --docker-server=<> --docker-username=<> --docker-password=<> -n <ns>`
  - Attach: add `imagePullSecrets: [{name: <secret-name>}]` under `spec` in the pod/deployment manifest.

- How do you set a default imagePullSecret for all pods in a namespace?
  - Patch the `default` ServiceAccount in that namespace to include the secret. All pods that don't explicitly set `serviceAccountName` use the default SA, so the pull secret is automatically injected into every pod in the namespace.
    ```bash
      kubectl patch serviceaccount default -n <ns> \
        -p '{"imagePullSecrets": [{"name": "<secret-name>"}]}'

        OR
      kubectl apply -f default-sa-patch.yml
    ```

---

## Scenario 4 — Service Not Reachable

**Simulate it:** Create a Service with a wrong label selector (does not match any pod).

**Your task — debug systematically:**
1. `kubectl get endpointslice <service>` — what does it show?
  - The `ENDPOINTS` column is empty. `kubectl get endpointslice <service> -n <ns>` shows `<none>` in the ENDPOINTS column. This means the Service's label selector matched zero pods — no pod IPs were registered as backends. The Service exists and is healthy, but it has nowhere to forward traffic to.

2. Find the label mismatch between Service selector and pod labels
  - `kubectl describe svc <service> -n <ns>` → look at `Selector:` field (e.g. `app=my-app`)
  - `kubectl get pods -n <ns> --show-labels` → compare labels on running pods
  - Spot the mismatch (e.g. pod has `app=myapp`, service selector has `app=my-app`) and fix the service selector or the pod label.

3. Fix it
  - Edit the Service: `kubectl edit svc <service> -n <ns>` → correct the `selector` field to match the pod labels. OR label the pod: `kubectl label pod <pod> app=my-app -n <ns>`.

4. Now simulate a second problem: Service correct but pod is in `CrashLoopBackOff` — endpoints exist but requests fail. Trace the full path.
  - **Without a readiness probe (default):** The pod IP is still registered in endpoints even when the container is crashed, because Kubernetes only removes a pod from endpoints when it fails a readiness probe. So: DNS resolves → ClusterIP routes to pod IP → connection reaches the pod → **Connection refused** (no process is listening on the port because the container is dead). The Service is not broken — the application is.
  - **With a readiness probe configured:** The pod fails the probe while in CrashLoopBackOff → Kubernetes removes the pod IP from endpoints → `kubectl get endpoints` shows `<none>` again → requests fail at the Service level before even reaching the pod. This is the correct production setup — a readiness probe prevents a crashed pod from receiving traffic.
  - Full trace: `curl <service>` → CoreDNS resolves to ClusterIP → kube-proxy iptables DNAT rule rewrites to pod IP → TCP to pod IP:port → **refused** (no container listening).

**You should know how to answer:**
- What does empty endpoints (`<none>`) on a service tell you?
  - It means the Service has no pod IPs registered as backends. Three possible causes: 
    - (1) no pods match the Service's label selector, 
    - (2) matching pods are Pending or not yet assigned an IP, 
    - (3) matching pods exist and have IPs but are **failing their readiness probe** — Kubernetes actively removes unhealthy pods from endpoints to protect traffic.

- How do you test connectivity from one pod to a service without external tools?
  - Run a temporary debug pod or exec into an existing pod and test via the full DNS name:
    ```bash
    # DNS + HTTP test
    kubectl exec -it <pod> -n <ns> -- curl <service-name>.<namespace>.svc.cluster.local:<port>

    # DNS resolution only
    kubectl exec -it <pod> -n <ns> -- nslookup <service-name>.<namespace>.svc.cluster.local

    # If curl is not in the image — use wget (busybox) or /dev/tcp
    kubectl exec -it <pod> -n <ns> -- wget -qO- <service-name>:<port>
    ```
  - The full DNS format `<service>.<namespace>.svc.cluster.local` is important — just `<service>` works only within the same namespace.

---

## Scenario 5 — Node is `NotReady`

**Simulate it (on Oracle Free Tier or AWS cluster — requires a real VM you can SSH into):** SSH into the worker node and stop kubelet.
```bash
# Oracle: ssh -i <key> ubuntu@<worker_public_ip>
# AWS:    ssh -i ~/.ssh/id_rsa ubuntu@<worker_public_ip>
sudo systemctl stop kubelet
```

> As we know the kubelet tasks is to connect the worker-node to the control-plane node. Also it continuously updates the Kube-API server, regarding the Pod's health in fixed interval of time.

**Your task:**
1. From master, observe the node status change (takes ~40 seconds)

2. Observe what happens to pods that were running on that node
  - Immediately after kubelet stops: pods appear `Running` in `kubectl get pods` — the API server still holds their last known state.
  - After ~40s: node flips to `NotReady`. The `node-lifecycle-controller` applies the `node.kubernetes.io/not-ready:NoExecute` taint automatically.
  - The endpoint controller **removes the pod IPs from endpoints** for pods on the NotReady node — the Service stops routing traffic to them if there are no other replicas on healthy nodes.
  - After `tolerationSeconds` (default 300s = 5 minutes): pods are force-evicted. Pods owned by a Deployment/ReplicaSet/StatefulSet are rescheduled on healthy nodes. Standalone pods (no owning controller) are simply deleted and NOT recreated.
  - You CAN issue `kubectl` commands (the API server is unaffected), but the kubelet on the NotReady node won't act on them — changes don't take effect on that node.

3. Find the reason for `NotReady` using `kubectl describe node`
  - `kubectl describe node <node-name>` → look at the `Conditions:` section. Find the entry where `Type: Ready` has `Status: False` (or `Unknown`).
  - The `Reason` field will say `KubeletNotReady` or `NodeStatusUnknown` and the `Message` field will say: `kubelet stopped posting node status` — this is the definitive indicator that kubelet has stopped communicating with the API server.

4. Restore kubelet and watch the node recover
  - `sudo systemctl start kubelet` on the worker node.
  - Node transitions back to `Ready` within ~10–20 seconds. The taint is removed automatically. Pods that were evicted are rescheduled back (if their controller still exists).

5. Understand the `node.kubernetes.io/not-ready` taint that gets automatically applied
  - Effect is `NoExecute` (not just `NoSchedule`). `NoExecute` does two things: (1) blocks new pods without a matching toleration from being scheduled, AND (2) evicts existing pods that do not have a toleration for it. This is why pods eventually leave the node even if they were already running.
  - System components (e.g., DaemonSet pods) carry a toleration for this taint with `tolerationSeconds: 300`, giving them a 5-minute grace period before eviction — to survive transient node blips.

**Second simulation:** Stop containerd instead of kubelet on the worker. Different failure — find the difference in the diagnostic output.
  - Modern K8s clusters use **containerd** directly via the CRI (Container Runtime Interface), not Docker daemon. Kubelet talks to containerd through CRI to create/start/stop containers.
  - If containerd is stopped: the node may initially stay `Ready` (kubelet is still running and reporting), but any new pod scheduled to that node will get stuck in `ContainerCreating` — because kubelet cannot call containerd to start the container. `kubectl describe pod` Events: `Failed to create pod sandbox: ... connection refused` or `failed to invoke ContainerCreate`.
  - Existing pods: containers already running are kernel processes. They continue running temporarily. But kubelet can no longer manage them (can't exec, can't probe, can't restart on crash).
  - Eventually kubelet itself may fail as it depends on containerd for health reporting → node transitions to `NotReady` — same end state as stopping kubelet, but the path is different and `ContainerCreating` is the early distinguishing symptom.

**You should know how to answer:**
- What is node eviction? When does K8s automatically move pods off an unhealthy node?
  - Node eviction is the process where the `node-lifecycle-controller` (inside `kube-controller-manager`) removes pods from a NotReady node after a grace period.
  - Timeline: Node goes NotReady → `node.kubernetes.io/not-ready:NoExecute` taint applied → pods with `tolerationSeconds: 300` (the default K8s adds automatically) wait 300 seconds → after 300s they are force-deleted → controllers (Deployment, ReplicaSet, StatefulSet) reschedule them on healthy nodes → standalone pods are simply deleted and gone.
  - What triggers it: kubelet stops heartbeating (stopped, crashed, network partition), node VM shut down, OOM on node killing kubelet.

- What is the `tolerationSeconds` on the `not-ready` taint and why does it exist?
  - `tolerationSeconds: 300` is a field on a pod's toleration for the `not-ready:NoExecute` taint. It means: "allow this pod to keep running on the NotReady node for up to 300 seconds before evicting it."
  - It is managed by the `node-lifecycle-controller`, not the API server.
  - It exists to tolerate transient node issues (brief network blip, short kubelet restart) without causing unnecessary pod churn and rescheduling. If the node recovers within 300 seconds, the pod stays put and never gets evicted. Only a sustained outage beyond the grace period triggers eviction.

---

## Scenario 6 — etcd Backup and Restore (Control Plane Disaster)

**Scenario:** Simulate a disaster recovery situation.

**Your task:**
1. Take an etcd snapshot:
   ```bash
   sudo ETCDCTL_API=3 etcdctl snapshot save /tmp/etcd-backup.db \
     --endpoints=https://127.0.0.1:2379 \
     --cacert=/etc/kubernetes/pki/etcd/ca.crt \
     --cert=/etc/kubernetes/pki/etcd/server.crt \
     --key=/etc/kubernetes/pki/etcd/server.key
   ```
2. Verify the snapshot: `etcdctl snapshot status /tmp/etcd-backup.db`
3. Deploy something after the snapshot (a new deployment)
4. Restore from the snapshot — this will roll back that deployment
5. Verify the cluster recovered

**You should know how to answer:**
- Why is etcd backup critical? What is lost if etcd dies without a backup?
- What is the recommended backup frequency for etcd in production?

---

## Scenario 7 — Broken Cluster (Put It All Together)

This is your final test for this task.

**Setup:** Run this command to intentionally break several things in your cluster. Do NOT look at what it does before diagnosing.

Manually do these actions yourself (simulate the "broken cluster" by doing them):
1. Delete the `kube-proxy` DaemonSet from `kube-system`
2. Add a wrong image to the `coredns` deployment
3. Set a wrong label on one of your services

**Your task:**
1. Start from `kubectl get nodes` and `kubectl get pods -A`

2. Identify all problems without being told what they are
  - **kube-proxy deleted:** `kubectl get pods -A` shows zero kube-proxy pods in `kube-system`. `kubectl get ds -n kube-system` confirms the DaemonSet is gone. Impact: the iptables/ipvs DNAT rules that map ClusterIPs → pod IPs no longer exist or update. ALL service-based routing fails cluster-wide — even if DNS resolves a ClusterIP, no rule forwards that traffic to a pod.
  - **CoreDNS wrong image:** `kubectl get pods -n kube-system` shows coredns pods in `ImagePullBackOff` or `ErrImagePull`. Impact: DNS resolution fails for all service names. `nslookup kubernetes` from any pod returns `SERVFAIL`.
  - **Wrong service label:** `kubectl get endpoints <service>` shows `<none>`. `kubectl describe svc <service>` → `Selector` doesn't match any pod labels. Impact: scoped to that one service only — not cluster-wide. DNS resolves the ClusterIP but traffic has nowhere to go.
  - Characterizing this as "deny-all network policy" is inaccurate — NetworkPolicy is a separate L3/L4 mechanism. This is a cascading failure across three distinct layers: routing (kube-proxy), DNS (CoreDNS), and service targeting (label selector).

3. Fix them in order of impact severity
  - **1st — kube-proxy** (cluster-wide routing broken): Reinstall the kube-proxy DaemonSet. Without it, no ClusterIP works at all — every service across every namespace fails. Without fixing this first, even testing other fixes is impossible via service names or IPs.
    ```bash
    kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/kind/main/pkg/internal/apis/config/v1alpha4/zz_generated.defaults.go
    # OR restore from: kubectl get ds kube-proxy -n kube-system -o yaml (if you have a backup)
    ```
  - **2nd — CoreDNS image** (cluster-wide DNS broken): Fix the image tag on the CoreDNS deployment. Without DNS, no pod can resolve any service name — applications fail even if routing works.
    ```bash
    kubectl set image deploy/coredns coredns=registry.k8s.io/coredns/coredns:v1.11.1 -n kube-system
    ```
  - **3rd — wrong service label** (one service affected): Fix the selector on the specific service. This has the smallest blast radius — only one service is broken.
    ```bash
    kubectl edit svc <service> -n <ns>  # correct the selector to match pod labels
    ```

4. Document your investigation steps — pretend you are writing an incident report
  - **Detection:** Alert fired / user reported: application unreachable.
  - **Step 1 — Cluster health:** `kubectl get nodes` → all nodes Ready. Problem is not at infrastructure layer.
  - **Step 2 — Pod health:** `kubectl get pods -A` → coredns pods in `ImagePullBackOff`; no kube-proxy pods visible in kube-system at all.
  - **Step 3 — Identify missing kube-proxy:** `kubectl get ds -n kube-system` → kube-proxy DaemonSet absent. This is how you find it — you don't guess, you look at what's supposed to be in kube-system. kube-proxy is a DaemonSet that must always be present.
  - **Step 4 — DNS test:** `kubectl exec -it <any-running-pod> -- nslookup kubernetes` → SERVFAIL → confirms CoreDNS is broken.
  - **Step 5 — Routing test (bypass DNS):** `kubectl exec -it <pod> -- curl <service-clusterIP>:<port>` → connection timeout even with direct IP → confirms kube-proxy iptables rules are missing.
  - **Step 6 — Service label check:** `kubectl get endpoints <service> -n <ns>` → `<none>` despite pods running → `kubectl describe svc <service>` → selector mismatch found.
  - **Root cause:** Three simultaneous changes: kube-proxy DaemonSet deleted, CoreDNS image corrupted, service label misconfigured.
  - **Fix applied:** Restored kube-proxy DS, corrected CoreDNS image, fixed service selector.
  - **Verification:** `kubectl get pods -n kube-system` → all healthy; `nslookup kubernetes` → resolves; `curl <service>` → responds.

---

## Scenario 8 — Certificate Expiry (The Silent Killer)

**Scenario:** A company's entire K8s cluster stopped accepting API requests at 3am. `kubectl` commands returned TLS errors. The cause: cluster certificates expired. kubeadm-provisioned clusters have 1-year certificates. This scenario causes more production outages than most engineers expect, and almost everyone who has operated K8s long enough has hit it.

**Your task:**

1. Check your cluster's certificate expiry dates:
   ```bash
   sudo kubeadm certs check-expiration
   ```
   This shows all certs and when they expire — API server, etcd, front-proxy, kubelet, admin.conf, etc.

2. Understand the output:
   - The admin kubeconfig (`admin.conf`) — used by `kubectl` — has its own cert that expires separately
   - Control plane certs are in `/etc/kubernetes/pki/`

3. Renew all certificates (safe to run even if certs are not expired — use this for practice):
   ```bash
   sudo kubeadm certs renew all
   ```

4. After renewal, the `admin.conf` kubeconfig is updated. Copy it:
   ```bash
   sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
   sudo chown $(id -u):$(id -g) $HOME/.kube/config
   ```

5. Restart control plane components to pick up new certs (they are static pods — delete them and kubelet restarts them):
   ```bash
   sudo crictl ps | grep -E "kube-apiserver|kube-controller|kube-scheduler"
   # Note the container IDs, then:
   sudo crictl stop <apiserver-container-id>
   sudo crictl stop <controller-manager-container-id>
   sudo crictl stop <scheduler-container-id>
   # kubelet will restart them automatically
   ```

6. Verify cluster is healthy after renewal:
   ```bash
   kubectl get nodes
   sudo kubeadm certs check-expiration   # should show 1 year validity now
   ```

**Production practice:**
In real companies, certificate renewal is automated via a CronJob that runs `kubeadm certs renew all` 30 days before expiry, or by using a managed K8s service (EKS, GKE, AKS) where the control plane certs are managed for you.

**You should know how to answer:**
- "How long are kubeadm cluster certificates valid and how do you renew them?"
- "If `kubectl` suddenly returns a TLS error and was working yesterday — what is the first thing you check?"
- "How do you automate certificate renewal in production?"

---

## Scenario 9 — Node Pressure Conditions (DiskPressure / MemoryPressure)

**Scenario:** A node shows `Ready` but pods are being evicted without explanation. Checking the node shows `DiskPressure: True`. This is a garbage collection and eviction problem — not a pod problem.

**Your task:**

1. Understand the three node pressure conditions:
   | Condition | Trigger | K8s Action |
   |-----------|---------|------------|
   | `MemoryPressure` | Node RAM < threshold | Evict best-effort pods (no resource limits) first |
   | `DiskPressure` | Node disk < threshold | Evict pods with large temp data, then others |
   | `PIDPressure` | Too many processes | Evict pods to free PIDs |

2. Simulate DiskPressure: write a large file on the node to exhaust disk space:
   ```bash
   # On the node (Oracle/AWS SSH)
   dd if=/dev/zero of=/tmp/bigfile bs=1M count=15000   # 15GB file
   ```
   Watch: `kubectl get nodes -w` — the node will show `DiskPressure`
   Watch: `kubectl get events -A | grep -i evict` — pods being evicted
   
3. Clean up and observe pressure clear:
   ```bash
   rm /tmp/bigfile
   ```

4. Check the kubelet's eviction thresholds:
   ```bash
   # On the node
   sudo cat /var/lib/kubelet/config.yaml | grep -A5 eviction
   ```
   Default: evict when `memory.available < 100Mi` or `nodefs.available < 10%`

5. Understand eviction ordering: `BestEffort` → `Burstable` → `Guaranteed` (this is QoS class — pods with no limits die first to protect pods with limits)

**You should know how to answer:**
- "Pods on a node are being randomly evicted. How do you investigate?"
- "What are the three K8s QoS classes and which gets evicted first under pressure?"
- "What is the difference between eviction and deletion?"

---

## Completion Checklist

- [ ] Diagnose and fix Pending pods (resource, node selector, taints)
- [ ] Diagnose CrashLoopBackOff including OOMKilled
- [ ] Debug ImagePullBackOff including private registry issues
- [ ] Trace a full service connectivity failure from endpoint to pod
- [ ] Simulate and recover from a node failure
- [ ] Take and restore an etcd backup
- [ ] Check and renew cluster certificates using kubeadm
- [ ] Identify and respond to DiskPressure / MemoryPressure on a node

---

## Interview Questions This Task Prepares You For

- "Walk me through how you would debug a pod stuck in Pending state."
- "An application pod is in CrashLoopBackOff. What is your process?"
- "How do you troubleshoot a service that is not receiving traffic?"
- "A node went NotReady at 3am. What are your first five commands?"
- "How do you do disaster recovery in Kubernetes?"
- "What does OOMKilled mean and how do you prevent it?"
- "Our entire cluster's API stopped responding at 3am with TLS errors. What happened?"
- "Pods on a node are being evicted without us deleting them. What are you checking?"
- "What are K8s QoS classes and why do they matter during node pressure events?"
- "What does OOMKilled mean and how do you prevent it?"

---

## Mini Project — Fix a Broken Namespace (Simulated Incident)

> Estimated time: 1.5 hours. Document your process — this is more important than the fix itself.

**Scenario:** You received an alert at 9am: "All pods in `team-alpha` are down. Services unreachable. On-call is you."

**Setup — break your own cluster by running these (do this THEN start the timer):**

```bash
# Before breaking anything: take an etcd snapshot (Scenario 6 — do this first, always)
# Run this inside the control plane node (kind: docker exec -it <control-plane-container> bash)
ETCDCTL_API=3 etcdctl snapshot save /tmp/etcd-backup.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key
# Verify snapshot is healthy
ETCDCTL_API=3 etcdctl snapshot status /tmp/etcd-backup.db

# Break 1: Scale down a deployment to 0 without using HPA
kubectl scale deployment alpha-api -n team-alpha --replicas=0

# Break 2: Change the Service selector to a wrong label
kubectl patch svc alpha-api -n team-alpha -p '{"spec":{"selector":{"app":"alpha-api-wrong"}}}'

# Break 3: Apply a NetworkPolicy that blocks all ingress including internal
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: block-all
  namespace: team-alpha
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
EOF

# Break 4: Introduce a crashing pod
kubectl run crasher -n team-alpha --image=busybox -- /bin/sh -c "exit 1"

# Break 5 (Scenario 9 — Node Pressure): Deploy a memory-hungry pod to push the node toward MemoryPressure
# NOTE: This may not reliably trigger MemoryPressure in kind — it depends on how much memory
# your local machine has allocated to Docker. If it doesn't fire, that's fine.
# The goal here is just to observe node Conditions and QoS eviction ordering.
# Scenario 9 in the exercises covers this topic properly with full explanation.
kubectl run memory-hog -n team-alpha --image=polinux/stress \
  -- stress --vm 1 --vm-bytes 800M --timeout 120s
# Watch node conditions: kubectl describe node | grep -A3 "Conditions:"
# Observe: MemoryPressure=True, pods begin to be evicted by QoS order (BestEffort first)
```

**Your task:** Start a timer. Find and fix ALL 5 issues as fast as possible.

**Deliverables — `incident-report.md`:**
```
## Incident Report

### Timeline
- 09:00 — Alert received
- 09:XX — First observation: ...
- 09:XX — Root cause identified: ...
- 09:XX — Fix applied: ...
- 09:XX — Service restored

### Root Causes Found
1. ...
2. ...
3. ...
4. ...
5. ...

### Commands Used to Diagnose Each Issue
...

### Fix Applied
...

### Prevention
How would you prevent each of these in a real company setup?

### etcd Snapshot
Paste the output of `etcdctl snapshot status /tmp/etcd-backup.db` taken before breaking the cluster.
Explain: when would you use this snapshot in a real incident?
```

This incident report format is exactly what companies expect in post-mortems. Practice writing it quickly and clearly.

---

**Next: Task-09-Real-World-Project.md**
