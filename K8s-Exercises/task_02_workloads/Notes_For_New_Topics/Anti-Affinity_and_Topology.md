# Kubernetes Notes: Pod Anti-Affinity & Topology Spread Constraints

## 1. Pod Anti-Affinity

### Purpose

Pod Anti-Affinity tells the scheduler:

> **"Do not place this Pod near other Pods matching these labels."**

It is mainly used to improve **High Availability (HA)** by spreading replicas across different nodes or zones.

---

## How it works

The scheduler looks for **existing Pods** that match the `labelSelector`.

Example:

```yaml
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
    - labelSelector:
        matchLabels:
          app: nginx
      topologyKey: kubernetes.io/hostname
```

The scheduler interprets this as:

* Find Pods with label:

  ```yaml
  app: nginx
  ```
* Do **not** place another matching Pod on the same node.

---

## Types

### 1. Required (Hard Rule)

```yaml
requiredDuringSchedulingIgnoredDuringExecution
```

* Rule **must** be satisfied.
* If impossible, Pod remains **Pending**.

Example:

* 2 Nodes
* 3 Replicas

Result:

```text
Node1   nginx-1
Node2   nginx-2
Pending nginx-3
```

---

### 2. Preferred (Soft Rule)

```yaml
preferredDuringSchedulingIgnoredDuringExecution
```

* Scheduler tries to satisfy the rule.
* If impossible, it schedules the Pod anyway.

Example:

```text
Node1   nginx-1 nginx-3
Node2   nginx-2
```

---

## Important Fields

### labelSelector

Selects the Pods to avoid.

```yaml
labelSelector:
  matchLabels:
    app: nginx
```

The scheduler checks for Pods matching these labels.

---

### topologyKey

Defines what "apart" means.

Common values:

```yaml
kubernetes.io/hostname
```

→ Different **Nodes**

```yaml
topology.kubernetes.io/zone
```

→ Different **Availability Zones**

---

## IgnoredDuringExecution

Example:

```yaml
requiredDuringSchedulingIgnoredDuringExecution
```

Meaning:

* Rule is checked **only while scheduling**.
* Once the Pod is running, Kubernetes **does not move or evict** it if cluster topology changes.

Example:

Initially:

```text
Node1   Pod1
Node2   Pod2
Node3   Pod3 Pod4
```

A fourth node is added.

Kubernetes **does not rebalance** existing Pods automatically.

Only newly created or rescheduled Pods consider the new node.

---

## Common Use Cases

* High Availability
* Avoid putting all replicas on one node
* Spread application replicas across failure domains

---

# 2. Topology Spread Constraints

## Purpose

Topology Spread Constraints tell Kubernetes:

> **"Keep my Pods evenly distributed across nodes or zones."**

Unlike Anti-Affinity, this focuses on **balanced distribution** instead of simply keeping Pods apart.

---

## Example

```yaml
topologySpreadConstraints:
- maxSkew: 1
  topologyKey: kubernetes.io/hostname
  whenUnsatisfiable: DoNotSchedule
  labelSelector:
    matchLabels:
      app: nginx
```

---

## Important Fields

### labelSelector

Pods counted while calculating the spread.

```yaml
labelSelector:
  matchLabels:
    app: nginx
```

---

### topologyKey

What should be balanced?

```yaml
kubernetes.io/hostname
```

→ Across Nodes

```yaml
topology.kubernetes.io/zone
```

→ Across Zones

---

### maxSkew

Maximum allowed difference between the busiest and least busy topology domain.

Example:

```yaml
maxSkew: 1
```

Allowed:

```text
Node1   3 Pods
Node2   2 Pods
Node3   2 Pods
```

Difference = 1 ✅

Not Allowed:

```text
Node1   4 Pods
Node2   1 Pod
Node3   1 Pod
```

Difference = 3 ❌

---

### whenUnsatisfiable

#### DoNotSchedule

```yaml
whenUnsatisfiable: DoNotSchedule
```

If the spread cannot be maintained:

* Pod stays Pending.

---

#### ScheduleAnyway

```yaml
whenUnsatisfiable: ScheduleAnyway
```

Scheduler tries to maintain balance but schedules the Pod even if perfect spreading isn't possible.

---

## Common Use Cases

* Even distribution across worker nodes
* Multi-zone deployments
* Large stateless applications
* Better fault tolerance

---

# Anti-Affinity vs Topology Spread Constraints

| Feature           | Pod Anti-Affinity                                 | Topology Spread Constraints                     |
| ----------------- | ------------------------------------------------- | ----------------------------------------------- |
| Goal              | Keep Pods apart                                   | Keep Pods evenly distributed                    |
| Decision Based On | Presence of matching Pods                         | Number of matching Pods in each topology domain |
| Distribution      | May not be balanced                               | Explicitly balanced                             |
| Hard Rule         | `requiredDuringSchedulingIgnoredDuringExecution`  | `whenUnsatisfiable: DoNotSchedule`              |
| Soft Rule         | `preferredDuringSchedulingIgnoredDuringExecution` | `whenUnsatisfiable: ScheduleAnyway`             |

---

# Example Comparison

### 6 Replicas, 3 Nodes

### Pod Anti-Affinity (Preferred)

Possible result:

```text
Node1   Pod1 Pod2 Pod3
Node2   Pod4 Pod5
Node3   Pod6
```

Scheduler only tries to separate Pods.

---

### Topology Spread Constraints

With:

```yaml
maxSkew: 1
```

Possible result:

```text
Node1   Pod1 Pod2
Node2   Pod3 Pod4
Node3   Pod5 Pod6
```

Scheduler actively maintains an even distribution.

---

# Quick Revision

### Pod Anti-Affinity

* Prevent Pods from running together.
* Uses labels of **other Pods**.
* Improves High Availability.
* Does not rebalance existing Pods.
* `required` = Hard rule.
* `preferred` = Soft rule.

---

### Topology Spread Constraints

* Evenly distribute Pods.
* Uses `maxSkew` to control balance.
* Supports nodes, zones, or any topology label.
* Better choice when balanced placement is the primary goal.
* Does not move already running Pods after scheduling.
