# K8s Storage — Concepts & Notes

---

## The Storage Chain

```
StorageClass  →  defines HOW to provision (which provisioner, which params)
  PersistentVolume (PV)  →  the actual disk (created manually or auto by provisioner)
    PersistentVolumeClaim (PVC)  →  a pod's request for storage
      Pod  →  mounts the PVC at a path
```

- **PV** — ClusterScoped
- **PVC** — NamespaceScoped
- **StorageClass** — ClusterScoped

Developers write PVCs. The platform team manages StorageClasses and PV availability.

---

## Static vs Dynamic Provisioning

### Static Provisioning
- Admin manually creates PVs ahead of time — like reserving a parking spot before the car arrives.
- K8s matches a PVC to an existing PV if ALL of these satisfy:
  - `spec.capacity.storage`: PV ≥ PVC request
  - `accessModes`: PV must support the requested mode(s)
  - `storageClassName`: PV and PVC must have compatible values
  - PV must be in `Available` state
- **Size waste**: a PVC of 500Mi bound to a 1Gi PV reserves the entire 1Gi. The remaining 500Mi is wasted — no other PVC can use it.
- `storageClassName` is just a **matching label**, NOT a lookup into the StorageClass registry. The StorageClass resource does not need to exist for static binding to work. K8s matches PV + PVC directly if their fields align.

### Dynamic Provisioning
- No manual PV creation. A StorageClass + provisioner auto-creates a PV when a PVC is submitted.
- Preferred at scale — no wasted capacity, no manual work per disk.

---

## StorageClass
  - A StorageClass is a cluster-level resource that defines a "type" of storage.
    - which provisioner creates the disk, what parameters it uses, and how binding works.
Key fields:
- **`provisioner`** — the plugin that creates the actual disk (e.g., `rancher.io/local-path`, `kubernetes.io/aws-ebs`, `hostpath.csi.k8s.io`)
- **`reclaimPolicy`** — what happens to the PV when its PVC is deleted (`Delete` or `Retain`)
- **`volumeBindingMode`**:
  - `Immediate` — PV is created and bound as soon as the PVC is created, even before any pod uses it. Binds to a random node, which can later cause a node affinity conflict if the pod lands on a different node.
  - `WaitForFirstConsumer` — PV is NOT created until a pod actually schedules and tries to use the PVC. Ensures the disk is created on the same node where the pod lands. **A PVC in `Pending` with this mode is NOT an error** — it is waiting for a pod to consume it.

---

## PV Lifecycle States

| State | Meaning |
|---|---|
| `Available` | PV exists, not bound to any PVC, ready to be claimed |
| `Bound` | PV is claimed by a PVC and in use |
| `Released` | The PVC was deleted, but the PV still holds the old data. Cannot be claimed by a new PVC until an admin manually clears the `claimRef` field. |
| `Failed` | Automatic reclamation failed |

---

## Reclaim Policies

| Policy | What happens when PVC is deleted | When to use |
|---|---|---|
| `Retain` | PV keeps its data. Admin must manually clean it up and re-mark it `Available`. | Production databases — safety net against accidental deletion |
| `Delete` | PV and its backing storage are automatically deleted. | Dynamic provisioning (cloud disks). Convenient but risky. |
| `Recycle` *(deprecated)* | PV is wiped (`rm -rf`) and made `Available` again. | Don't use. Replaced by dynamic provisioning. |

---

## Access Modes

| Mode | Short | Meaning |
|---|---|---|
| `ReadWriteOnce` | RWO | One **node** can mount read-write at a time |
| `ReadOnlyMany` | ROX | Many nodes can mount read-only simultaneously |
| `ReadWriteMany` | RWX | Many nodes can mount read-write simultaneously |

