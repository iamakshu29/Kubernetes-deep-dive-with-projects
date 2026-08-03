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
```bash
    kubectl get storageclass
    kubectl apply -f .
```

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
  - **Retain** — PV keeps its data after PVC is deleted. Admin must manually clean it up and make it Available again. Use this for production databases — safety net.
  - **Delete** — PV and its backing storage are automatically deleted when the PVC is deleted. Common with dynamic provisioning (cloud disks). Convenient but risky.
  - **Recycle** (deprecated) — PV is wiped (`rm -rf`) and made Available again. Replaced by dynamic provisioning. Don't use in modern clusters.

- What does it mean when a PV is in `Released` state vs `Available`?(Also cover: what is the `Bound` state, and how do you make a Released PV available again?)
  - **Available** — PV exists, not bound to any PVC, ready to be claimed.
  - **Bound** — PV is claimed by a PVC and in use.
  - **Released** — The PVC that was bound to it has been deleted, but the PV still holds the old data.
    - It cannot be claimed by a new PVC until an admin manually clears the `claimRef` field on the PV.
    - This is intentional with `Retain` — K8s protects the data until a human decides what to do with it.

---

## Exercise 2 — Dynamic Provisioning with StorageClass

> If your PVC stays `Pending` even after installing the provisioner, this is usually because — **no pod is using the PVC yet**.

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
      kubectl get pvc    # stays Pending — expected, because VOLUMEBINDINGMODE: WaitForFirstConsumer
   
      # The PV will only be created when a pod that uses this PVC is scheduled.
      # Deploy a pod that uses the PVC and then re-check — the PVC will bind.
   ```

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
   ```bash
      # First unmark the current default
      kubectl patch storageclass standard -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'

      # Set fast-local as default
      kubectl patch storageclass fast-local -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

      # fast-local should show (default)
      kubectl get storageclass    

      # You will see the error in events Message Column as why Immediate not work with local-path.
      # It works and suited for Amazon EFS, Azure Files like filesystem
      kubectl describe pvc rancher-pvc
   ```

**You should know how to answer:**
- What happens if you create a PVC and no StorageClass can satisfy it?
  - It will still be created and until it got a PV, it remains in pending state.

- Why does a PVC with `WaitForFirstConsumer` stay `Pending` even after installing a provisioner?
  - It is the feature of storageClass, it will stays Pending until we attached a PVC to a Pod.
  - It is because if the PV is created without knowing on which Pod it is schedules, then PV will never get attached to the Pod

- Why is dynamic provisioning preferred over static at scale?
  - It is preferred so that developers dont have to request everytime for the required PV.
  - In case of storage requirement they just create a PVC and attached to it.
  - Plus, in case of StatefulSet each Pod itself create a PVC so in case of Dynamic Provisioning, PV will get attached to the Pod automatically

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

    psql -U postgres
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
- 1. Because DB is a stateful app. And in Statefulset Pod has different roles to perform. Like in RDS. The first created Pod act as master where Read and Write is possible.
  - The next Pods which get created will only works as Replication and can do Read operations.
- 2. In some type of statefule set, there are master-slave architecture.
- 3. In some type of stateful set, there are election-pod type architecture.

**You should know how to answer:**
- What is the difference between a Deployment and a StatefulSet for running databases?
  - Deployment is created for stateless app, where all replicas of Pods are exactly same and user request doesnt have any difference when hitting the service.
  - StatefulSet, we need to maintain the order of creation, also the Pod should be ordered so user can request explicitly on the specific Pod, Along with that ordered pods are also required to persist the same data before and after deletion and recreation of Pod.
    - The pod which got recreated is created with same cardinal number so that the specific PVC can attached to it again to persist the same data.
  - Another difference is deployments replicas are attached to single PVC where every pod in stateful set has their own separate PVC which attached to separate PV. As the data is specific as per Pod.
  - Like master-slave arch, 1 read-write master and another read replicas arch.

- What happens to PVCs when you delete a StatefulSet?
  - The PVC remains attached with the PV and contains the data.
  - It reattach to same the Pod as the Pod is created with unique cardinal number and Pod is created with same cardinal number if recreated.

- Why does a StatefulSet scale up and down sequentially?
  - because every pod has some function to perform and every next pod sometime get dependent on previous pod.
  - This is the reason, the next pod is created only after the previous pod is ready

---

## Exercise 4 — Shared Storage with emptyDir and Multi-Container Pods

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
  - emptyDir is used when multiple containers inside a Pod needs to share the same data.
  - hostPath is the path where the data is stored and sync with mountPath defined inside the container.
  - PVC - it is not a storage, it is used to claim the storage. Instead of directly attaching the volume we can attach the PVC to a POD.
    - As in case of refefining the Path we just need to update the PV and no need to change the deployment / pod manifest.

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

**First — understand the two completely different reasons a PVC can be `Pending`:**

Pending reason
- **No volume available** 
- **WaitForFirstConsumer**


Check the `volumeBindingMode` on the StorageClass to understand which case you are in:
  ```bash
  kubectl get storageclass
  # NAME       PROVISIONER              RECLAIMPOLICY   VOLUMEBINDINGMODE      AGE
  # standard   rancher.io/local-path    Delete          WaitForFirstConsumer   ...
  ```

**Root cause — why your PV+PVC both bound even with a fake storageClassName:**
  K8s `storageClassName` is just a **matching label**, not a lookup into the StorageClass registry.  
  Static binding rules: K8s will bind a PV to a PVC if ALL of these match — `storageClassName`, `accessModes`, and capacity (PV ≥ PVC request). 

Diagnose:
  ```bash
  kubectl apply -f Exercises/Exercise-5/problem_1.yml
  kubectl get pvc problem-one-pvc -n team-alpha
  # STATUS: Pending
  
  kubectl describe pvc problem-one-pvc -n team-alpha
  # Events:
  #   Normal  FailedBinding  no PersistentVolume found for PVC ... waiting for a volume to be created
  #                                                            ^^ this means no volume available
  #   (compare: "waiting for first consumer" = WaitForFirstConsumer mode, NOT the same thing)
  ```

Fix (option A — create a matching PV):
  # STATUS: Bound  ← PV appeared, K8s matched and bound it (even though the SC resource doesn't exist)

Fix (option B — create a Pod and attach the PVC to it, if the VolueBindMode: WaitForFirstConsumer):

---

**Problem 2: Permission denied on mounted volume**
- Mount a `hostPath` PersistentVolume backed by a directory owned by `root` with group-exclusive write (`chmod 770, chown root:2000`).
- Pod runs as a non-root user (`runAsUser: 1000`) with a primary group that is NOT GID 2000 → Permission denied.
- Fix using `securityContext.fsGroup: 2000`.

**Root cause — why fsGroup did not fix `/root/` in your original attempt (two bugs):**

  **Bug 1 — wrong directory permissions:**  
  `/root/` has `700` (`drwx------`) permissions. When fsGroup chowns the group to 2000, the directory becomes `root:2000` but the permission bits are still `700` — the group field is `---` (zero access). Chowning the group is useless when the group permission bits are all zeroes.

  **Bug 2 — hostPath does NOT support automatic fsGroup chown:**  
  Kubernetes only performs the recursive `chown :fsGroup` on **managed volumes** (emptyDir, CSI-provisioned PVCs, etc.).  
  For `hostPath`, K8s skips the chown step entirely — the host filesystem permissions are used as-is.  
  What fsGroup **always** does (even for hostPath) is add the GID to the container's **supplemental groups**.  
  So for hostPath, the fix only works if the host directory is already owned by group `fsGroup` and has group-write bits.

**Setup — exec into the kind worker node and prepare the directory:**
  ```bash
  docker exec -it calico-lab-worker bash
  mkdir -p /opt/problem-data
  chown root:2000 /opt/problem-data    # group ownership = GID 2000
  chmod 770 /opt/problem-data          # owner=rwx, group=rwx, other=---
  exit
  # Verify: the directory is now root:2000 drwxrwx---
  ```

Diagnose (broken pod — no fsGroup):
  ```bash
  kubectl apply -f Exercises/Exercise-5/problem_2.yml
  kubectl logs problem-two-pod -n team-alpha
  # Running as: uid=1000 gid=3000 groups=3000
  # sh: can't create /mnt/data/file.txt: Permission denied
  # User 1000 with primary group 3000 → "other" on a 770 dir → --- → denied
  ```

Fix (apply after deleting the broken pod):
  ```bash
  kubectl delete pod problem-two-pod -n team-alpha
  
  # Apply problem-two-pod-fixed (defined in the same file)
  kubectl apply -f Exercises/Exercise-5/problem_2.yml
  kubectl logs problem-two-pod-fixed -n team-alpha
  # Running as: uid=1000 gid=3000 groups=3000,2000   ← fsGroup added 2000
  # Write succeeded!
  # Process is now a member of group 2000 → group has rwx on root:2000 770 dir → allowed
  ```
---

**Problem 3: RWO PVC — simulating single-node exclusive access**
- Demonstrate that a `ReadWriteOnce` volume can only be used from one node at a time.
- Use dynamic provisioning so the PV is physically tied to one node.
- Force two pods onto different nodes and observe the conflict.

**Setup**
  - As we are using KIND cluster with 2 node - worker and master.
  - First add the nodeSelector in one of the Pod and also add tolerations. So that the Pod will get scheduled on Control-Plane
  - Second, simply create the node, it will auto scheduled in worker node. As the other one is tainted.

**Diagnose**
  - As we are using `spec.hostPath` in PV, so there will be no conflict in case of RWO even if the Pods present in different Nodes.
  - As the volume path will be mounted in separate Nodes accordingly. So It will be like 2 same path on different Nodes, so there will be no conflict. But the Pods can not see each other data.

**Conflicting Stage**
  - The conflict arises if we use and Amazon EBS or similar in PV i.e. `spec.awsElasticBlockStore`
  - As now both Pods point to same storage. This will create conflict.

**Solution**
  - Scheduled all Pods which Points to specific storage on same Node (if appropriate).
    - Since RWO is per node, multiple pods on the same node can share the volume.
    - This works because the EBS volume is attached only once—to Node-1.
  - Use RWX storage (Recommended for shared data).
    - If multiple pods on different nodes need the same files, use a storage backend that supports ReadWriteMany (RWX).
    - Now all pods can read/write simultaneously.
  - Give each pod its own volume.
    - Use StatefuleSets.
      - This is the standard approach for databases.
      - Each pod gets its own PersistentVolumeClaim, which leads to different EBS
  - Wait for the volume to detach

---

**What the real error looks like in production (AWS EBS / Azure Disk / GCE PD):**

A cloud block disk is a **single physical device**. It can only be attached to one VM (node) at a time. When Pod 1 already has it attached on Node A and Pod 2 tries to start on Node B:
```
Warning  FailedAttachVolume  Multi-Attach error for volume "pvc-abc123"
         Volume is already exclusively attached to one node and can't be attached to another
