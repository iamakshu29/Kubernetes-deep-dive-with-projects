# Task 05 — RBAC & Security: Who Can Do What in the Cluster

> Real-world relevance: In a company cluster, not everyone should be able to delete
> production deployments. RBAC is how you enforce that — and a misconfigured RBAC
> is one of the most common K8s security incidents.

> **Cluster needed:** Any single-node cluster. RBAC is cluster-wide — node count doesn't matter.
> - **Use:** `kind create cluster` (no config file needed) or Killercoda.
> - **Browser-based:** Killercoda works perfectly for all RBAC exercises.
> - No special add-ons required.
> - If doing the Secrets audit (Exercise 5 — etcd encryption check): kind or Oracle Free Tier — you need direct shell access to the control-plane node.

---

## What You Will Learn

- How K8s authentication and authorisation works
- Roles, ClusterRoles, RoleBindings, ClusterRoleBindings
- ServiceAccounts — identity for pods, not humans
- Least-privilege principle applied to K8s
- Pod security — what a pod is allowed to do at the OS level
- Secrets handling — why the default is insecure and what you do about it

---

## Background — Read Before Starting

K8s does not manage users directly. It trusts external identity (certificates, OIDC tokens). But it DOES manage what those identities are allowed to do — that is RBAC.

Two axes:
```
WHO (Subject)      → User, Group, or ServiceAccount
CAN DO WHAT (Verb) → get, list, create, update, patch, delete, watch
ON WHAT (Resource) → pods, deployments, secrets, configmaps, etc.
```

At a company, RBAC controls:
- Developers can deploy to `dev` namespace but not `production`
- CI/CD pipelines (ServiceAccounts) can update Deployments but not delete Secrets
- On-call engineers can read logs but not modify configs

## Exercise 1 — Role and RoleBinding (Namespace Scoped)

**Scenario:** A developer on `team-alpha` should be able to view pods and logs but NOT delete anything.

**Your task:**
1. Create a Role named `alpha-dev-readonly` in namespace `team-alpha` that allows:
   - `get`, `list`, `watch` on `pods`
   - `get` on `pods/log`
   - `get`, `list` on `deployments` and `services`
2. Create a RoleBinding that binds `alpha-dev-readonly` to a user named `dev-alice`
3. Test it: simulate the user with `--as=dev-alice`
   - `kubectl get pods -n team-alpha --as=dev-alice` → should work
   - `kubectl delete pod <pod> -n team-alpha --as=dev-alice` → should be forbidden
4. Create another Role `alpha-dev-write` that also allows `create`, `update`, `patch` on `deployments`
5. Bind it to a group `alpha-leads` — bind `dev-alice` to this group (add a second RoleBinding)



**You should know how to answer:**
- What is the difference between a Role and a ClusterRole?
- Can you use a ClusterRole inside a specific namespace?
---

## Exercise 2 — ClusterRole and ClusterRoleBinding

**Scenario:** The monitoring team needs to read metrics from ALL namespaces — namespace-scoped Roles won't work.

**Your task:**
1. Create a ClusterRole `monitoring-reader` that allows:
   - `get`, `list`, `watch` on `pods`, `nodes`, `services`, `endpoints`
   - `get` on `pods/log`
2. Create a ClusterRoleBinding that binds this role to ServiceAccount `prometheus` in namespace `monitoring`
3. Verify with `--as=system:serviceaccount:monitoring:prometheus` that the SA can list pods in `team-alpha` in any namespace.
4. Verify it CANNOT create or delete anything in any namespace.

**You should know how to answer:**
- What built-in ClusterRoles exist in K8s that you should know about? (`cluster-admin`, `view`, `edit`)
- Why is binding `cluster-admin` to a CI/CD pipeline dangerous?

---

## Exercise 3 — ServiceAccounts for Applications

**Scenario:** Your CI/CD pipeline (running as a pod) needs to update Deployment images in `team-alpha`.

