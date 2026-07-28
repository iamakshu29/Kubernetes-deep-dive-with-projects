# Kubernetes Notes: Pod Anti-Affinity & Topology Spread Constraints

# 1. Pod Anti-Affinity

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

Result: 1 Pod remains **Pending**.

---

### 2. Preferred (Soft Rule)

```yaml
preferredDuringSchedulingIgnoredDuringExecution
```

* Scheduler tries to satisfy the rule.
* If impossible, it schedules the Pod anyway.

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
  - Simply selects the pod labels

### topologyKey
  - The node label that defines the topology domains

Common values:
- For Different **Nodes** - `kubernetes.io/hostname`
- For Different **Availability Zones** - `topology.kubernetes.io/zone`

### maxSkew
  - The maximum allowed difference in the number of matching pods between eligible topology domains.

### whenUnsatisfiable

#### DoNotSchedule
If the spread cannot be maintained: Pod stays Pending.

#### ScheduleAnyway
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

Possible result: It is a possible outcome with `preferredDuringSchedulingIgnoredDuringExecution`

```text
Node1   Pod1 Pod2 Pod3
Node2   Pod4 Pod5
Node3   Pod6
```

Scheduler only tries to separate Pods, as anti-affinity does not guarantee even distribution.
If your goal is even distribution, use:
  - Use n Nodes for n Pods
  - Topology Spread Constraints

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
