# Task 07 — Troubleshooting: Debugging a Broken Cluster

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
kubectl get endpoints <service> -n <ns>
kubectl exec -it <pod> -- curl <service>:<port>
kubectl exec -it <pod> -- nslookup <service>
```

---

## Scenario 1 — Pod is Stuck in `Pending`

**Simulate it:** Create a pod requesting 100 CPUs (more than your cluster has).

**Your task:**
1. Identify WHY the pod is pending (do not just read the answer — run the commands and find it)
2. Identify which specific condition is blocking scheduling
3. Resolve it by adjusting the resource request to something reasonable
4. Understand the `describe pod` output — specifically the `Events` section at the bottom

**Second simulation:** Create a pod with a `nodeSelector` for a label that no node has.
1. Find why it is pending
2. Fix it by adding the label to a node
3. Explain: what is the difference between nodeSelector, nodeAffinity, and taints/tolerations for node targeting?

---

## Scenario 2 — Pod in `CrashLoopBackOff`

**Simulate it:** Deploy a pod with command `exit 1`.

**Your task:**
1. Identify the exit code from the pod status
2. Get logs from the crashed container (it is dead — how do you get logs from a dead pod?)
3. Distinguish between these crash patterns by simulating each:
   - Container exits immediately (bad command)
   - Container runs but liveness probe fails (use wrong probe path)
   - Container runs out of memory (OOMKilled — set memory limit to 1Mi)
4. For OOMKilled: find the exact OOM event and identify which container caused it

---

## Scenario 3 — Pod in `ImagePullBackOff`

**Simulate it:** Deploy a pod with image `nginx:does-not-exist-version`.

**Your task:**
1. Find the exact error message
2. Distinguish between:
   - Image tag does not exist
   - Image is private (requires imagePullSecret)
3. Fix the image tag issue
4. Simulate a private registry: create an `imagePullSecret` with fake credentials, attach it to a pod, and observe the auth failure message (different from "image not found")

**You should know how to answer:**
- What is an imagePullSecret and how do you attach it to a pod?
- How do you set a default imagePullSecret for all pods in a namespace?

---

## Scenario 4 — Service Not Reachable

**Simulate it:** Create a Service with a wrong label selector (does not match any pod).

**Your task — debug systematically:**
1. `kubectl get endpoints <service>` — what does it show?
2. Find the label mismatch between Service selector and pod labels
3. Fix it
4. Now simulate a second problem: Service correct but pod is in `CrashLoopBackOff` — endpoints exist but requests fail. Trace the full path.

**You should know how to answer:**
- What does empty endpoints (`<none>`) on a service tell you?
- How do you test connectivity from one pod to a service without external tools?

---

## Scenario 5 — Node is `NotReady`

**Simulate it (on Oracle Free Tier or AWS cluster — requires a real VM you can SSH into):** SSH into the worker node and stop kubelet.
```bash
# Oracle: ssh -i <key> ubuntu@<worker_public_ip>
# AWS:    ssh -i ~/.ssh/id_rsa ubuntu@<worker_public_ip>
sudo systemctl stop kubelet
```

**Your task:**
1. From master, observe the node status change (takes ~40 seconds)
2. Observe what happens to pods that were running on that node
3. Find the reason for `NotReady` using `kubectl describe node`
4. Restore kubelet and watch the node recover
5. Understand the `node.kubernetes.io/not-ready` taint that gets automatically applied

**Second simulation:** Stop containerd instead of kubelet on the worker. Different failure — find the difference in the diagnostic output.

**You should know how to answer:**
- What is node eviction? When does K8s automatically move pods off an unhealthy node?
- What is the `tolerationSeconds` on the `not-ready` taint and why does it exist?

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
3. Fix them in order of impact severity
4. Document your investigation steps — pretend you are writing an incident report

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
```

**Your task:** Start a timer. Find and fix ALL 4 issues as fast as possible.

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

### Commands Used to Diagnose Each Issue
...

### Fix Applied
...

### Prevention
How would you prevent each of these in a real company setup?
```

This incident report format is exactly what companies expect in post-mortems. Practice writing it quickly and clearly.

---

**Next: Task-08-Real-World-Project.md**
