# Kubernetes Revision Guide

A fast revision of the complete K8s learning workspace. Use this before opening the detailed task notes or exercises.

## How to Use This Guide

- First pass: read the mental models and the New Topics sections.
- Second pass: run the command checklist against a live cluster.
- Third pass: answer the self-check questions without looking at the answers.
- When a topic still feels unclear, open the linked task guide, exercise, or notes file.

The goal is not to memorize every command. The goal is to know what Kubernetes is responsible for, which object controls it, and how to prove what is happening.

## 1. Kubernetes Mental Model

Kubernetes is a declarative control-loop system:

1. You submit desired state through the API server.
2. The API server authenticates and authorizes the request, then persists state in etcd.
3. Controllers compare desired state with actual state.
4. Controllers create or change lower-level resources.
5. The kubelet and other agents make the node match the desired state.
6. Status and events show the result.

Important control-plane components:

- API server: front door for all cluster operations.
- etcd: strongly consistent key-value store for cluster state; back it up.
- Scheduler: chooses a suitable node for unscheduled Pods.
- Controller manager: runs reconciliation loops such as Deployment and Node controllers.
- Cloud controller manager: integrates cloud load balancers, routes, and nodes.

Important node components:

- kubelet: ensures Pods assigned to the node are running.
- container runtime: runs containers.
- kube-proxy or the replacement dataplane: implements Service networking rules.
- CNI plugin: provides Pod networking and may enforce NetworkPolicies.

A Pod is the smallest deployable unit, but normally you manage Pods through Deployments, StatefulSets, DaemonSets, Jobs, or CronJobs.

## 2. Object Selection: Which Resource Do I Need?

| Need | Resource | Key idea |
|---|---|---|
| Run one or more stateless replicas | Deployment | Manages ReplicaSets and rolling updates |
| Stable identity and storage | StatefulSet | Ordered Pods, stable names, volumeClaimTemplates |
| One Pod per node | DaemonSet | Agents such as logging or node monitoring |
| One-time work | Job | Retries until completion or failure |
| Scheduled work | CronJob | Creates Jobs on a schedule |
| Stable network endpoint | Service | Selects Pods using labels |
| External HTTP routing | Ingress | Needs an Ingress controller |
| Persistent data request | PVC | Claims storage supplied by a PV/StorageClass |
| Permissions | Role/ClusterRole + Binding | Grants verbs on resources |
| Policy enforcement | PSA/Kyverno | Admission-time security and governance |
| Package and template deployment | Helm chart | One chart, multiple values files |
| Git-driven delivery | Argo CD Application | Git is the desired-state source |

Labels identify objects. Selectors connect objects. A Service with the wrong selector can exist perfectly while having zero endpoints.

## 3. Cluster Setup and Contexts

Use the setup material in `01_K8s_Exercises/task_00_Setup/` to choose a kind cluster. A single node is enough for basic objects; multiple nodes are needed to observe spreading, drains, and failure domains. NetworkPolicy exercises need a policy-enforcing CNI such as Calico or Cilium; default kindnet should not be treated as sufficient enforcement.

A kubeconfig contains:

- clusters: API server endpoints and certificate information.
- users: credentials or authentication settings.
- contexts: a named combination of cluster, user, and namespace.
- current-context: the context used by kubectl when no context is specified.

Useful commands:

```bash
kubectl config get-contexts
kubectl config current-context
kubectl config use-context <context>
kubectl config set-context <context> --namespace=<namespace>
kubectl cluster-info
kubectl get nodes -o wide
```

Always confirm context and namespace before destructive commands.

## 4. Namespaces, Multi-Tenancy, and Admission

Namespaces provide a logical boundary, not a complete security boundary. Safe team separation usually combines:

- Namespace: ownership and naming boundary.
- ResourceQuota: caps total CPU, memory, Pods, PVCs, and other resources.
- LimitRange: supplies or enforces per-container and per-Pod requests/limits.
- RBAC: controls who can perform which API actions.
- NetworkPolicy: controls Pod traffic.
- PSA and securityContext: controls workload security posture.

Pod Security Admission profiles:

