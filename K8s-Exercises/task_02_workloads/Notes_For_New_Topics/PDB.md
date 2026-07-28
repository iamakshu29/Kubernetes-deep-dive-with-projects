# Kubernetes Notes: PodDisruptionBudget (PDB)

## What is a PodDisruptionBudget (PDB)?

A **PodDisruptionBudget (PDB)** limits the number of Pods that can be **voluntarily disrupted** at the same time.

Its purpose is to ensure that **enough application replicas remain available** during maintenance operations.

A PDB **does not create Pods** or **reschedule Pods**. It only controls whether a Pod **may be evicted**.

---

# Why is a PDB needed?

Suppose a Deployment has:

* 5 replicas
* All Pods are healthy

Without a PDB, draining a node could evict several Pods simultaneously, reducing application availability.

A PDB prevents too many Pods from being evicted at once.

---

# Voluntary vs Involuntary Disruptions

## Voluntary Disruptions (PDB applies)

These are disruptions initiated by Kubernetes administrators or cluster operations.

Examples:

* `kubectl drain`
* Cluster upgrades
* Node maintenance
* Cluster Autoscaler removing a node

PDBs are checked before these evictions.

---

## Involuntary Disruptions (PDB does NOT apply)

These happen unexpectedly.

Examples:

* Node crash
* Power failure
* Hardware failure
* Kernel panic
* Network partition

A PDB cannot prevent these events.

---

# How a PDB Works

Suppose you have:

* Deployment with 3 replicas

PDB -> `minAvailable: 2`

When the node is drained:

1. Kubernetes evicts one Pod.
2. The Deployment creates a replacement Pod.
3. As long as **2 Pods remain available**, further evictions are allowed.
4. If evicting another Pod would reduce availability below 2, Kubernetes blocks the eviction.

---

# PDB Manifest

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: nginx-pdb
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: nginx
```

The selector identifies which Pods the PDB protects.

---

# Two Ways to Configure a PDB

## 1. minAvailable

Specifies the minimum number of Pods that must remain available.

Example: Deployment with 3 Replicas

```yaml
minAvailable: 2

 # Allowed:
Available Pods = 3 -> Evict one -> Available Pods = 2

 # Not Allowed:
Available Pods = 2 -> Evict another -> Available Pods = 1 ❌
```

---

## 2. maxUnavailable

Specifies the maximum number of Pods that may be unavailable.

Example: Deployment with 5 Replicas

PDB -> `maxUnavailable: 1`

Maximum one Pod may be unavailable at any time.

---

### Example: Single Worker Kind Cluster

Cluster:
  - Control Plane (NoSchedule taint)
  - Worker

Deployment with 3 Replicas

PDB -> `minAvailable: 2`

Result: Drain the worker node make 1 Pod remain in Pending State

Why?
* Worker is cordoned.
* Control-plane node has a `NoSchedule` taint.
* Replacement Pod cannot be scheduled.
* Available Pods = 2.
* PDB prevents another eviction.

Drain remains blocked.

---

## PDB Does NOT

* Create Pods
* Schedule Pods
* Move Pods
* Balance Pods across nodes

Those responsibilities belong to:

* Deployment / StatefulSet
* ReplicaSet
* Scheduler

The PDB only says:

> "Is this eviction allowed?"

---

## Does a PDB Work with Standalone Pods?

Technically: **Yes, it can**
Practically: **Usually no**

Because there is no Deployment or StatefulSet to create a replacement Pod.

---

## Use PDBs with:

* Deployments
* StatefulSets
* ReplicaSets

Avoid using them with standalone Pods unless you have a specific reason.

---

### Common Commands

```bash
 # Create
kubectl create pdb nginx-pdb -n team-alpha --selector=app=nginx --min-available=2 --dry-run=client -o yaml > nginx_PDB.yml
kubectl apply -f nginx_PDB.yml

 # View
kubectl get pdb

 # Describe
kubectl describe pdb nginx-pdb

 # Delete
kubectl delete pdb nginx-pdb
```

---

### Common Interview Questions

1. Does a PDB prevent node failures?
  - No, It only protects against **voluntary disruptions**.

---

2. Does a PDB create replacement Pods?
  - No, The Deployment or StatefulSet creates replacement Pods.

---

3. Does a PDB affect `kubectl delete pod`?
  - Not directly, Deleting a Pod bypasses the Eviction API.
  - Commands like `kubectl drain` use the Eviction API and therefore respect the PDB.

---

4. Can a PDB protect a DaemonSet?
  - Generally no, DaemonSet Pods are ignored by `kubectl drain` unless the `--ignore-daemonsets` behavior is changed.
  - PDBs are primarily intended for replicated application workloads.

---

# Quick Revision

* PDB = **PodDisruptionBudget**
* Protects against **voluntary disruptions**
* Does **not** protect against node crashes
* Uses the **Eviction API**
* Does **not** create or schedule Pods
* Works best with Deployments and StatefulSets
* `minAvailable` = Minimum Pods that must stay available
* `maxUnavailable` = Maximum Pods allowed to be unavailable
* Blocks evictions that would violate the budget
* `kubectl drain` respects PDBs
* Existing Pods are not moved automatically; PDB only decides whether an eviction is allowed