**Your task:**
1. Create a ServiceAccount `cicd-deployer` in `team-alpha`.
2. Create a Role that allows `get`, `list`, `update`, `patch` on `deployments` only
3. Bind the role to the `cicd-deployer` ServiceAccount
4. Verify all three
5. Deploy a deployment whose pods run with the `cicd-deployer` SA (not the default SA)
> `--as=cicd-deployer` is impersonation (testing only) — it does NOT make the pod use that SA. You set the SA inside the pod spec.
6. From inside that pod, use the mounted SA token to call the K8s API:
7. Try to list Secrets with the same token — verify it is forbidden
   ```bash
       # Still inside the same exec session
       TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
       curl -k -H "Authorization: Bearer $TOKEN" \
         https://kubernetes.default.svc/api/v1/namespaces/team-alpha/secrets
       # Expected: {"kind":"Status","code":403,"reason":"Forbidden",...}
       # The SA's Role only covers deployments — secrets are not in it, so RBAC denies.
   ```

**Dig deeper:**
- Disable auto-mounting of the default SA token on a pod: `automountServiceAccountToken: false` : add under `spec.template.spec` (default is true)
- Explain why you should do this for pods that don't need API access
  - **Why:** Every pod gets an authenticated K8s identity by default because of a default SA. If your pod is a web server that never calls the K8s API, that mounted token is pure attack surface — an attacker who exploits the pod can read the token and use it to probe the API server. Disabling the mount removes that vector entirely.
  - **What changes by making it false:** The entire `/var/run/secrets/kubernetes.io/` directory is not created inside the container — no token, no CA cert, no namespace file. Verified with `ls /var/run/secrets/` → `No such file or directory`.
  - **Default value:** `true` on the ServiceAccount object. Pod-level field is unset by default (inherits from SA).
  - **Override precedence:** Pod-level setting always wins over SA-level setting.
    - SA=`false`, Pod=not set → token NOT mounted (SA default applies)
    - SA=`true`, Pod=`false` → token NOT mounted (pod overrides)
    - SA=`false`, Pod=`true` → token IS mounted (pod overrides)
  - **Where to set it:**
    - On the **pod/deployment spec** (`spec.template.spec.automountServiceAccountToken: false`) — affects only that workload.
    - On the **ServiceAccount object itself** (`automountServiceAccountToken: false`) — disables mounting for every pod that uses that SA cluster-wide.
  - **Rule of thumb:** Set `false` on any pod that is a pure application (web server, worker, batch job). Set it `true` (or omit) only when the pod explicitly needs to call the K8s API — operators, controllers, CI/CD deployers, Prometheus, ArgoCD.
  - **Do you need to set it even when no SA is specified in the pod spec?**
    - YES. When you don't set `serviceAccountName`, K8s silently assigns the `default` SA — and its token IS auto-mounted. "I didn't specify an SA" does not mean "no token is mounted." You must explicitly add `automountServiceAccountToken: false` on the pod spec to opt out.
  - **Rule of thumb:** Set `false` on any pod that is a pure application (web server, worker, batch job). Set it `true` (or omit) only when the pod explicitly needs to call the K8s API — operators, controllers, CI/CD deployers, Prometheus, ArgoCD.

**You should know how to answer:**
- What is the default ServiceAccount and why is it a security risk to use it for everything?
- Where is the SA token mounted inside a pod and what format is it in?
---

## Exercise 4 — Pod Security (securityContext)

**Scenario:** Security team flagged that some pods run as root. You need to fix this.

**Your task:**
1. Deploy a pod without any securityContext — exec into it and run `whoami` (likely root)
2. Add a `securityContext` to run as user `runAsUser: 1000`, group `runAsGroup: 3000` (apply the emptyDir fix above first)
3. Set `readOnlyRootFilesystem: true` — then try to write a file inside the container and observe the error
4. Set `allowPrivilegeEscalation: false`
5. Set capabilities `drop: ["ALL"]` and `add: ["NET_BIND_SERVICE"]` — explain what this does

**Pod-level vs Container-level securityContext:**
Apply `fsGroup: 2000` at the pod level — mount a volume and verify files created there are owned by group 2000.

