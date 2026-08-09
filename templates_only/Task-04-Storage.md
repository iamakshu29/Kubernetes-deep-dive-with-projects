# Task 04 — Storage: Persistent Data in a K8s Cluster

> Real-world relevance: Stateless apps are easy. The hard part is stateful apps - databases, file uploads and shared config that must survive pod restarts and rescheduling.
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
  → PersistentVolume (the actual disk which stores the data — provisioned manually or auto-created)
    → PersistentVolumeClaim (a pod's request for storage)
      → Pod (mounts the PVC at a path)
```

At a company: developers write PVCs in their app manifests. The DevOps/platform team manages StorageClasses and ensures PVs are available or dynamically provisioned.

---

## Exercise 1 — Static Provisioning (Manual PV)

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

**You should know how to answer:**
- What are the three reclaim policies and when do you use each?
- What does it mean when a PV is in `Released` state vs `Available`?(Also cover: what is the `Bound` state, and how do you make a Released PV available again?)

---

## Exercise 2 — Dynamic Provisioning with StorageClass

> If your PVC stays `Pending` even after installing the provisioner, this is usually because — **no pod is using the PVC yet**.

**Scenario:** Developers should be able to request storage without asking the DevOps team to manually create PVs every time.

**Your task:**
1. Check what StorageClasses exist in your cluster:
Notice the `volumeBindingMode: WaitForFirstConsumer` — this is why PVCs using it stay `Pending` until a pod consumes them.

2. Try creating a PVC with default StorageClass and observe it stays `Pending`:

3. Install the Rancher local-path-provisioner to install another StorageClass
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
      volumeBindingMode: Immediate
   ```
   Then create a PVC using `storageClassName: fast-local` and a pod that uses it — watch the PV get auto-created as `volumeBindingMode: Immediate` which is default mode

5. Mark `fast-local` as the cluster default StorageClass — verify that PVCs without a `storageClassName` now use it:


**You should know how to answer:**
- What happens if you create a PVC and no StorageClass can satisfy it?
- Why does a PVC with `WaitForFirstConsumer` stay `Pending` even after installing a provisioner?
- Why is dynamic provisioning preferred over static at scale?

---

## Exercise 3 — StatefulSet (The Right Way to Run a Database)

- volumeClaimTemplate → creates a PVC for each replica.
- volumeMounts → mounts that PVC into the container.

**Scenario:** `team-alpha` wants to run a PostgreSQL instance in the cluster.

**Your task:**
1. Deploy a StatefulSet named `postgres` in `team-alpha` with:
   - Image: `postgres:15`
   - 1 replica initially
   - Environment variable `POSTGRES_PASSWORD` sourced from a Secret `postgres-secret`
   - A `volumeClaimTemplate` that requests 1Gi storage with `ReadWriteOnce`
2. Notice the PVC is named `<volumeClaimTemplate.metadata.name>-<pod-name>`.
3. Notice the PV is also created with CLAIM as PVC named
4. Connect to the database from inside the pod using psql
5. Create db testdb, create a user table and insert a row
6. Delete the pod `postgres-0` - watch it recreate with the SAME name and SAME PVC:
7. Reconnect and verify data is still there
8. Scale to 2 replicas — observe that `postgres-1` gets its own separate PVC:
9. Resolve the headless Service from another pod:
    - `postgres-0.postgres.team-alpha.svc.cluster.local`
    - `postgres-1.postgres.team-alpha.svc.cluster.local`
10. Explain why this individual pod DNS is important for databases (replication, master-slave setup).

**You should know how to answer:**
- What is the difference between a Deployment and a StatefulSet for running databases?
- What happens to PVCs when you delete a StatefulSet?
- Why does a StatefulSet scale up and down sequentially?
---

## Exercise 4 — Shared Storage with emptyDir and Multi-Container Pods

**Scenario:** An app writes logs to a file. A sidecar container needs to read those logs and ship them.

**Your task:**
1. Create a pod with two containers:
    - `app` container: writes a timestamp to `/shared/app.log` every 5 seconds (use a busybox with a shell loop)
    - `log-shipper` container: tails `/shared/app.log` and prints it to stdout (use a busybox simulating Filebeat)
2. Check logs from the `log-shipper` container — verify it reads what `app` writes: You should see the timestamps being printed in real time.
3. Explain: What happens to the `/shared` data if the pod is deleted?

**You should know how to answer:**
- When would you use `emptyDir` in production?
- What is the difference between `emptyDir`, `hostPath`, and a PVC?

---

## Exercise 5 — Volume Debugging

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
- Create a PVC that references a PV or provisioned that does not exist.
- Find why it is pending and fix it.

---

**Problem 2: Permission denied on mounted volume**
- Mount a `hostPath` PersistentVolume backed by a directory owned by `root` with group-exclusive write (`chmod 770, chown root:2000`).
- Pod runs as a non-root user (`runAsUser: 1000`) with a primary group that is NOT GID 2000 → Permission denied.
- Fix using `securityContext.fsGroup: 2000`.

---

**Problem 3: RWO PVC — simulating single-node exclusive access**
- Demonstrate that a `ReadWriteOnce` volume can only be used from one node at a time.
- Use dynamic provisioning so the PV is physically tied to one node.
- Force two pods onto different nodes and observe the conflict.

---

**You should know how to answer:**
- What kubectl commands do you run first when a pod is stuck in `ContainerCreating`?
- What is the difference between RWO, ROX, and RWX access modes?
- What does `fsGroup` do, and when do you need it?
- Why can't you edit the `storageClassName` of an existing PVC?
- RWO allows one node — does that mean two pods on the same node can both mount it?

---

## Exercise 6 — VolumeSnapshots (Backup Your PVCs) 

**VolumeSnapshot FLOW:**
```bash
- StorageClass (with csi-hostpath as provisioner) -> VolumeSnapshotClass (using csi-hostpath as driver)
- Postgres Secret -> Postgres-StatefuleSet + Service -> Write Some Data in DB
- Create VolumeSnapshot (After writing data as point in time snapshot) -> Wait for VolumeSnapshot `ReadyToUse=true`
- Now drop the table, if want to from statefulset postgres DB.
- Restore the PVC from the VolumeSnapshot created
- Create a new Pod, attaching the restored PVC → Verify that, the data is present.
```

**NOTE** - If unable to install csi driver in kind cluster, use KillerCoda.

**Scenario:** Your PostgreSQL StatefulSet has important data in its PVC. Before running a risky schema migration, you need to take a point-in-time snapshot of the volume so you can restore if it goes wrong. This is the K8s-native backup mechanism.


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
     cd csi-driver-host-path/deploy/kubernetes-1.35
     bash deploy.sh
 ```
```bash
    kubectl get csidrivers
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
Re-deploy your PostgreSQL StatefulSet using `storageClassName: csi-hostpath-sc` for this exercise.

2. From the postgreSQL StatefulSet, Create a `VolumeSnapshot` of the `postgres-0` PVC:
```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: postgres-snapshot-before-migration
  namespace: team-alpha
spec:
  volumeSnapshotClassName: csi-hostpath-snapclass
  source:
    persistentVolumeClaimName: db-data-postgres-0
```

3. Observe the `VolumeSnapshot` and `VolumeSnapshotContent` get created.
  - Wait for it to be ready: Look for: ReadyToUse: true

4. Simulate data corruption — connect to postgress and drop your users table.

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
- "Walk me through the storage provisioning flow in K8s."
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
   - Readiness probe: `pg_isready` command (# Used first Time as tutorial)
     - With proper DB name and User name
3. `postgres-service.yaml` — Headless service (clusterIP: None) for stable DNS
(**IMPORTANT**:  How to create a client-server thingy)
4. `test-pod.yaml` — A temporary pod that acts as a client and connects to postgres statefulset server:  creates a table, inserts a row, queries it, then exits.
**INSIGHTS AFTER DEBUGGING**
  - Use a Pod with --image=postgres as a client, because other Pods (like busybox, curlimages) dont have the psql installed.
  - Client become Another PostgreSQL server
    - The official PostgreSQL image starts a PostgreSQL server `by default`.
    - The test pod became another database server instead of a client.
    - Command shows multiple postgress PIDs - `ps -ef`
    - Override the command: `sleep infinity`, to stop the pod working as Server,so the pod acts only as a client which required psql only.
    - Check the endpointSlice if None. Check the labels, serviceName correctly.
    - Verify Server Pod is reachable from Client Pod - `getent hosts postgres-0.postgres-svc`
    - Check Postgres Server network connectivity from Client Pod - `pg_isready -h postgres-svc`
      - Earlier it shows error due to left over networkpolicies from earlier Tutorials (This finding waste 1 hr of time, Keep in mind from now on)
5. Reconnect to postgres server and verify data

**Proof of completion:**
- Run the test pod — show it successfully inserted and queried data
- Delete the `postgres-0` pod manually — show it comes back with the same PVC
- Reconnect and show the data is still there
- `kubectl get pvc -n team-alpha` shows the bound volume

- Explain: what would happen to this PVC if you ran `kubectl delete statefulset postgres`?

---

**Next: Task-05-RBAC-and-Security.md**