```
Pod 2 is stuck in `ContainerCreating`. The cloud API rejects the second attach at the hardware level.

---

**Why your original attempt (manual hostPath PV) showed no error:**

`hostPath` resolves to the **local filesystem of whichever node the pod is running on**. The PV spec just says "give me `/var/tmp`" — it doesn't say "give me `/var/tmp` from a specific node". Each node has its own `/var/tmp`.

```
1 PV spec (path: /var/tmp)  +  1 PVC
        ↓
Pod 1 on control-plane  →  mounts /var/tmp FROM control-plane's disk
Pod 2 on worker         →  mounts /var/tmp FROM worker's disk
```

Same PV and PVC in K8s metadata. Completely separate storage on disk. No shared resource, no conflict. A manual `hostPath` PV has no nodeAffinity — it is a ghost volume that resolves differently on every node.

> Think of it like a key that opens the door of whatever house you're standing in front of — not a key to one specific house.

---

**Why dynamic provisioning (local-path) actually demonstrates the constraint:**

With `local-path-provisioner`, ONE PVC → ONE PV → ONE physical directory on ONE specific node:

```
Pod 1 scheduled on calico-lab-worker
→ local-path creates:  /opt/local-path-provisioner/pvc-abc123/  ON calico-lab-worker
→ PV has nodeAffinity: kubernetes.io/hostname In [calico-lab-worker]