**Critical RWO detail — per node, not per pod:**
  - RWO is per-*node*, not per-pod. Multiple pods on the *same node* can all use an RWO volume simultaneously.
  - If a pod using the volume is running on node-1, another pod on node-2 cannot mount the same RWO volume at the same time.Depending on the storage backend, the second pod may remain Pending or fail with a Multi-Attach error.
  - Multi-Attach errors are typical for cloud block storage such as AWS EBS and Azure Disk, which enforce single-node attachment.
    - If `spec.awsElasticBlockStore` not `spec.hostPath`
    - Most cloud block disks (AWS EBS, Azure Disk) are RWO only.
  - A hostPath volume is different—it is simply a directory on a node's local filesystem. It isn't "attached" to nodes, so there is no Multi-Attach error. Instead, a pod scheduled to another node simply won't see the same data because that node has its own local filesystem.
  - RWX requires a distributed filesystem like NFS, CephFS, or AWS EFS.

---

## Volume Types Comparison

| Type | Survives pod restart? | Survives pod deletion? | Shared across pods? | Typical use |
|---|---|---|---|---|
| `emptyDir` | Yes (same pod) | No | No (same pod only) | Sidecar log sharing, temp processing, init→app handoff |
| `hostPath` (direct) | Yes (same node) | Yes (file stays on node) | Only pods on same node | Accessing node-level files (logs, Docker socket) |
| PVC | Yes | Yes | Yes (depends on access mode) | Databases, user uploads, anything that must persist |

### emptyDir
- An `emptyDir` volume is created fresh and empty when a pod starts.
- It solves a real problem, where **two containers in the same pod can't share files unless they have a shared volume**. 
- Created fresh and empty when a pod starts. Lives on the node. Shared between all containers **in the same pod**.
- Deleted permanently when the pod is deleted.
- Solves the sidecar problem: without `emptyDir`, container A and container B each have isolated filesystems — A cannot share a log file with B.
- Production uses: app writes logs → log-shipper sidecar reads from `/shared`; init container writes config → app container reads it; scratch space for temporary processing.

### hostPath
- A directory on the node's local filesystem. Not a "device" — no attachment model, so no Multi-Attach error. But data is node-local: pod rescheduled to another node sees that node's own directory, not the original data.
- A manually created `hostPath` PV without `nodeAffinity` is a ghost — it resolves to a different physical directory depending on which node the pod lands on.

---

## StatefulSet — volumeClaimTemplate and Headless Service

### volumeClaimTemplate
- Instead of referencing an existing PVC, you define a template inside the StatefulSet spec.
- K8s auto-creates a **unique PVC per pod replica**: `postgres-0` always gets `data-postgres-0`, `postgres-1` always gets `data-postgres-1`.
- PVCs created by a StatefulSet are **NOT deleted** when the StatefulSet is deleted — they persist. Recreating a StatefulSet with the same name and template re-attaches the same PVCs, so data survives.
- This behaviour is controlled by `persistentVolumeClaimRetentionPolicy` (K8s 1.27+) — default is `Retain`.

### Headless Service (`clusterIP: None`)
- A normal Service gives one stable ClusterIP that load-balances across all pods. For a database, you need to talk to `postgres-0` specifically (the primary), not a random replica.
- A headless service skips the ClusterIP entirely. DNS returns the individual pod IPs directly.
- DNS format: `<pod-name>.<service-name>.<namespace>.svc.cluster.local`
  - e.g. `postgres-0.postgres.team-alpha.svc.cluster.local`
- This is how database replication works: the replica connects to the primary by name, not a random IP.

### Why StatefulSet scales sequentially
- Scale up: `postgres-0` must be `Running` and `Ready` before `postgres-1` starts. Ensures each node can register with the cluster before the next one joins.
- Scale down: pods are deleted in reverse order (`postgres-2` before `postgres-1`). Ensures the most recent replicas are removed first — primary is last.

---

## fsGroup — What It Does and Its Limits

`securityContext.fsGroup` performs two operations:

| Step | What happens | Works for hostPath? |
|---|---|---|
| 1 | Recursively `chown :fsGroup` the mounted volume directory | **No** — skipped for hostPath |
| 2 | Adds `fsGroup` GID to container process as a supplemental group | **Yes** — always applied |

