# Task 04 — Storage: Persistent Data in a K8s Cluster

> Real-world relevance: Stateless apps are easy. The hard part is databases, file uploads,
> and shared config that must survive pod restarts and rescheduling.
> This is where most junior engineers make mistakes in production.

> **Cluster needed:** 2-node cluster. Single-node works for most exercises but node-failure simulation (Exercise 3) needs 2 nodes.
> - **For core storage exercises:** kind 2-node — see **00-Setup.md Option A1**.
> - **For node-failure simulation (Exercise 3):** Use Oracle Free Tier or AWS EC2 — you can stop a real VM from the console to simulate node loss. See **00-Setup.md Options B/C**.
> - **Dynamic provisioning (Exercise 2):** Install `local-path-provisioner` — command is inside Exercise 2.
> - **NOT recommended:** Killercoda for this task — sessions expire and you lose storage state mid-exercise.

---

## What You Will Learn

- Why you cannot store data inside a pod
- PersistentVolume (PV), PersistentVolumeClaim (PVC), StorageClass — how they connect
- Dynamic vs static provisioning
- Access modes and what they mean for multi-pod scenarios
- StatefulSets — the right way to run databases in K8s
- Real debugging: volume mount failures, permission issues

---

## Background — Read Before Starting

Pod storage is ephemeral. When a pod dies and is replaced, all data written inside it is gone.

The K8s storage chain:
```
StorageClass (defines HOW to provision storage)
  → PersistentVolume (the actual disk — manually or auto-created)
    → PersistentVolumeClaim (a pod's request for storage)
      → Pod (mounts the PVC at a path)
```

At a company: developers write PVCs in their app manifests. The DevOps/platform team manages StorageClasses and ensures PVs are available or dynamically provisioned.

---

## Exercise 1 — Static Provisioning (Manual PV)

**What is Static Provisioning?**
  - A cluster admin manually creates a PersistentVolume (PV) ahead of time — like reserving a parking spot before the car arrives.
  - A developer then creates a PVC, and K8s matches it to an existing PV that satisfies the request.
    - Capacity: PV `spec.capacity.storage` >=  `spec.resources.requests.storage` in PVC.
    - AccessModes: The PV must support the requested access mode(s).
    - StorageClassName: The PV and PVC must have compatible storageClassName values.
    - The PV must be available.
  - This is the old-school way. You manage every disk by hand. Painful at scale but sometimes required for pre-existing infrastructure.

**Scenario:** You are setting up storage for a legacy app that requires a pre-provisioned volume.

**Your task:**
1. Create a PersistentVolume with:
   - Name: `alpha-pv`
   - Storage: 1Gi
   - Access mode: `ReadWriteOnce`
   - Reclaim policy: `Retain`
   - HostPath: `/tmp/data/` (for local cluster practice)
   - Write a index.html file into the mounted HostPath `/tmp/data/`
2. Create a PersistentVolumeClaim `alpha-pvc` in `team-alpha` that requests 500Mi
3. Deploy a pod that mounts `alpha-pvc` at `/usr/share/nginx/html` with image as `nginx:1.25`
4. Delete the pod, recreate it, and verify the file is still there
5. Delete the PVC — check what happens to the PV (it should be `Released`, not deleted, because of `Retain` policy)

**CRITICAL — kind cluster HostPath:**
  - In kind, your cluster nodes are Docker containers running on your Windows machine.
  - A `hostPath` like `/tmp/data/` refers to the filesystem **inside the kind worker node container**, NOT your Windows filesystem.
  - To make it work, You must exec into the worker node container first:
   ```bash
     # Exec into the kind worker node and create file at the hostPath inside this container
     docker exec -it <kind-worker-node-name> bash
   ```

**Important — PV/PVC size binding rule:**
  - When a PVC requests 500Mi and binds to a 1Gi PV, the **entire 1Gi PV becomes exclusively reserved** for that PVC.
  - The remaining 500Mi is NOT available to any other PVC — it is wasted.
  - This is another reason static provisioning is painful at scale — you either over-provision and waste space, or under-provision and requests go unmet.

