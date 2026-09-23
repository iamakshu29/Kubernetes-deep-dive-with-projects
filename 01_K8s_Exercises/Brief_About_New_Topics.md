# CONTEXT

- A kubeconfig has clusters, users, contexts, and current-context.
- A context selects which cluster and identity kubectl uses, and can also set a default namespace.
- Always run `kubectl config current-context` and check the namespace before changing resources.
- Context switching changes the target of kubectl; it does not move workloads between clusters.

# WORKLOAD RESILIENCE

## PDB (PodDisruptionBudget)

- Protects the minimum available replicas during voluntary disruptions such as node drain or planned maintenance.
- Use either `minAvailable` or `maxUnavailable`.
- It does not guara ntee protection from node crashes, kernel failures, or application crashes.
- A PDB must match the workload labels and should be compatible with the replica count.

## Pod anti-affinity and topology

- Anti-affinity prevents or discourages similar Pods from sharing a node or failure domain.
- `requiredDuringSchedulingIgnoredDuringExecution` is a hard rule and can leave Pods Pending.
- `preferredDuringSchedulingIgnoredDuringExecution` is a soft preference.
- Topology spread constraints distribute replicas by hostname, zone, or another topology label.

## Graceful shutdown and zero-downtime rolling updates

- Readiness must become false before the Pod stops accepting traffic.
- SIGTERM gives the application an opportunity to finish requests and close connections.
- A `preStop` hook can provide a short drain period; `terminationGracePeriodSeconds` must be long enough.
- Combine this with `maxUnavailable: 0`, a correct readiness probe, and sufficient capacity.

# NETWORKING

- Delete the previous cluster before creating the Calico-enabled cluster so old networking configuration does not confuse testing.
- For kind, use `kind get clusters`, then `kind delete cluster --name <old-cluster-name>`.
- Delete the Calico test cluster the same way when the exercise is complete: `kind delete cluster --name <calico-cluster-name>`.
- Confirm cleanup with `kind get clusters` and `kubectl config get-contexts`.

## Ingress: implementation/code focus

- An Ingress object only declares host/path rules; an Ingress controller implements them.
- The controller watches Ingress resources and configures its proxy, commonly NGINX.
- Verify `ingressClassName`, Service name, Service port, controller status, and controller logs.
- `pathType: Prefix` matches a path tree; `Exact` matches one path.
- NGINX rewrite annotations can change the path forwarded to the backend. Test both the public URL and the backend path.
- In a local kind setup, the reachable NGINX address may be the hostPort mapped when the cluster was created. Do not assume it is a cloud LoadBalancer IP.

## NetworkPolicy

- Policies select Pods by labels and control Ingress, Egress, or both.
- Begin with default deny, then explicitly allow required application paths and DNS.
- Allow CoreDNS on UDP/TCP 53 or name resolution will fail.
- NetworkPolicy enforcement depends on the CNI; a policy can be accepted by the API without being enforced by an unsupported CNI.

## CoreDNS

- CoreDNS provides Service and Pod name resolution inside the cluster.
- A normal Service resolves as `<service>.<namespace>.svc.cluster.local`.
- Debug from inside a Pod using `nslookup`, `dig`, or `getent hosts` when available.
- Check `kube-system` CoreDNS Pods, their logs, the Service, and the Pod `/etc/resolv.conf`.

## Certificates and TLS

- cert-manager automates certificate requests, Secret creation, and renewal.
- `Issuer` is namespace-scoped; `ClusterIssuer` is cluster-scoped.
- The Ingress normally terminates TLS using the Secret referenced in `spec.tls`.
- Debug issuer status, Certificate status, Secret creation, DNS, challenge resources, and Ingress events.

## Service types and external traffic

