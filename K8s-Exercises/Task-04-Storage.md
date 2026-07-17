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

**Scenario:** You are setting up storage for a legacy app that requires a pre-provisioned volume.

**Your task:**
1. Create a PersistentVolume with:
   - Name: `alpha-pv`
   - Storage: 1Gi
   - Access mode: `ReadWriteOnce`
   - Reclaim policy: `Retain`
   - HostPath: `/data/alpha` (for local cluster practice)
2. Create a PersistentVolumeClaim `alpha-pvc` in `team-alpha` that requests 500Mi
3. Deploy a pod that mounts `alpha-pvc` at `/app/data`
4. Write a file into the mounted path from inside the pod
5. Delete the pod, recreate it, and verify the file is still there
6. Delete the PVC — check what happens to the PV (it should be `Released`, not deleted, because of `Retain` policy)

**You should know how to answer:**
- What are the three reclaim policies and when do you use each?
- What does it mean when a PV is in `Released` state vs `Available`?

---

## Exercise 2 — Dynamic Provisioning with StorageClass

**Scenario:** Developers should be able to request storage without asking the DevOps team to manually create PVs every time.

**Your task:**
1. Check what StorageClasses exist in your cluster
2. Use the default StorageClass to create a PVC — observe that a PV is automatically created
3. Create a custom StorageClass named `fast-local` using the `rancher.io/local-path` provisioner (install local-path-provisioner first):
   ```
   kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.26/deploy/local-path-storage.yaml
   ```
4. Create a PVC using `fast-local` StorageClass and verify dynamic provisioning works
5. Mark `fast-local` as the cluster default StorageClass — verify that PVCs without a storageClassName now use it

**You should know how to answer:**
- What happens if you create a PVC and no StorageClass can satisfy it?
- Why is dynamic provisioning preferred over static at scale?

---

## Exercise 3 — StatefulSet (The Right Way to Run a Database)

**Scenario:** `team-alpha` wants to run a PostgreSQL instance in the cluster.

**Your task:**
1. Deploy a StatefulSet named `postgres` in `team-alpha` with:
   - Image: `postgres:15`
   - 1 replica initially
   - Environment variable `POSTGRES_PASSWORD` from a Secret
   - A `volumeClaimTemplate` that requests 1Gi storage with `ReadWriteOnce`
2. Observe the pod name format: `postgres-0` (not random like Deployments)
3. Connect to the database from inside the pod using `psql`
4. Create a test table and insert a row
5. Delete the pod `postgres-0` — watch it get recreated with the SAME name
6. Reconnect and verify your data is still there
7. Scale to 2 replicas — observe `postgres-1` gets its own separate PVC

**Headless Service (required for StatefulSet DNS):**
Create a headless Service (clusterIP: None) for postgres. Then from another pod, resolve:
- `postgres-0.postgres.team-alpha.svc.cluster.local`
- `postgres-1.postgres.team-alpha.svc.cluster.local`

Explain why this individual pod DNS is important for databases (replication, master-slave setup).

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
   - `log-shipper` container: tails `/shared/app.log` and prints it to stdout (simulating Filebeat)
   - Both share an `emptyDir` volume mounted at `/shared`
2. Check logs from the `log-shipper` container — verify it reads what `app` writes
3. Explain: what happens to the `/shared` data if the pod is deleted?

**You should know how to answer:**
- What is the difference between `emptyDir`, `hostPath`, and a PVC?
- When would you use `emptyDir` in production?

---

## Exercise 5 — Volume Debugging

**Scenario:** A developer reports "my pod is stuck in `ContainerCreating`." It's a storage issue.

**Simulate and solve each:**

**Problem 1:** PVC in `Pending` state
- Create a PVC requesting a StorageClass that doesn't exist
- Find why it's pending and fix it

**Problem 2:** Permission denied on mounted volume
- Mount a hostPath volume that is owned by `root`
- Pod runs as a non-root user and can't write to it
- Fix it using `securityContext.fsGroup`

**Problem 3:** PVC already bound to another pod
- Try to mount a `ReadWriteOnce` PVC in two pods on different nodes simultaneously
- Observe the failure and explain why

**For each:** write down the kubectl commands you used to diagnose.

---

## Exercise 6 — VolumeSnapshots (Backup Your PVCs)

**Scenario:** Your PostgreSQL StatefulSet has important data in its PVC. Before running a risky schema migration, you need to take a point-in-time snapshot of the volume so you can restore if it goes wrong. This is the K8s-native backup mechanism.

**Background:** VolumeSnapshots are a K8s feature that lets you take a snapshot of a PVC. A `VolumeSnapshotClass` defines the driver (like a StorageClass), a `VolumeSnapshot` is the actual snapshot request, and a `VolumeSnapshotContent` is the backing resource.

**Your task:**

1. Check if your cluster supports VolumeSnapshots:
   ```bash
   kubectl get crd | grep volumesnapshot
   ```
   If using kind with local-path-provisioner, install the snapshot CRDs and controller:
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/client/config/crd/snapshot.storage.k8s.io_volumesnapshotclasses.yaml
   kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/client/config/crd/snapshot.storage.k8s.io_volumesnapshotcontents.yaml
   kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/client/config/crd/snapshot.storage.k8s.io_volumesnapshots.yaml
   ```

2. From the PostgreSQL StatefulSet in Exercise 3, create a `VolumeSnapshot` of the `postgres-0` PVC:
   ```yaml
   apiVersion: snapshot.storage.k8s.io/v1
   kind: VolumeSnapshot
   metadata:
     name: postgres-snapshot-before-migration
     namespace: team-alpha
   spec:
     volumeSnapshotClassName: csi-hostpath-snapclass
     source:
       persistentVolumeClaimName: postgres-data-postgres-0
   ```

3. Observe the `VolumeSnapshot` and `VolumeSnapshotContent` objects created
4. Simulate data corruption: connect to postgres and `DROP TABLE` your test table
5. Restore from snapshot: create a new PVC sourced from the snapshot:
   ```yaml
   apiVersion: v1
   kind: PersistentVolumeClaim
   metadata:
     name: postgres-restored
     namespace: team-alpha
   spec:
     storageClassName: standard
     dataSource:
       name: postgres-snapshot-before-migration
       kind: VolumeSnapshot
       apiGroup: snapshot.storage.k8s.io
     accessModes: [ReadWriteOnce]
     resources:
       requests:
         storage: 1Gi
   ```
6. Mount the restored PVC in a new pod and verify your data is there

**You should know how to answer:**
- "How do you back up a PVC in Kubernetes?"
- "What is the difference between a VolumeSnapshot and a backup tool like Velero?"
- "Can you restore a VolumeSnapshot to a different namespace or cluster?"

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

---

**Next: Task-05-RBAC-and-Security.md**