**You should know how to answer:**
- What are the three reclaim policies and when do you use each?
  - **Retain** — PV keeps its data after PVC is deleted. Admin must manually clean it up and make it Available again. Use this for production databases — safety net.
  - **Delete** — PV and its backing storage are automatically deleted when the PVC is deleted. Common with dynamic provisioning (cloud disks). Convenient but risky.
  - **Recycle** (deprecated) — PV is wiped (`rm -rf`) and made Available again. Replaced by dynamic provisioning. Don't use in modern clusters.

- What does it mean when a PV is in `Released` state vs `Available`?(Also cover: what is the `Bound` state, and how do you make a Released PV available again?)
  - **Available** — PV exists, not bound to any PVC, ready to be claimed.
  - **Bound** — PV is claimed by a PVC and in use.
  - **Released** — The PVC that was bound to it has been deleted, but the PV still holds the old data. It cannot be claimed by a new PVC until an admin manually clears the `claimRef` field on the PV. This is intentional with `Retain` — K8s protects the data until a human decides what to do with it.

---

## Exercise 2 — Dynamic Provisioning with StorageClass

**What is a StorageClass?**
  - A StorageClass is a cluster-level resource that defines a "type" of storage — which provisioner creates the disk, what parameters it uses, and how binding works.
  - Key fields in a StorageClass:
    - `provisioner` — the plugin that creates the actual disk (e.g., `rancher.io/local-path`, `kubernetes.io/aws-ebs`)
    - `reclaimPolicy` — what happens to the PV when the PVC is deleted (`Delete` or `Retain`)
    - `volumeBindingMode` — **this is the one that trips people up:**
    - `Immediate` — PV is created and bound as soon as the PVC is created, even with no pod.
    - `WaitForFirstConsumer` — PV is NOT created until a pod actually tries to use the PVC. This avoids creating a disk on the wrong node before the scheduler decides where the pod lands.
> If your PVC stays `Pending` even after installing the provisioner, this is usually why — **no pod is using the PVC yet**.

**Scenario:** Developers should be able to request storage without asking the DevOps team to manually create PVs every time.

**Your task:**
1. Check what StorageClasses exist in your cluster:
   ```bash
      kubectl get storageclass
   ```
Notice the `volumeBindingMode: WaitForFirstConsumer` — this is why PVCs using it stay `Pending` until a pod consumes them.

2. Try creating a PVC with default StorageClass and observe it stays `Pending`:
   ```bash
      kubectl apply -f alpha-pvc.yml
      kubectl get pvc    # stays Pending — expected, because WaitForFirstConsumer
   
      # he PV will only be created when a pod that uses this PVC is scheduled.
      # Deploy a pod that uses the PVC and then re-check — the PVC will bind.
   ```

3. Install the Rancher local-path-provisioner to install a StorageClass
   ```bash
      kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.26/deploy/local-path-storage.yaml
   ```
   Verify it appeared:
   ```bash
   kubectl get storageclass
   ```

4. Create a custom StorageClass named `fast-local` that uses the local-path provisioner:
   ```yaml
      apiVersion: storage.k8s.io/v1
      kind: StorageClass
      metadata:
        name: fast-local
      provisioner: rancher.io/local-path
      reclaimPolicy: Delete
      volumeBindingMode: WaitForFirstConsumer
   ```
   Then create a PVC using `storageClassName: fast-local` and a pod that uses it — watch the PV get auto-created.

5. Mark `fast-local` as the cluster default StorageClass — verify that PVCs without a `storageClassName` now use it:
   ```bash
      # First unmark the current default
      kubectl patch storageclass standard -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
      # Set fast-local as default
      kubectl patch storageclass fast-local -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
      kubectl get storageclass    # fast-local should show (default)
   ```

**You should know how to answer:**
- What happens if you create a PVC and no StorageClass can satisfy it?
- Why does a PVC with `WaitForFirstConsumer` stay `Pending` even after installing a provisioner?
- Why is dynamic provisioning preferred over static at scale?

---

## Exercise 3 — StatefulSet (The Right Way to Run a Database)

**What is `volumeClaimTemplate`?**
  - Each pod in StatefulSet gets its **own dedicated PVC** via `volumeClaimTemplate` — `postgres-0` always gets `data-postgres-0`, `postgres-1` always gets `data-postgres-1`.
  - Normally you create one PVC and reference it in a pod. With a StatefulSet, instead of referencing an existing PVC, you define a *template* inside the StatefulSet spec. 
  - Kubernetes uses that template to auto-create a unique PVC for each pod replica. 
  - This is the key feature that makes StatefulSets suitable for databases.