- privileged: broadest permissions; use only when justified.
- baseline: blocks common privilege escalation patterns.
- restricted: strongest built-in profile; expects non-root and safer defaults.

PSA modes:

- enforce: reject non-compliant workloads.
- warn: accept but warn the user.
- audit: accept but record an audit annotation.

Typical namespace labels use `pod-security.kubernetes.io/<mode>: <profile>`.

## 5. Workloads and Application Lifecycle

### Deployments and Rollouts

A Deployment manages a ReplicaSet, which manages replacement Pods. Prefer Deployments over directly creating long-lived Pods.

Production rollout essentials:

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 1
    maxUnavailable: 0
minReadySeconds: 10
```

- `maxSurge`: temporary extra capacity during an update.
- `maxUnavailable`: capacity allowed to be unavailable.
- `minReadySeconds`: how long a Pod must stay ready before being considered available.
- `revisionHistoryLimit`: controls old ReplicaSets retained for rollback.

Commands:

```bash
kubectl rollout status deployment/<name>
kubectl rollout history deployment/<name>
kubectl rollout undo deployment/<name>
kubectl rollout pause deployment/<name>
kubectl rollout resume deployment/<name>
kubectl scale deployment/<name> --replicas=3
```

### Configuration and Secrets

- ConfigMap: non-sensitive configuration.
- Secret: sensitive-looking data, but base64 is encoding, not encryption.
- Use environment variables or mounted files according to application needs.
- Do not commit plaintext secrets to Git. Prefer an external secret manager or External Secrets Operator; protect etcd with encryption at rest.

### Health Probes

- Startup probe: gives slow-starting applications time to initialize; delays liveness/readiness checks.
- Readiness probe: controls whether a Pod receives traffic.
- Liveness probe: restarts a stuck container.

A bad readiness probe causes no traffic. A bad liveness probe causes restart loops. Do not use liveness as a simple dependency check.

### Requests, Limits, and QoS

- Requests influence scheduling and HPA utilization calculations.
- Limits cap container usage; memory over the limit commonly results in OOMKilled.
- Guaranteed: requests equal limits for CPU and memory.
- Burstable: some requests/limits exist but are not all equal.
- BestEffort: no requests or limits.

### Autoscaling and Availability

HPA scales a workload from observed metrics, commonly CPU or memory utilization relative to requests. It needs metrics-server for resource metrics. Custom metrics require a metrics adapter, often Prometheus-backed.

PDB protects against voluntary disruptions such as `kubectl drain`, not every involuntary failure. Use either `minAvailable` or `maxUnavailable`, and ensure the policy is compatible with the replica count.

Anti-affinity and topology spread improve failure tolerance:

- `requiredDuringSchedulingIgnoredDuringExecution`: hard placement rule; may leave Pods Pending.
- `preferredDuringSchedulingIgnoredDuringExecution`: scoring preference; more flexible.
- topology spread can distribute replicas by hostname, zone, or another topology label.

### Graceful Shutdown and Zero-Downtime Updates

During termination, Kubernetes sends SIGTERM and waits for `terminationGracePeriodSeconds` before SIGKILL. A `preStop` hook can allow connection draining, but the application must also stop accepting new work and finish existing requests.

The practical combination is:

- readiness probe that becomes false during shutdown,
- `preStop` hook when needed,
- sufficient `terminationGracePeriodSeconds`,
- rolling update with `maxUnavailable: 0`,
- application-aware SIGTERM handling.

### StatefulSets, DaemonSets, Jobs

StatefulSets provide stable names such as `db-0`, ordered behavior, and persistent claims. They normally use a headless Service. DaemonSets run one copy per eligible node. Jobs complete work; CronJobs create Jobs on a schedule and need concurrency, history, and failure policies reviewed.

## 6. Networking

### Services and DNS

Service types:

- ClusterIP: internal virtual IP; default.
- NodePort: exposes a port on each node.
- LoadBalancer: asks a cloud or MetalLB integration for an external address.
- ExternalName: DNS alias, not a normal proxying Service.
- Headless (`clusterIP: None`): returns Pod addresses directly; common with StatefulSets.

CoreDNS resolves names such as:

```text
<service>.<namespace>.svc.cluster.local
```

Inside the same namespace, the short Service name usually works. Test the actual path from a Pod, not only from your laptop.

### Ingress

Ingress is an HTTP/HTTPS routing object. An Ingress controller is required to implement it. Review:

- host routing,
- path routing,
- `pathType`: Exact, Prefix, or controller-specific behavior,
- TLS secret and TLS termination,
- rewrite annotations,
- HTTP-to-HTTPS redirect,
- controller logs and exposed address.

Gateway API is the newer, more expressive direction, separating Gateway ownership from HTTPRoute ownership.

### NetworkPolicy

Without a policy selecting a Pod, traffic is generally allowed. Once a Pod is selected by an Ingress or Egress policy, that direction becomes restricted to allowed rules.

A zero-trust starting sequence:

1. Default deny Ingress and Egress.
2. Allow DNS egress to CoreDNS on UDP/TCP 53.
3. Allow required frontend-to-API, API-to-database, and ingress-controller paths.
4. Allow required external egress explicitly.
5. Test from inside the cluster.

NetworkPolicy enforcement depends on the CNI. A manifest can apply successfully while having no security effect if the CNI does not enforce it.

### TLS and cert-manager

cert-manager automates certificate issuance and renewal through CRDs such as `Issuer`, `ClusterIssuer`, and `Certificate`. The normal flow is:

1. Define an issuer and its ACME or internal CA configuration.
2. Request a Certificate for a DNS name.
3. cert-manager stores the resulting key and certificate in a Secret.
4. Ingress references the Secret and terminates TLS.
5. cert-manager renews before expiry.

Verify DNS, issuer status, HTTP-01/DNS-01 reachability, Secret creation, and Ingress events.

## 7. Storage

Storage chain:

```text
Pod -> PVC -> PV -> StorageClass/provisioner -> backing storage
```

- PV: actual cluster storage resource.
- PVC: workload request for storage.
- StorageClass: dynamic provisioning policy and provisioner.
- `volumeClaimTemplates`: per-Pod claims generated by a StatefulSet.

Access modes:

- ReadWriteOnce: read-write from one node.
- ReadOnlyMany: read-only from many nodes.
- ReadWriteMany: read-write from many nodes, if the backend supports it.

Reclaim policies:

- Retain: preserve storage/data for manual recovery and cleanup.
- Delete: delete the provisioned storage when the claim is removed.
- Recycle: deprecated.

`emptyDir` is temporary and tied to the Pod lifecycle. `hostPath` exposes node storage and is mainly for development or controlled node-local use. VolumeSnapshots are storage-level snapshots; namespace-wide disaster recovery usually needs a tool such as Velero plus a tested restore process.

Storage debugging:

```bash
kubectl get pvc,pv
kubectl describe pvc <claim>
kubectl get storageclass
kubectl describe pod <pod>
```

## 8. RBAC and Workload Security

Authentication answers “who are you?” Authorization answers “what may you do?” Kubernetes does not maintain a normal human-user database; users commonly come from certificates or OIDC.

RBAC pieces:

- Role: namespace-scoped rules.
- ClusterRole: cluster-scoped rules or reusable rules bound into a namespace.
- RoleBinding: grants a Role or ClusterRole in one namespace.
- ClusterRoleBinding: grants a ClusterRole cluster-wide.
- ServiceAccount: identity used by Pods and automation.

Use least privilege: narrow namespaces, resources, and verbs. Avoid giving `*` permissions or broad Secret access. Test with:

```bash
kubectl auth can-i get pods -n <namespace> --as=<user>
kubectl auth can-i patch deployments -n <namespace> --as=system:serviceaccount:<namespace>:<sa>
```

Useful securityContext settings include `runAsNonRoot`, a non-zero `runAsUser`, `allowPrivilegeEscalation: false`, dropped Linux capabilities, `readOnlyRootFilesystem`, and a suitable seccomp profile. PSA provides baseline enforcement; Kyverno adds organization-specific rules such as approved registries, required labels, or required resource limits.

## 9. Helm

A chart normally contains:

- `Chart.yaml`: chart metadata and version.
- `values.yaml`: defaults.
- `templates/`: parameterized Kubernetes manifests.
- `charts/`: dependencies.

Values precedence is generally defaults, then files supplied with `-f`, then `--set` overrides. Use one chart with environment-specific values files rather than copying complete manifests.

```bash
helm lint ./chart
helm template <release> ./chart -f values-prod.yaml
helm upgrade --install <release> ./chart -n <namespace> --create-namespace -f values-prod.yaml --set image.tag=<immutable-tag>
helm list -A
helm history <release> -n <namespace>
helm rollback <release> <revision> -n <namespace>
helm uninstall <release> -n <namespace>
```

Know conditionals, ranges, named templates, quoting, dependencies, hooks, and the difference between chart version and application image version. Render manifests before applying them.

## 10. Argo CD and GitOps

GitOps uses Git as the desired-state source. CI builds and publishes an image; the GitOps repository changes the image reference; Argo CD pulls and reconciles the cluster.

Argo CD concepts:

- Application: source, destination, project, and sync policy.
- Auto-sync: reconcile automatically.
- Self-heal: correct drift made directly in the cluster.
- Sync waves: order resources.
- Hooks: pre-sync, sync, and post-sync actions.
- App of Apps: one root Application manages many Applications.
- ApplicationSet: generates Applications from a template.
- Argo Rollouts: canary or blue-green delivery with analysis and promotion.

Push-based CD gives CI direct cluster credentials. Pull-based CD keeps reconciliation inside the cluster and makes Git review and rollback central: rollback is commonly a Git revert.

## 11. Observability

The three pillars are metrics, logs, and traces. This workspace focuses most deeply on metrics and dashboards.

- metrics-server: current CPU/memory used by HPA and `kubectl top`.
- Prometheus: historical time-series collection, PromQL, rules, and scraping.
- kube-state-metrics: object state such as Deployment replicas and Pod phases.
- Grafana: dashboards and visualization.
- Alertmanager: groups, routes, silences, and notifications.
- ServiceMonitor: Prometheus Operator object describing scrape targets.

Metric types:

- Counter: only increases; query changes with `rate()` or `increase()`.
- Gauge: current value that rises and falls.
- Histogram: buckets for distributions such as latency.
- Summary: client-side quantiles and counts.

PromQL building blocks:

```promql
up
rate(http_requests_total[5m])
sum by (namespace) (rate(container_cpu_usage_seconds_total[5m]))
histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket[5m])))
```

Prefer alerts tied to user-facing SLOs: error rate, latency, and availability. CPU and memory are useful diagnostic signals but are not automatically user impact.

## 12. Troubleshooting Framework

Use this order:

1. Confirm context, namespace, and the exact symptom.
2. Check object status and events.
3. Check scheduling and node health.
4. Check container state and logs.
5. Check selectors, endpoints, DNS, and policy.
6. Check storage, credentials, and external dependencies.
7. Reproduce from inside the cluster.

Core commands:

```bash
kubectl get pods -A -o wide
kubectl describe pod <pod>
kubectl logs <pod> -c <container> --previous
kubectl exec -it <pod> -- /bin/sh
kubectl get events -A --sort-by='.lastTimestamp'
kubectl get endpoints <service>
kubectl get endpointslices
kubectl top nodes
kubectl top pods -A --sort-by=memory
kubectl get nodes
kubectl describe node <node>
```

Common symptoms:

- Pending: insufficient resources, selectors/affinity, PVC, taints, admission, or image issues.
- CrashLoopBackOff: application error, bad configuration, failed liveness, or missing dependency.
- ImagePullBackOff: tag, registry access, imagePullSecret, or network problem.
- Service unreachable: selector mismatch, empty endpoints, wrong port/targetPort, DNS, or NetworkPolicy.
- Node NotReady: kubelet, runtime, disk/memory pressure, certificates, or network.
- HPA not scaling: metrics-server/custom adapter unavailable, missing requests, wrong target, or insufficient workload.
- LoadBalancer Pending: no cloud integration or MetalLB on a local cluster.

Node operations:

```bash
kubectl cordon <node>
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
kubectl uncordon <node>
```

`cordon` prevents new scheduling. `drain` evicts workloads and respects disruption rules. Avoid force deletion in production unless you understand the data and availability consequences. For kubeadm control planes, monitor certificate expiry and maintain tested etcd backups.

## 13. Capstone Architecture Checklist

The Online Boutique capstone combines the curriculum:

- namespaces, quotas, LimitRanges, and RBAC,
- multiple microservice Deployments,
- readiness/liveness probes and resource requests/limits,
- anti-affinity or topology spreading,
- frontend Ingress and TLS,
- default-deny NetworkPolicies with explicit service paths,
- Redis StatefulSet and persistent storage,
- HPA and load generation,
- Helm packaging and environment values,
- Prometheus/Grafana observability,
- Argo CD GitOps,
- optional service mesh exploration.

Review the capstone by layer instead of trying to understand every manifest at once: platform foundation, workloads, network, data, scaling, packaging, observability, then delivery.

## 14. High-Value Self-Check Questions

1. Why is a Deployment better than a bare Pod for an application?
2. What is the difference between readiness and liveness?
3. Why does HPA usually need resource requests?
4. What does a PDB protect, and what does it not protect?
5. Why can strict anti-affinity leave replicas Pending?
6. Why must DNS be allowed after a default-deny egress policy?
7. What is the difference between a Service selector and an Ingress rule?
8. What happens to data under Retain versus Delete reclaim policy?
9. Why is base64 in a Secret not encryption?
10. What is the difference between a RoleBinding and ClusterRoleBinding?
11. What does Helm solve that raw YAML duplication does not?
12. Why is Argo CD pull-based GitOps safer than giving CI cluster-admin credentials?
13. How are metrics-server and Prometheus different?
14. What is the first command you use when a Service has no traffic?
15. What evidence distinguishes a scheduling problem from an application crash?

## 15. Recommended Revision Timing

### First Complete Revision

- Quick scan of this guide: 45-60 minutes.
- Run command and manifest checks on a live cluster: 60-90 minutes.
- Revisit new-topic notes and weak areas: 2-3 hours.
- Troubleshooting and capstone architecture review: 60-90 minutes.

Practical total: **5-7 focused hours** for a useful first revision. A very quick reading-only pass is possible in **90 minutes**, but it will not replace hands-on recall.

### Repeatable Revision Cycle

- Daily, after study: 10 minutes of self-check questions.
- Weekly: 45-60 minutes covering one phase and its commands.
- Monthly: 2-3 hours running the core checklist and one failure scenario.
- Before interviews or a project: 3-4 hours, with extra focus on troubleshooting, networking, RBAC, Helm, GitOps, and observability.

Yes, repeating this revision is relevant. Spaced repetition turns commands and object relationships into retrieval skills, while repeated troubleshooting exposes gaps that passive rereading hides. Do not repeat it identically every time: first recall from memory, then verify with commands, then change one variable in a lab and explain the observed behavior.

## 16. Where to Go Deeper

Use the detailed files when this guide identifies a weak area:

- Context: `01_K8s_Exercises/task_01_Namespace_and_Context/Notes_for_New_Topics/Context.md`
- Workload resilience: `01_K8s_Exercises/task_02_workloads/Notes_For_New_Topics/`
- Ingress, policies, and TLS: `01_K8s_Exercises/task_03_Networking_and_Ingress/Notes_For_New_Topics/`
- Storage: `01_K8s_Exercises/task_03_Networking_and_Ingress/task_04_storage/`
- PSA: `01_K8s_Exercises/task_05_RBAC_and_Security/Notes_For_New_Topics/PSA.md`
- Helm: `01_K8s_Exercises/task_06_Helm/Notes_For_New_Topics/helm.md`
- Prometheus and Grafana: `01_K8s_Exercises/task_08_Observability/Notes/`
- Command reference: `commands.md`
- Full project integration: `01_K8s_Exercises/task_10_Project/`