### Enforcing These Settings at the Namespace Level — Pod Security Admission (PSA)

Setting `securityContext` correctly per pod is only half the story. If you rely on developers to do it themselves, someone will forget. PSA is the built-in mechanism that enforces these requirements at the namespace level — at admission time, before a pod ever runs.

**Background:** Pod Security Admission (PSA) is built into K8s 1.25+. It replaced oldPodSecurityPolicy (PSP). You label a namespace to enforce one of three profiles:
- `privileged` — no restrictions
- `baseline` — blocks the most dangerous settings (privileged containers, host namespace sharing, dangerous capabilities)
- `restricted` — Allow least-privilege: everything in `baseline` plus `runAsNonRoot`, `allowPrivilegeEscalation: false`, all capabilities dropped, seccomp required

Each profile can be applied in three independent modes:

| Mode | Behaviour |
|---|---|
| `enforce` | Policy Violations will cause the pod to be rejected — API server blocks it entirely |
| `warn` | Pod is created, but a warning is printed to the client |
| `audit` | Policy Violations will trigger the addition of an audit annotation to the event recorded in the audit log, but Pod creation is allowed otherwise |

**Your task:**
1. Label `team-alpha` to enforce on `baseline` violations and warns and audit `restricted` profile:
  - enforce=baseline - hard floor, blocks only the truly dangerous stuff
  - warn=restricted - tells developers "this pod would fail once we tighten enforcement"
  - audit=restricted - logs it for a compliance report
2. Try to deploy a pod that runs as root (with no `securityContext`) — observe the warning from `restricted` and that the pod is created (because only `baseline` is `enforce`):
3. Now tighten `enforce` to `restricted` — re-deploy the same pod and observe it is rejected outright
4. Deploy a compliant pod with the minimum `securityContext` to satisfy `restricted`:
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  allowPrivilegeEscalation: false
  seccompProfile:
    type: RuntimeDefault
  capabilities:
    drop: ["ALL"]
```
5. Leave `monitoring` namespace as `privileged` — explain why Prometheus `node-exporter` legitimately needs `hostNetwork`/`hostPID`

**Dig deeper:**
- **Why did PodSecurityPolicy get removed and what problem did it cause that PSA solves?**

**You should know how to answer:**
- **What is the difference between a privileged container and a container with added capabilities?**
- **Why is `readOnlyRootFilesystem: true` a security best practice?**
- **"How do you prevent developers from deploying root containers without trusting them to set securityContext themselves?"**
- **What is the `restricted` PSA profile and what does it require on every pod?**
---

## Exercise 5 — Secrets Security Audit

**Scenario:** You inherited a cluster. Audit how Secrets are being handled.

**Your task:**
1. Create a Secret and retrieve its value — observe it is base64 encoded, NOT encrypted
2. Check if etcd encryption at rest is configured
3. Find all pods in the cluster that mounts Secrets as environment variables vs as volume files — which is more secure and why?
4. Find the Orphaned Secrets, Secrets not referenced by any pod - list them
5. What is the Proper solution for secrets management at a company? (Hashicorp Vault ,AWS Secret Manager, Sealed Secrets)

**You should know how to answer:**
- **Why is storing secrets in environment variables less secure than volume mounts?**
- **What is the External Secrets Operator?**

---

## Exercise 6 — Kyverno: Policy Enforcement at Admission Time

**Scenario:** RBAC controls what users and service accounts can do. But it does not control the *content* of what they deploy. A developer with `create deployments` permission can still deploy a container running as root, with no resource limits, pulling from an untrusted registry. Kyverno fixes this — it validates, mutates, and generates resources at admission time.

**Background:** Kyverno is a Kubernetes-native policy engine. It reads `ClusterPolicy` resources and intercepts every create/update request to the API server. If the resource violates a policy, it is rejected (or auto-fixed if using mutation). Every serious company runs either Kyverno or OPA Gatekeeper.

**Install Kyverno:**
```bash
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update
helm install kyverno kyverno/kyverno --namespace kyverno --create-namespace
```

**Your task:**

### Policy 1 — Require Resource Limits on All Pods
No container should be deployable without CPU and memory limits set (prevents noisy-neighbour issues):
```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-resource-limits
spec:
  validationFailureAction: Enforce
  rules:
  - name: check-resource-limits
    match:
      any:
      - resources:
          kinds: [Pod]
    validate:
      message: "CPU and memory limits are required on all containers."
      pattern:
        spec:
          containers:
          - resources:
              limits:
                memory: "?*"
                cpu: "?*"