**What is a Headless Service and why does StatefulSet need it?**
  - A normal Service gets a single stable IP (ClusterIP) that load-balances across all pods.
    - For databases, you don't want that — you need to talk to `postgres-0` specifically (the primary), not a random replica.
  - A headless Service (`clusterIP: None`) skips the load-balancer IP entirely. Instead, DNS returns the IPs of the individual pods directly.
    - `<pod-name>.<service-name>.<namespace>.svc.cluster.local`

**Scenario:** `team-alpha` wants to run a PostgreSQL instance in the cluster.

**Your task:**
1. Deploy a StatefulSet named `postgres` in `team-alpha` with:
   - Image: `postgres:15`
   - 1 replica initially
   - Environment variable `POSTGRES_PASSWORD` sourced from a Secret `postgres-secret`
   - A `volumeClaimTemplate` that requests 1Gi storage with `ReadWriteOnce`
  ```bash
      # Create secret
      kubectl create secret generic postgres-secret --from-literal=DB_PASSWORD=supersecurepassword
      
      # Create stateful Set
      kubectl apply -f postgres_statefulset.yml
  ```
2. Notice the PVC is named `<volumeClaimTemplate.metadata.name>-<pod-name>`.
  ```bash
      kubectl get pvc
      # db-data-postgres-0 
  ```
3. Notice the PV is also created with CLAIM as PVC named
  ```bash
      kubectl get pv
  ```
4. Connect to the database from inside the pod using psql
  ```bash
    kubectl exec -it postgres-0 -- sh
    psql -U postgres
  ```
5. Create db testdb, create a user table and insert a row
  ```bash
    CREATE DATABASE testdb;
    \c testdb
    CREATE TABLE users (id SERIAL PRIMARY KEY,name TEXT);
    INSERT INTO users (name) VALUES ('alice');
    INSERT INTO users (name) VALUES ('john');
    SELECT * FROM users;
  ```
6. Delete the pod `postgres-0` - watch it recreate with the SAME name and SAME PVC:
  ```bash
      kubectl delete pod postgres-0
  ```
7. Reconnect and verify data is still there
  ```bash
    kubectl exec -it postgres-0 -- sh

    pssql -U postgres
    \c testdb
    SELECT * FROM users;
  ```
8. Scale to 2 replicas — observe that `postgres-1` gets its own separate PVC:
  ```bash
      kubectl scale statefulset postgres --replicas=2
      kubectl get pods
  ```
9. Resolve the headless Service from another pod:
    - `postgres-0.postgres.team-alpha.svc.cluster.local`
    - `postgres-1.postgres.team-alpha.svc.cluster.local`
  ```bash
      # as postgres Pod does not have nslookup
      kubectl run dns --image=busybox:1.36 --rm -it --restart=Never -- nslookup postgres-1.postgres.team-alpha.svc.cluster.local
      # you will get the Pod-IP resolved from DNS
  ```
10. Explain why this individual pod DNS is important for databases (replication, master-slave setup).

- volumeClaimTemplate → creates a PVC for each replica.
- volumeMounts → mounts that PVC into the container.

**You should know how to answer:**
- What is the difference between a Deployment and a StatefulSet for running databases?
- What happens to PVCs when you delete a StatefulSet?
- Why does a StatefulSet scale up and down sequentially?

---

## Exercise 4 — Shared Storage with emptyDir and Multi-Container Pods

**What is `emptyDir`?**
  - An `emptyDir` volume is created fresh and empty when a pod starts.
  - It lives on the node where the pod runs and is shared between all containers **in the same pod**.
    - When the pod is deleted, the `emptyDir` is permanently deleted too — the data is gone.
  - It solves a real problem, where **two containers in the same pod can't share files unless they have a shared volume**. 
  - Without `emptyDir`, if container A writes a log file, container B (the sidecar) can't read it — they each have their own isolated filesystem.

