# Kubernetes Team Setup

## Overview

This setup creates an isolated Kubernetes environment for two development teams (`team-alpha` and `team-beta`) within a single cluster. It includes namespaces, resource quotas, limit ranges, and a helper script to simplify namespace switching.

### 1. Namespaces

Two namespaces (`team-alpha` and `team-beta`) are created with team labels.

**Why?**

* Namespaces provide logical isolation between teams while sharing the same Kubernetes cluster.
* They make it easier to organize resources and apply policies such as ResourceQuotas and LimitRanges on a per-team basis.

### 2. ResourceQuota

A `ResourceQuota` is applied to each namespace.

* **team-alpha:** Maximum 8 Pods, 2 CPU, 4Gi Memory
* **team-beta:** Maximum 6 Pods, 1 CPU, 2Gi Memory

**Why?**

* Prevents one team from consuming excessive cluster resources.
* Avoids the "noisy neighbor" problem, where one namespace can impact workloads running in other namespaces.
* Ensures fair resource allocation across teams.

### 3. LimitRange

A `LimitRange` is configured in each namespace with:

* Default CPU request: **100m**
* Default CPU limit: **500m**
* Default Memory request: **128Mi**
* Default Memory limit: **256Mi**
* Minimum CPU: **50m**
* Maximum CPU: **1**

**Why?**

* Automatically assigns default resource requests and limits to Pods when developers forget to specify them.
* Prevents Pods from consuming unlimited CPU or memory.
* Encourages consistent resource usage and improves cluster stability.

### 4. switch-context.sh

A shell script is provided to switch the current kubectl context to a team's namespace.

**Why?**

* Eliminates the need to specify `-n <namespace>` with every `kubectl` command.
* Reduces the chance of deploying resources into the wrong namespace.
* Improves developer productivity by quickly switching between team environments.

## Summary

This setup demonstrates Kubernetes multi-tenancy best practices by combining:

* Namespace-based isolation
* Resource quotas for fair resource allocation
* Limit ranges for enforcing sensible defaults
* A helper script for easier namespace management