```
1. Apply the policy
2. Try to deploy a pod without resource limits — observe the rejection
3. Deploy a pod WITH resource limits — confirm it is accepted

### Policy 2 — Disallow Root Containers
```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: disallow-root-containers
spec:
  validationFailureAction: Enforce
  rules:
  - name: check-runasnonroot
    match:
      any:
      - resources:
          kinds: [Pod]
    validate:
      message: "Containers must not run as root. Set runAsNonRoot: true."
      pattern:
        spec:
          containers:
          - securityContext:
              runAsNonRoot: true
```
1. Deploy a pod without `runAsNonRoot: true` — observe rejection
2. Fix the pod — confirm it deploys

### Policy 3 — Auto-Add Labels (Mutation Policy)
Kyverno can mutate resources, not just reject them. Add a policy that automatically adds a `managed-by: platform-team` label to every new namespace:
```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: add-ns-labels
spec:
  rules:
  - name: add-managed-by-label
    match:
      any:
      - resources:
          kinds: [Namespace]
    mutate:
      patchStrategicMerge:
        metadata:
          labels:
            managed-by: platform-team
```
1. Create a new namespace WITHOUT the label
2. Check its labels — Kyverno should have added `managed-by: platform-team` automatically

### Policy 4 — Allowed Image Registries
Prevent pulling images from untrusted registries (only allow your company registry + official images):
```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: restrict-image-registries
spec:
  validationFailureAction: Enforce
  rules:
  - name: validate-registries
    match:
      any:
      - resources:
          kinds: [Pod]
    validate:
      message: "Images must come from docker.io, gcr.io, or quay.io only."
      pattern:
        spec:
          containers:
          - image: "docker.io/* | gcr.io/* | quay.io/* | nginx:* | busybox:* | alpine:* | hashicorp/*"
```

**Check policy violations:**
```bash
kubectl get policyreport -A          # see all policy reports
kubectl describe policyreport <report-name> # see violation details
```

### Insights
**Kyverno supports several rule types, but the most common are:**
1. **Validate**
  - Checks whether a resource satisfies a condition.
  - Does not modify the resource.
  - Depending on the configuration, it can: Allow, Reject or Warn the resource creation
```bash
validate:
  message: "Image tag latest is not allowed."
  pattern:
    spec:
      containers:
      - image: "!*:latest"
```
2. **Mutate**
    - Automatically modifies the resource before it is stored in Kubernetes.
    - Useful for:
      - Adding labels
      - Adding annotations
      - Setting defaults
      - Injecting sidecars
      - Modifying security contexts
```bash
mutate:
  patchStrategicMerge:
    metadata:
      labels:
        owner: platform-team
```
3. **generate** → automatically creates another resource (ConfigMap, Secret, NetworkPolicy, etc.)
4. **verifyImages** → verifies container image signatures and attestations.

**Matching Resources:**
- The match block determines that: "Does this rule apply to this resource?"
- You can match by: kind, namespace, name, labels, user, annotations, roles
```bash
# Only Pods inside the production namespace are evaluated.
match:
  any:
  - resources:
      kinds:
      - Pod
      namespaces:
      - production
```

**Scope:**
We can change the scope where Policy is Applied
- There are two different concepts.
`Policy Scope`
  - A `ClusterPolicy` is cluster-scoped. It exists once for the entire cluster.
  - A `Policy` is namespace-scoped. It only exists inside one namespace.
`Resource Matching`
  - Inside either Policy or ClusterPolicy, you can further restrict which resources are checked using `match`
```bash
# The policy exists cluster-wide, but only evaluates resources inside the payments namespace.
match:
  any:
  - resources:
      namespaces:
      - payments