**For hostPath, only step 2 happens.** The directory on the node must ALREADY be owned by the `fsGroup` GID with group-write bits (`chmod 770`, `chown root:<fsGroup-GID>`). Then step 2 makes the container a group member → write succeeds.

**Common trap:** Using `/root/` (permissions `700`, `drwx------`) as the hostPath. Even after chowning the group, the permission bits are `---` for the group field. Group membership is useless when group bits are zero.

**For managed volumes** (emptyDir, CSI-provisioned PVCs): step 1 DOES run — K8s recursively chowns the volume directory on mount. This is the normal expected behaviour.

---

## VolumeSnapshot
- A VolumeSnapshot is a point-in-time copy of a PVC's data, taken at the storage driver level. It's like a database snapshot — instant (copy-on-write at the disk level), not a slow file-by-file backup.
Three objects:
- **`VolumeSnapshotClass`** — defines which CSI driver handles snapshots. Created once by admin. (Analogous to StorageClass for PVs.)
- **`VolumeSnapshot`** — your request to snapshot a specific PVC. You create one per snapshot.
- **`VolumeSnapshotContent`** — the actual backing snapshot at the storage level. Auto-created by the driver. (Analogous to PV for PVC.)

**`local-path-provisioner` is NOT a CSI driver** — it has no snapshot capability. Use `csi-hostpath-driver` in kind, or a real cloud CSI driver (EBS CSI, GKE PD CSI, Azure Disk CSI) in production.

### VolumeSnapshot vs Velero

| | VolumeSnapshot | Velero |
|---|---|---|
| What it covers | One PVC | Entire namespace/cluster (PVCs + all K8s objects) |
| Speed | Very fast (storage-level, copy-on-write) | Slower (copies data byte-by-byte) |
| Cross-cluster restore | No — driver-specific | Yes |
| Storage | Cloud disk snapshot | S3 / GCS / Azure Blob |
| Use case | Quick rollback before a migration | Full disaster recovery, cluster migration |

### When to use what

```
 "I'm about to run a risky DB migration and want a 5-minute rollback option"
   → VolumeSnapshot (fast, storage-level, single PVC)

 "The entire cluster died / we're migrating to a new cloud region"
   → Velero restore (full namespace, all objects + data)

 "We need to comply with a 30-day backup retention policy"
   → Velero scheduled backups to S3 (automated, auditable)
```

**Interview answer:** *"For a quick pre-migration rollback of a single database — VolumeSnapshot, because it's instant and storage-level. For full disaster recovery or moving between clusters — Velero, because it backs up both the PVC data and all the Kubernetes object definitions together, and stores everything in S3 so it survives cluster loss."*

---

## Debugging Cheatsheet

```bash
# Always start here — Events section at the bottom tells you everything
kubectl describe pod <pod-name> -n <namespace>

kubectl get pvc -n <namespace>
kubectl describe pvc <pvc-name> -n <namespace>

kubectl get pv
kubectl describe pv <pv-name>

# If using dynamic provisioning, check the provisioner logs
kubectl get pods -n local-path-storage
kubectl logs -n local-path-storage <provisioner-pod-name>
```

**PVC stuck in Pending — two completely different causes:**

| Cause | `describe pvc` says | Fix |
|---|---|---|
| No volume available | `no PersistentVolume found` | Create a matching PV or fix StorageClass/provisioner |
| WaitForFirstConsumer | `waiting for first consumer to be created before binding` | Deploy a pod that uses the PVC — NOT an error |

---

## The Portability Takeaway

A PVC does not guarantee that storage is portable.

It only guarantees that the **pod is decoupled from the storage implementation**.

Whether data can move with the pod depends on what backs the PV:
- `hostPath` → data is stuck on one node
- NFS / Ceph / EBS / Azure Disk / Longhorn → data can generally follow the pod

A `hostPath`-backed PV is persistent only as long as that node and its local filesystem remain available.