- ClusterIP is internal and is the default.
- NodePort exposes a port on every node.
- LoadBalancer needs a cloud integration or MetalLB; otherwise the external IP can remain Pending.
- ExternalName returns a DNS alias and does not select Pods or create normal Endpoints.
- `externalTrafficPolicy: Cluster` can distribute traffic across nodes; `Local` preserves the client IP but requires a local endpoint and can cause uneven traffic.

## Gateway API

- Gateway API is a richer successor direction to Ingress.
- `GatewayClass` describes the controller, `Gateway` represents the traffic entry point, and `HTTPRoute` describes application routing.
- It separates platform ownership of the Gateway from application ownership of Routes and supports more expressive routing.

# STORAGE

## StorageClass

- Defines the provisioner and parameters used for dynamic PV creation.
- A PVC can request a StorageClass explicitly or use the cluster default.
- Debug with `kubectl get storageclass`, `kubectl describe pvc`, and `kubectl get pv`.

## emptyDir

- Temporary storage created with the Pod and removed when the Pod is removed.
- Useful for scratch space or sharing files between containers in the same Pod.
- It is not a durable backup and does not survive Pod replacement.

## VolumeSnapshots and cloud storage

- A VolumeSnapshot is a storage-backend snapshot of a PVC, requiring a compatible CSI driver and snapshot controller.
- Cloud examples use the provider CSI driver and its snapshot capability; verify consistency requirements for databases.
- Test restore into a new PVC. A snapshot is not automatically a complete application or namespace backup.

## Velero

- Velero backs up Kubernetes resources and, with provider plugins, persistent volume data or snapshots.
- It is appropriate for namespace or application disaster recovery, while a VolumeSnapshot is focused on a volume.
- A backup is useful only after restore testing, including Secrets, configuration, RBAC, and storage dependencies.

# SECURITY

## ServiceAccount

- A ServiceAccount is a Kubernetes identity for a Pod, Job, controller, or CI/CD process.
- A human User normally comes from certificates or an external identity provider; Kubernetes does not maintain a normal user database.
- A Role or ClusterRole defines permissions; a RoleBinding or ClusterRoleBinding grants them to a ServiceAccount, User, or Group.
- Test permissions with `kubectl auth can-i`, and grant only the verbs and resources required.

## PSA and Kyverno

- Pod Security Admission provides built-in privileged, baseline, and restricted profiles with enforce, warn, and audit modes.
- Kyverno adds custom organization rules, such as approved image registries, required labels, non-root containers, or resource limits.
- PSA is a built-in baseline guardrail; Kyverno is a policy engine for richer custom validation and mutation.

# HELM

- This list has no separate additional topic, but Helm remains a new practical workflow: chart structure, values overrides, templates, releases, hooks, dependencies, and rollback.
- Always render with `helm template` and validate with `helm lint` before installation.

# ARGO CD

- No separate additional topic is listed here; revise Git as source of truth, Applications, auto-sync, self-healing, sync waves, hooks, App of Apps, and Rollouts.

# OBSERVABILITY

- No separate additional topic is listed here; revise the difference between metrics-server and Prometheus, PromQL, ServiceMonitor, Grafana dashboards, Alertmanager, and SLO-based alerts.

# REFERENCE RELATIONSHIPS TO REMEMBER

- Ingress -> Gateway API: Gateway API provides richer routing and clearer ownership boundaries.
- VolumeSnapshot -> Velero: a snapshot protects storage; Velero can coordinate broader application or namespace recovery.
- PSA -> Kyverno: PSA supplies built-in Pod security profiles; Kyverno adds custom policy logic.
- ServiceAccount -> User: ServiceAccounts are Kubernetes workload identities; Users are generally external human or automation identities.

# SHOULD TRY LATER

- Service mesh: Istio or Linkerd for traffic policy, mTLS, retries, telemetry, and progressive delivery.
- Multi-cluster and multi-region: federation patterns, disaster recovery, global traffic, and data replication.

LOWER PRIORITY FOR THIS CURRICULUM

- Keycloak and Active Directory integration can be studied later when identity-provider integration becomes necessary.