**Volume type comparison:**
| Volume Type | Survives pod restart? | Survives pod deletion?   | Shared across pods?          | Typical use                                         |
| -------------| -----------------------| --------------------------| ------------------------------| -----------------------------------------------------|
| `emptyDir`  | Yes (same pod)        | No                       | No (same pod only)           | Sidecar log sharing, temp processing, cache         |
| `hostPath`  | Yes (same node)       | Yes (file stays on node) | Only pods on same node       | Accessing node-level files (logs, Docker socket)    |
| PVC         | Yes                   | Yes                      | Yes (depends on access mode) | Databases, user uploads, anything that must persist |

**Scenario:** An app writes logs to a file. A sidecar container needs to read those logs and ship them.

**Your task:**
1. Create a pod with two containers:
    - `app` container: writes a timestamp to `/shared/app.log` every 5 seconds (use a busybox with a shell loop)
    - `log-shipper` container: tails `/shared/app.log` and prints it to stdout (use a busybox simulating Filebeat)
  ```bash
      kubectl apply -f shared-pod.yml
  ```
2. Check logs from the `log-shipper` container — verify it reads what `app` writes: You should see the timestamps being printed in real time.
  ```bash
       kubectl logs shared-pod -c log-shipper -f
  ```
3. Explain: What happens to the `/shared` data if the pod is deleted?

**You should know how to answer:**
- When would you use `emptyDir` in production?
  - Sidecar patterns: app writes logs to `/shared`, log-shipper (Filebeat/Fluentd) reads from `/shared`
  - Init containers passing data to app containers (init writes config, app reads it)
  - Temporary scratch space for processing (e.g., unzip a file, process it, upload result)
  - Never for data you need to keep — it dies with the pod
- What is the difference between `emptyDir`, `hostPath`, and a PVC?

---

## Exercise 5 — Volume Debugging

**Access Modes — understand these before debugging:**
Every PV and PVC declares an accessMode. K8s enforces this strictly at the storage driver level:
| Mode            | Short | Meaning                                                 |
| -----------------| -------| ---------------------------------------------------------|
| `ReadWriteOnce` | RWO   | One **node** can mount this volume read-write at a time |
| `ReadOnlyMany`  | ROX   | Many nodes can mount read-only simultaneously           |
| `ReadWriteMany` | RWX   | Many nodes can mount read-write simultaneously          |

**Critical RWO detail:** 
  - RWO is per-*node*, not per-pod. Multiple pods on the *same node* can all use an RWO volume simultaneously.
  - But if pod A has it on node-1, pod B on node-2 cannot also attach it — it will get stuck with a `Multi-Attach` error.
  - Most cloud block disks (AWS EBS, Azure Disk) are RWO only.
  - RWX requires a distributed filesystem like NFS, CephFS, or AWS EFS.

**Scenario:** A developer reports "my pod is stuck in `ContainerCreating`." It's a storage issue.

**General diagnosis flow — run these first, every time:**
  ```bash
  # Step 1: describe the pod — always check the Events section at the bottom
  kubectl describe pod <pod-name> -n <namespace>
  
  # Step 2: check PVC status
  kubectl get pvc -n <namespace>
  kubectl describe pvc <pvc-name> -n <namespace>
  
  # Step 3: check PV status
  kubectl get pv
  
  # Step 4: if using dynamic provisioning, check provisioner logs
  kubectl get pods -n local-path-storage
  kubectl logs -n local-path-storage <provisioner-pod-name>
  ```

---

**Problem 1: PVC in `Pending` state**
- Create a PVC that references a StorageClass that doesn't exist.
- Find it why it's pending and fix it
Diagnose
Fix
```bash
  Never was in pending state even if the storageClass is non-existent
```

**Problem 2: Permission denied on mounted volume**
- Mount a hostPath  persistent volume that is owned by `root` (e.g. /root, /opt/root-owned)
- Pod runs as a non-root user (runAsNonRoot: true, runAsUser: 1000) and can't write to it (use PSA)
  - Use image: busybox for it.
- Verify that the application cannot write to the mounted volume and receives a Permission denied error.
- Fix it using `securityContext.fsGroup`

Diagnose
```bash
    kubectl logs problem-two-pod
    sh: line 0: can't create /mnt/data/file.txt: Permission denied

```