```

**Effect on Newly Created Resources:**
- When `validationFailureAction: Enforce` (or failureAction: Enforce in newer Kyverno versions) is used CREATE/UPDATE requests go through the Admission Controller.
- If validation fails, the API Server rejects the request.

**Existing Resources**
- Kyverno periodically performs background scans.
- It evaluates existing resources and creates PolicyReports.
- It does not delete or modify those existing resources just because they violate a validation rule.
- Instead it records:
  - PASS, FAIL, WARN, ERROR, SKIP

**Viewing Policy Reports**
- `kubectl get policyreport`
- `kubectl describe policyreport <report-name>`
- `kubectl get clusterpolicyreport`

**Validation policies can operate in two modes.**
- `failureAction: Audit`
  - Resource is allowed.
  - Violation is recorded in PolicyReports.
- `failureAction: Enforce`
  - Resource creation/update is denied.
  - Violation is still reported.

**You should know how to answer:**
- "What is the difference between RBAC and a policy engine like Kyverno?"
  - RBAC controls **who can perform what action** (create, delete, get) on a resource type — it is enforced at the API request level. It does not inspect the *content* of the resource.
  - A developer with `create deployments` RBAC permission can still deploy a root container with no resource limits — RBAC cannot stop that. Kyverno controls **what the content of a resource must look like**: it validates/mutates the YAML itself at admission time, complementing RBAC.

- "Can Kyverno be used to auto-remediate violations or only block them?"
  - Both. `validate` rules block or warn on violation. `mutate` rules **auto-fix** the resource before it is stored — e.g., automatically inject `readOnlyRootFilesystem: true` or add required labels.
  - `generate` rules create new resources in response to another resource being created (e.g., auto-create a NetworkPolicy whenever a new Namespace is created). So Kyverno can enforce, warn, and silently remediate.

- "What is the difference between `Audit` and `Enforce` mode in Kyverno?" (hint: use `Audit` to discover violations first before enabling `Enforce`)
  - **`Audit`**: the resource is **created and runs** — the violation is only recorded in a `PolicyReport` and the API audit log. No workloads are broken.
  - **`Enforce`**: the API server **rejects the request outright** — the resource is never created.
  - Standard rollout: start with `Audit` to discover how many existing workloads would fail, fix them, then flip to `Enforce` once you are confident nothing breaks in production.

- "How is Kyverno different from OPA Gatekeeper?"
  - Both are admission-webhook policy engines. Key differences:
    - **Policy language**: Kyverno uses Kubernetes-native YAML — easy to read and write. OPA Gatekeeper uses **Rego** (a custom declarative language) — very powerful but steep learning curve.
    - **Mutation**: Kyverno has full native mutation support. OPA Gatekeeper's mutation support is limited.
    - **Image verification**: Kyverno has a built-in `verifyImages` rule type for supply-chain security. OPA does not.
    - **Ecosystem scope**: OPA is language-agnostic and used outside K8s (Terraform, HTTP APIs). Kyverno is K8s-specific and integrates more naturally with K8s resource patterns.

---

## Completion Checklist

- [ ] Create namespaced Roles with precise verb/resource permissions
- [ ] Create ClusterRoles for cross-namespace access
- [ ] Set up ServiceAccounts with least-privilege access for CI/CD
- [ ] Apply securityContext to prevent root containers
- [ ] Apply PSA namespace labels to enforce security profiles cluster-wide
- [ ] Explain K8s secrets limitations and the real-world solution
- [ ] Install Kyverno and write validation and mutation policies
- [ ] Block deployments without resource limits using a ClusterPolicy

---

## Interview Questions This Task Prepares You For

- **"How do you ensure a developer cannot delete production resources?"**
- **"Walk me through how you set up RBAC for a CI/CD pipeline."**
- **"Are Kubernetes Secrets secure? What do you use in production?"**
- **"What is a ServiceAccount and when would you use a custom one?"**
- **"How do you prevent pods from running as root?"**
- **"What replaced PodSecurityPolicy and how does PSA work?"**
- **"We had a security breach where a pod exfiltrated secrets. How could that happen and how do you prevent it?"**
- **"RBAC is in place but a developer deployed a root container with no resource limits. How does that happen and how do you prevent it?"**
- **"What is Kyverno and how does it complement RBAC?"**
- **"How do you enforce that only approved container registries are used in production?"**

---

## Mini Project — Secure Namespace for team-alpha with Multi-Role Access

> Estimated time: 2 hours. Put this in GitHub under `k8s-practice/task-05/`.

**Scenario:** You need to set up access control for `team-alpha`. There are 3 personas: a developer (read-only), a deployer CI/CD pipeline (deploy only), and a namespace admin (full control of their namespace but nothing else).

**Deliverables — all as YAML files:**

1. `service-accounts.yaml` — Three ServiceAccounts in `team-alpha`:
   - `dev-viewer`
   - `cicd-deployer`
   - `ns-admin`
2. `roles.yaml` — Three Roles:
   - `viewer`: get/list/watch pods, logs, deployments, services
   - `deployer`: everything in viewer + create/update/patch deployments and services
   - `admin`: full access within `team-alpha` namespace only
3. `rolebindings.yaml` — Bind each SA to its role
4. `secure-deployment.yaml` — A deployment with:
   - Uses `cicd-deployer` ServiceAccount (not default)
     - `serviceAccountName: cicd-deployer`
     - Do NOT set `automountServiceAccountToken: false` here — this pod calls the K8s API using the mounted token; disabling it would break the deployer.
     - Set `automountServiceAccountToken: false` only on pods that have no reason to call the K8s API (e.g., a pure nginx web server).
   - Runs as non-root user (UID 1000) inside `container`
   - `readOnlyRootFilesystem: true`
   - `allowPrivilegeEscalation: false`
   - All capabilities dropped
5. `psa-labels.sh` — a shell script (or document the commands inline in README) that applies PSA labels to `team-alpha`:
   - `enforce=baseline` — hard block on truly dangerous settings
   - `warn=restricted` + `audit=restricted` — warns developers and logs violations without breaking existing workloads
6. `kyverno-policies.yaml` — Two Kyverno ClusterPolicies (Exercise 6):
   - `require-resource-limits`: validate that every pod in `team-alpha` has CPU and memory limits set — reject pods without them
     - using kind: Policy is already namespace scoped so Filtering namespaces not allowed i.e. only match with Pod
   - `disallow-root-pods`: validate that no pod runs as root (`runAsNonRoot: true`) — reject violating pods

**NOTE:**
- Kyverno Polcy `disallow-root-pods` checks for `runAsNonRoot: true` at Pod level not at containers level.

**Proof of completion (document in README.md):**
  ```bash
  # These should WORK
  kubectl get pods -n team-alpha --as=system:serviceaccount:team-alpha:dev-viewer
  kubectl get deploy -n team-alpha --as=system:serviceaccount:team-alpha:cicd-deployer
  
  # These should FAIL
  kubectl delete pod <any-pod> -n team-alpha --as=system:serviceaccount:team-alpha:dev-viewer
  kubectl get pods -n team-beta --as=system:serviceaccount:team-alpha:ns-admin
  ```
Screenshot or paste each output in the README.
- Deploy a pod without `securityContext` in `team-alpha` — show the PSA `warn=restricted` warning printed by the API server
  - Does before this warning, the kyverno rejects the Pod as one attribute `runAsNonRoot: true` required securityContext

- Tighten to `enforce=restricted`, redeploy the same pod — show the API server rejection
  - Same with this, Does before this PSA rejection, the kyverno rejects the Pod as one attribute `runAsNonRoot: true` required securityContext

- Deploy a compliant pod (correct `securityContext`) — show it is accepted
  - secure-deployment.yml already created compliant pod
- Deploy a pod without resource limits in `team-alpha` — show Kyverno blocks it with a policy violation message

- Deploy a pod running as root — show Kyverno blocks it

---

**Next: Task-06-Observability.md**