PVC is now Bound to this PV. One volume. Physically on one node only.

Pod 2 must run on calico-lab-control-plane (nodeSelector)
→ Scheduler looks for a node satisfying BOTH:
    • pod-two's nodeSelector:  calico-lab-control-plane
    • PV's nodeAffinity:       calico-lab-worker
→ No such node exists → Pod 2 stuck: Pending
```

The error in kind is `volume node affinity conflict` (a scheduler-level block). In real cloud it's `Multi-Attach error` (a storage-driver-level block). The mechanism differs but the result is the same: **one RWO volume, one node, any other node is locked out.**

> **Two valid approaches to get the RWO constraint working:**
>
> **Option A — Static PV with nodeAffinity (you write it manually):**
> ```yaml
> apiVersion: v1
> kind: PersistentVolume
> metadata:
>   name: problem-three-pv
> spec:
>   capacity:
>     storage: 1Gi
>   accessModes: [ReadWriteOnce]
>   storageClassName: problem-three-storage
>   hostPath:
>     path: /var/tmp
>   nodeAffinity:                        # ← you must add this yourself
>     required:
>       nodeSelectorTerms:
>       - matchExpressions:
>         - key: kubernetes.io/hostname
>           operator: In
>           values: [calico-lab-worker]  # ← pins this PV to worker only
> ```
> Pod 1 on `calico-lab-worker` → mounts fine. Pod 2 on control-plane → `Pending` (node affinity conflict). Same result.  
> The problem_3.yml uses dynamic provisioning only because the provisioner adds nodeAffinity automatically — you don't have to remember it. If you write a static PV and forget nodeAffinity, you get the silent bug from your original attempt.
>
> **Option B — Dynamic provisioning (problem_3.yml, no manual PV):**  
> `local-path-provisioner` creates the PV and stamps `nodeAffinity` automatically when the first pod consumes the PVC.

---

Diagnose:
  ```bash
  # STEP 1: Check your node names
  kubectl get nodes
  # NAME                          STATUS   ROLES
  # calico-lab-control-plane      Ready    control-plane
  # calico-lab-worker             Ready    <none>
  
  # STEP 2: Apply the full file — PVC + pod-one + pod-two
  kubectl apply -f Exercises/Exercise-5/problem_3.yml
  
  # STEP 3: Wait for pod-one to be Running (this triggers PVC binding to worker node)
  kubectl get pod problem-three-pod-one -n team-alpha -w
  
  # STEP 4: Inspect the auto-created PV — confirm nodeAffinity is set to calico-lab-worker
  PV=$(kubectl get pvc problem-three-pvc -n team-alpha -o jsonpath='{.spec.volumeName}')
  kubectl describe pv $PV | grep -A8 "Node Affinity"
  # Required Terms:
  #   Term 0:  kubernetes.io/hostname in [calico-lab-worker]
  # This PV physically only exists on calico-lab-worker. Any pod on another node is locked out.
  
  # STEP 5: Check pod-two — it is stuck in Pending
  kubectl get pod problem-three-pod-two -n team-alpha
  # NAME                    READY   STATUS    RESTARTS
  # problem-three-pod-two   0/1     Pending   0
  
  kubectl describe pod problem-three-pod-two -n team-alpha
  # Events:
  #   Warning  FailedScheduling  0/2 nodes are available:
  #   1 node(s) had volume node affinity conflict.   ← kind equivalent of Multi-Attach error
  #   1 node(s) had untolerated taint {node-role.kubernetes.io/control-plane:}.
  ```

Fix (production patterns):
  ```bash
  # Option A — Use ReadWriteMany (RWX): requires a distributed filesystem (NFS, CephFS, AWS EFS)
  #            Multiple nodes can mount the same volume simultaneously
  # Option B — StatefulSet pattern: give each pod its own PVC (see Exercise 3)
  #            postgres-0 gets data-postgres-0, postgres-1 gets data-postgres-1
  # Option C — Keep all pods that share the volume on the same node (NodeAffinity on pod)
  ```

**You should know how to answer:**
- What kubectl commands do you run first when a pod is stuck in `ContainerCreating`?
  - kubectl describe pod <pod-name>
  - kubectl logs pod -p

- What is the difference between RWO, ROX, and RWX access modes?
  - RWO - ReadWriteOnce - it means Pod on same node can alter with the volume at a same time. It will be errorProne if the multiple Pods from different nodes are attached to same PVC
    - In case of hostPath it will not give error as the PV will be created on different nodes. So Pods in different nodes can still read and write but its not the same volume they are performingoperations on. 
      - They are different volume on different Node.
      - We can't create a scenario for RWO error with hostPath even we do Nodeaffinity on PV to make the PV on single Node only because if that the case, other Node simply wont find the volume in them. So that a error like pv not found or path not found not the RWO related error.
    - EBS, hostPath
  - ROX - ReadOnceMany - it means multiple pod on multiple Node can read the data at a same time
    - EBS
  - RWX - ReadWriteMany - It means multiple pod on multiple node can read as well as write the data at a same time.
    - EFS

- What does `fsGroup` do, and when do you need it?
  - ....

- Why can't you edit the `storageClassName` of an existing PVC?
  - Because storageClassName consist of configurations set for specific use, if we update it in existing PVC, the config might not adhere to it.

- RWO allows one node — does that mean two pods on the same node can both mount it?
  - Yes, 2 Pod on same node can mount and read/write data at a time.

---

## Exercise 6 — VolumeSnapshots (Backup Your PVCs) 

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

 ```bash
 # Install Velero (one-time, points to an S3 bucket)
 velero install --provider aws --bucket my-k8s-backups --backup-location-config region=us-east-1

 # Take a full namespace backup
 velero backup create team-alpha-backup --include-namespaces team-alpha

 # Restore into a different cluster or namespace
 velero restore create --from-backup team-alpha-backup
 ```
  - At companies: the platform/SRE team sets up Velero with scheduled nightly backups. Individual developers don't usually run it directly.


 **Your interview answer (memorize this):**
   - *"For a quick pre-migration rollback of a single database — VolumeSnapshot, because it's instant and storage-level. For full disaster recovery or moving between clusters — Velero, because it backs up both the PVC data and all the Kubernetes object definitions together, and stores everything in S3 so it survives cluster loss."*

---

## Completion Checklist

- [x] Create PVs manually and bind them with PVCs
- [x] Explain and demonstrate all three reclaim policies
- [x] Configure dynamic provisioning via StorageClass
- [x] Deploy a StatefulSet with persistent storage that survives pod restarts
- [x] Debug PVC pending and volume mount issues
- [ ] Take a VolumeSnapshot and restore data from it

---

## Interview Questions This Task Prepares You For

- "How would you run a database in Kubernetes? What are the trade-offs?"
  - We use the statefulset as DB are stateful application, where same data on specific pod needs to be persisted in case of pod recreation. and there are some other factors too.

- "What is the difference between a Deployment and a StatefulSet?"
  - I answered above.

- "Walk me through the storage provisioning flow in K8s."
  - We provide a PV or it is provided through Dynamic Provisioning.
  - PV is claimed by PVC based on labels and selector and the configuration we mentioned in Storage Class.
  - Then we attached the PVC to POd and mention the mountPath - the path where the data needs to by sync from the hostPath provided in PV. either local on nodes, or through block storage like EBS, and file system like EFS.

- "A pod is stuck in ContainerCreating — how do you debug it?"
  - Answered above. ques on line 551

- "What happens to data when a pod is deleted? How do you prevent data loss?"
  - No data is persisted in a PV but it depends on the Reclaim policy - data is deleted if policy is delete instead of retain.

- "How do you back up your database PVC in Kubernetes before a migration?"
  - 

---

## Mini Project — Persistent PostgreSQL for team-alpha

> Estimated time: 2 hours. Put this in GitHub under `k8s-practice/task-04/`.

**Scenario:** `team-alpha` wants to persist their application data. You need to deploy PostgreSQL with real persistent storage so data survives pod restarts and node rescheduling.

**Deliverables — all as YAML files:**

1. `postgres-secret.yaml` — A Secret containing `POSTGRES_PASSWORD` and `POSTGRES_DB`
  ```bash
      kubectl create secret generic postgres-secret -n team-alpha --from-literal=POSTGRES_PASSWORD=supersecretpassword --from-literal=POSTGRES_DB=testDB --dry-run=client -o yaml > postgres-secret.yml
  ```
2. `postgres-statefulset.yaml` — StatefulSet with:
   - 1 replica
   - Image: `postgres:15`
   - `volumeClaimTemplate` requesting 1Gi with `ReadWriteOnce`
   - Env vars sourced from the Secret
   - Readiness probe: `pg_isready` command (# Used first Time as tutorial)
     - With proper DB name and User name
3. `postgres-service.yaml` — Headless service (clusterIP: None) for stable DNS
  ```bash
    kubectl apply -f .
  ```
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
  
  ```bash
      kubectl run test-pod --image=postgres:15 --dry-run=client -o yaml > test-pod.yml
      
      kubectl exec -it test-pod -- sh

        getent hosts postgres-0.postgres-svc
  
        export PGPASSWORD="$POSTGRES_PASSWORD"
        psql -h postgres-svc -U postgres -d testDB

        CREATE TABLE users (id SERIAL PRIMARY KEY,name TEXT);
        INSERT INTO users (name) VALUES ('alice');
        INSERT INTO users (name) VALUES ('john');
        SELECT * FROM users;
  ```
5. Reconnect to postgres server and verify data
  ```bash
    kubectl exec -it postgres-0 -- sh

    psql -U postgres
    \c testDB
    SELECT * FROM users;
  ```

**Proof of completion:**
- Run the test pod — show it successfully inserted and queried data
- Delete the `postgres-0` pod manually — show it comes back with the same PVC
- Reconnect and show the data is still there
- `kubectl get pvc -n team-alpha` shows the bound volume
- Explain: what would happen to this PVC if you ran `kubectl delete statefulset postgres`?
  - Deleting the StatefulSet does not delete the PVCs.
  - The PVCs remain in the cluster and stay Bound to their PVs.
  - If you recreate the StatefulSet with the same name and volumeClaimTemplates, it can reuse those existing PVCs, so your PostgreSQL data is preserved.
  - But this is also depend of `persistentVolumeClaimRetentionPolicy`
- **VolumeSnapshot (Exercise 6):** Take a snapshot of the PVC while data is intact → delete the data row from inside postgres → restore the PVC from the snapshot → show the data is back. Run `kubectl get volumesnapshot -n team-alpha` to confirm the snapshot exists.

---

**Next: Task-05-RBAC-and-Security.md**