Fix
```bash
    Not working even after applying fsgroup
```

**What is `securityContext.fsGroup`?**
  - By default, a mounted volume directory is owned by `root:root`. If your container runs as a non-root user, it cannot write to it — you'll get `Permission denied` errors in the pod logs.
  - `fsGroup` is a pod-level setting. When set, Kubernetes `chown`s the mounted volume's group ownership to that GID at mount time, so the container process (if it belongs to that group) can write to it.
 ```yaml
 spec:
   securityContext:
     fsGroup: 2000          # volume will be group-owned by GID 2000 at mount
   containers:
     - name: app
       securityContext:
         runAsUser: 1000    # container runs as UID 1000
         runAsGroup: 2000   # belongs to GID 2000 — matches fsGroup above
 ```

**Problem 3: PVC already bound to another pod**
- Try to mount a `ReadWriteOnce` PVC in two pods on different `nodes` simultaneously
- Observe the failure and explain why
  ```bash
    kubectl get nodes
      # As control-plane is tainted so use tolerations and nodeSelector so that first pod is place on that specific node only.
    
  ```
Diagnose
Fix

**For each:** write down the kubectl commands you used to diagnose.

**You should know how to answer:**
- What kubectl commands do you run first when a pod is stuck in `ContainerCreating`?
- What is the difference between RWO, ROX, and RWX access modes?
- What does `fsGroup` do, and when do you need it?
- Why can't you edit the `storageClassName` of an existing PVC?
- RWO allows one node — does that mean two pods on the same node can both mount it?

---

## Exercise 6 — VolumeSnapshots (Backup Your PVCs) 

**Scenario:** Your PostgreSQL StatefulSet has important data in its PVC. Before running a risky schema migration, you need to take a point-in-time snapshot of the volume so you can restore if it goes wrong. This is the K8s-native backup mechanism.

**Background:**
**What is a VolumeSnapshot?**
- A VolumeSnapshot is a point-in-time copy of a PVC's data, taken at the storage driver level. It's like a database snapshot — instant (copy-on-write at the disk level), not a slow file-by-file backup.
- Three objects involved:
   - **`VolumeSnapshotClass`** — defines which CSI driver handles snapshots (like `StorageClass` is for PVs). Created once by the admin.
   - **`VolumeSnapshot`** — your request to snapshot a specific PVC. You create this per-snapshot.
   - **`VolumeSnapshotContent`** — the actual backing snapshot object at the storage level. Auto-created by the driver (like a PV is auto-created for a PVC).

**VolumeSnapshot vs Velero:**
|                         | VolumeSnapshot                    | Velero                                            |
| -------------------------| -----------------------------------| ---------------------------------------------------|
| What it covers          | One PVC                           | Entire namespace/cluster (PVCs + all K8s objects) |
| Speed                   | Very fast (storage-level)         | Slower (copies data byte-by-byte)                 |
| Cross-cluster restore   | No — driver-specific              | Yes                                               |
| Cross-namespace restore | No                                | Yes                                               |
| Use case                | Quick rollback before a migration | Full disaster recovery, cluster migration         |

**IMPORTANT — kind + local-path-provisioner cannot do VolumeSnapshots:**
  - `local-path-provisioner` is NOT a CSI driver — it has no snapshot capability. Creating a `VolumeSnapshot` against a `local-path` PVC will fail even after installing the CRDs. To use VolumeSnapshots in kind, you must use the **csi-hostpath-driver** instead.
  - On real cloud clusters (EKS with EBS CSI, GKE with PD CSI, AKS with Azure Disk CSI), snapshot support is built in.

**Your task:**

1. Check if you cluster supports VolumeSnapshots:
  ```bash
  kubectl get crd | grep volumesnapshot
  ```
  If using kind with local-path-provisioner, Install the VolumeSnapshot CRDs and controller (required on any cluster that doesn't ship with them):
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/client/config/crd/snapshot.storage.k8s.io_volumesnapshotclasses.yaml
   kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/client/config/crd/snapshot.storage.k8s.io_volumesnapshotcontents.yaml
   kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/client/config/crd/snapshot.storage.k8s.io_volumesnapshots.yaml
   kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/deploy/kubernetes/snapshot-controller/rbac-snapshot-controller.yaml
   kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/deploy/kubernetes/snapshot-controller/setup-snapshot-controller.yaml

   kubectl get crd | grep volumesnapshot    # confirm CRDs exist
   ```

 **kind users — switch to csi-hostpath-driver:**
 ```bash
 git clone https://github.com/kubernetes-csi/csi-driver-host-path.git
 cd csi-driver-host-path
 deploy/kubernetes-latest/deploy.sh
 ```
 Then create a StorageClass and VolumeSnapshotClass for it:
 ```yaml
 apiVersion: storage.k8s.io/v1
 kind: StorageClass
 metadata:
   name: csi-hostpath-sc
 provisioner: hostpath.csi.k8s.io
 reclaimPolicy: Delete
 volumeBindingMode: Immediate
 ---
 apiVersion: snapshot.storage.k8s.io/v1
 kind: VolumeSnapshotClass
 metadata:
   name: csi-hostpath-snapclass
 driver: hostpath.csi.k8s.io
 deletionPolicy: Delete
 ```
 Re-deploy your PostgreSQL StatefulSet from Exercise 3 using `storageClassName: csi-hostpath-sc` for this exercise.

2. From the postgreSQL StatefulSet in Exercise-3, Create a `VolumeSnapshot` of the `postgres-0` PVC:
   ```yaml
   apiVersion: snapshot.storage.k8s.io/v1
   kind: VolumeSnapshot
   metadata:
     name: postgres-snapshot-before-migration
     namespace: team-alpha
   spec:
     volumeSnapshotClassName: csi-hostpath-snapclass
     source:
       persistentVolumeClaimName: data-postgres-0
   ```
Wait for it to be ready: Look for: ReadyToUse: true

3. Observe the `VolumeSnapshot` and `VolumeSnapshotContent` get created.
4. Simulate data corruption — connect to postgress and drop your test table.
5. Restore from snapshot — create a new PVC with the snapshot as its data source:
   ```yaml
   apiVersion: v1
   kind: PersistentVolumeClaim
   metadata:
     name: postgres-restored
     namespace: team-alpha
   spec:
     storageClassName: csi-hostpath-sc
     dataSource:
       name: postgres-snapshot-before-migration
       kind: VolumeSnapshot
       apiGroup: snapshot.storage.k8s.io
     accessModes: [ReadWriteOnce]
     resources:
       requests:
         storage: 1Gi
   ```
6. Mount the restored PVC in a temporary pod and verify data is back:

**You should know how to answer:**
  - How do you back up a PVC in Kubernetes?
  - What is the difference between a VolumeSnapshot and a backup tool like Velero?
  - Can you restore a VolumeSnapshot to a different namespace or cluster?
  - Why doesn't `local-path-provisioner` support VolumeSnapshots?
  - What is a `VolumeSnapshotClass` and how does it relate to a `StorageClass`?

---

**Where does this fit in the real world? — Velero and cloud-native backups**
  - In production at a company, engineers rarely write raw `VolumeSnapshot` YAMLs themselves. Here's how backup actually works at each level:

**On cloud clusters (EKS / GKE / AKS) — VolumeSnapshots work out of the box:**
  - The cloud provider installs a CSI driver for you (e.g., AWS EBS CSI, GKE PD CSI). You don't need to install anything. A VolumeSnapshot triggers an actual EBS snapshot / GCP Persistent Disk snapshot at the cloud level — it shows up in your AWS Console too.
 ```bash
 # On EKS — this just works, no driver setup needed
 kubectl apply -f my-volumesnapshot.yaml
 ```
  - Cloud teams use these for pre-migration rollbacks of individual databases.

**Velero — the full cluster backup tool:**
  - Velero is an open-source tool (by VMware) that backs up everything at once: PVC data + all K8s object definitions (Deployments, ConfigMaps, Secrets, RBAC, etc.).
  - It stores backups in object storage (S3, GCS, Azure Blob) so they survive even if the entire cluster is gone.
 ```bash
 # Install Velero (one-time, points to an S3 bucket)
 velero install --provider aws --bucket my-k8s-backups --backup-location-config region=us-east-1

 # Take a full namespace backup
 velero backup create team-alpha-backup --include-namespaces team-alpha

 # Restore into a different cluster or namespace
 velero restore create --from-backup team-alpha-backup
 ```
  - At companies: the platform/SRE team sets up Velero with scheduled nightly backups. Individual developers don't usually run it directly.

**When to use what — the mental model:**
 ```
 "I'm about to run a risky DB migration and want a 5-minute rollback option"
   → VolumeSnapshot (fast, storage-level, single PVC)

 "The entire cluster died / we're migrating to a new cloud region"
   → Velero restore (full namespace, all objects + data)

 "We need to comply with a 30-day backup retention policy"
   → Velero scheduled backups to S3 (automated, auditable)
 ```

 **Your interview answer (memorize this):**
   - *"For a quick pre-migration rollback of a single database — VolumeSnapshot, because it's instant and storage-level. For full disaster recovery or moving between clusters — Velero, because it backs up both the PVC data and all the Kubernetes object definitions together, and stores everything in S3 so it survives cluster loss."*

---

## Completion Checklist

- [ ] Create PVs manually and bind them with PVCs
- [ ] Explain and demonstrate all three reclaim policies
- [ ] Configure dynamic provisioning via StorageClass
- [ ] Deploy a StatefulSet with persistent storage that survives pod restarts
- [ ] Debug PVC pending and volume mount issues
- [ ] Take a VolumeSnapshot and restore data from it

---

## Interview Questions This Task Prepares You For

- "How would you run a database in Kubernetes? What are the trade-offs?"
- "What is the difference between a Deployment and a StatefulSet?"
- "Walk me through the storage provisioning flow in K8s."
- "A pod is stuck in ContainerCreating — how do you debug it?"
- "What happens to data when a pod is deleted? How do you prevent data loss?"
- "How do you back up your database PVC in Kubernetes before a migration?"

---

## Mini Project — Persistent PostgreSQL for team-alpha

> Estimated time: 2 hours. Put this in GitHub under `k8s-practice/task-04/`.

**Scenario:** `team-alpha` wants to persist their application data. You need to deploy PostgreSQL with real persistent storage so data survives pod restarts and node rescheduling.

**Deliverables — all as YAML files:**

1. `postgres-secret.yaml` — A Secret containing `POSTGRES_PASSWORD` and `POSTGRES_DB`
2. `postgres-statefulset.yaml` — StatefulSet with:
   - 1 replica
   - Image: `postgres:15`
   - `volumeClaimTemplate` requesting 1Gi with `ReadWriteOnce`
   - Env vars sourced from the Secret
   - Readiness probe: `pg_isready` command
3. `postgres-service.yaml` — Headless service (clusterIP: None) for stable DNS
4. `test-pod.yaml` — A temporary busybox pod that connects to postgres, creates a table, inserts a row, queries it, then exits

**Proof of completion (document in a `README.md`):**
- Run the test pod — show it successfully inserted and queried data
- Delete the `postgres-0` pod manually — show it comes back with the same PVC
- Reconnect and show the data is still there
- `kubectl get pvc -n team-alpha` shows the bound volume
- Explain in the README: what would happen to this PVC if you ran `kubectl delete statefulset postgres`?
- **VolumeSnapshot (Exercise 6):** Take a snapshot of the PVC while data is intact → delete the data row from inside postgres → restore the PVC from the snapshot → show the data is back. Run `kubectl get volumesnapshot -n team-alpha` to confirm the snapshot exists.

---

**Next: Task-05-RBAC-and-Security.md**

```
If you want fsGroup to work

Use a volume type that supports ownership management, such as:

emptyDir
many CSI-backed PersistentVolumes
some network filesystems

Or change the host directory permissions manually:

sudo chgrp 2000 /root
sudo chmod 770 /root

or

sudo chown root:2000 /some-directory

and use /some-directory instead of /root.

For your lab

If your lab is:

Problem 2: Permission denied on mounted volume

Mount a hostPath volume owned by root
Pod runs as a non-root user and can't write to it

then do not use fsGroup as the solution. It is actually useful to demonstrate that fsGroup is not sufficient for a hostPath pointing to /root, because the underlying host directory permissions remain unchanged. This reinforces that fsGroup is not a universal fix and that hostPath behaves differently from many other volume types.
```