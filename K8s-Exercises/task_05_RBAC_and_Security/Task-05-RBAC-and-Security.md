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

## A bit info about all
**About:**
1. A `RoleBinding` does two things:
    - References one `Role` (or `ClusterRole`).
    - Assigns that Role to one or more subjects (`users, groups, or serviceaccounts`).
2. `ServiceAccount` → does require a namespace, because ServiceAccounts are namespaced (no matter in `Rolebinding` or `Clusterrolebinding`)
3. We didnt get any error while binding even if user, groups, serviceaccount not present.
4. Roles, Rolebinding, clsuterrole, clusterrolebinding, user, groups, serviceAccount (how they are different from user)
5. Can we create user, group ,can we add or delete user in group(why why not), can we create serviceAccount
6. If there is any term I need to know which is important related to RBAC and security purpose or authentication and authorizaton.
---

## Exercise 1 — Role and RoleBinding (Namespace Scoped)

**Scenario:** A developer on `team-alpha` should be able to view pods and logs but NOT delete anything.

**Your task:**
1. Create a Role named `alpha-dev-readonly` in namespace `team-alpha` that allows:
   - `get`, `list`, `watch` on `pods`
   - `get` on `pods/log`
   - `get`, `list` on `deployments` and `services`
  ```bash
      # kubectl create role -h

      kubectl create role alpha-dev-readonly -n team-alpha --verb=get,list,watch --resource=deployments,services,pods,pods/log --dry-run=client -o yaml > dev-readonly.yml

      # Then edit the manifest accordingly..
      
  ```
2. Create a RoleBinding that binds `alpha-dev-readonly` to a user named `dev-alice`
  ```bash
      # kubectl create rolebinding -h

      kubectl create rolebinding dev-rolebinding-readonly --role=alpha-dev-readonly -n team-alpha --user=dev-alice --dry-run=client -o yaml > dev-rolebinding-readonly.yml
  ```
3. Test it: simulate the user with `--as=dev-alice`
   - `kubectl get pods -n team-alpha --as=dev-alice` → should work
   - `kubectl delete pod <pod> -n team-alpha --as=dev-alice` → should be forbidden
  ```bash
      kubectl apply -f .
      
      # create a test pod
      kubectl run nginx-pod --image=nginx -n team-alpha

      kubectl get pods -n team-alpha --as=dev-alice
      kubectl delete pod nginx-pod -n team-alpha --as=dev-alice
  ```
4. Create another Role `alpha-dev-write` that also allows `create`, `update`, `patch` on `deployments`
  ```bash
      kubectl create role alpha-dev-write -n team-alpha --verb=create,update,patch --resource=deployments --dry-run=client -o yaml > dev-write.yml
  ```
5. Bind it to a group `alpha-leads` — bind `dev-alice` to this group (add a second RoleBinding)
**IMPORTANT** - K8s doesnot have any user-group creation deleting, we need some IAM like OIDC, AzureAD, KeyCload, or AWS IAM (does it work)
  ```bash
      kubectl create rolebinding dev-rolebind-write --role=alpha-dev-write -n team-alpha --group=alpha-leads --dry-run=client -o yaml > dev-rolebinding-write.yml
  ```

**You should know how to answer:**
- What is the difference between a Role and a ClusterRole?
  - Role is Namespace Scoped
  - ClusterRole is ClusterScoped and can be bind to specific Namespace also.

- Can you use a ClusterRole inside a specific namespace?
  - ClusterRole + ClusterRoleBinding → cluster-wide access
  - ClusterRole + RoleBinding → namespace-limited access
  - Role + RoleBinding → namespace-limited access
  - Role + ClusterRoleBinding -> `Not Possible`

---

## Exercise 2 — ClusterRole and ClusterRoleBinding

**Scenario:** The monitoring team needs to read metrics from ALL namespaces — namespace-scoped Roles won't work.

**Your task:**
1. Create a ClusterRole `monitoring-reader` that allows:
   - `get`, `list`, `watch` on `pods`, `nodes`, `services`, `endpoints`
   - `get` on `pods/log`
  ```bash
      # kubectl create clusterrole -h

      kubectl create clusterrole monitoring-reader --verb=get,list,watch --resource=pods,nodes,service,endpoints,pods/log --dry-run=client -o yaml > monitoring-reader.yml

      # Then edit the manifest accordingly..
      
  ```
2. Create a ClusterRoleBinding that binds this role to ServiceAccount `prometheus` in namespace `monitoring`
  ```bash
      # kubectl create clusterrolebinding -h

      kubectl create clusterrolebinding monitor-clusterrolebinding --clusterrole=monitoring-reader --serviceaccount=monitoring:prometheus --dry-run=client -o yaml > monitor-reader-clusterrolebinding.yml
  ```
3. Verify with `--as=system:serviceaccount:monitoring:prometheus` that the SA can list pods in `team-alpha` in any namespace.
  ```bash
      kubectl get pods --as=system:serviceaccount:monitoring:prometheus
  ```
4. Verify it CANNOT create or delete anything in any namespace.
  ```bash
      kubectl run pod nginx-pod-2 --image=nginx:1.25 --as=system:serviceaccount:monitoring:prometheus
      kubectl delete pod nginx-pod --as=system:serviceaccount:monitoring:prometheus
  ```

**You should know how to answer:**
- What built-in ClusterRoles exist in K8s that you should know about? (`cluster-admin`, `view`, `edit`)
- Why is binding `cluster-admin` to a CI/CD pipeline dangerous?

---

## Exercise 3 — ServiceAccounts for Applications

**Scenario:** Your CI/CD pipeline (running as a pod) needs to update Deployment images in `team-alpha`.

**Your task:**
1. Create a ServiceAccount `cicd-deployer` in `team-alpha`.
  ```bash
      kubectl create serviceaccount cicd-deployer -n team-alpha
  ```
2. Create a Role that allows `get`, `list`, `update`, `patch` on `deployments` only
  ```bash
    kubectl create role cicd-reader -n team-alpha --verb=get,list,update,patch --resource=deployments --dry-run=client -o yaml > cicd-reader.yml
  ```
3. Bind the role to the `cicd-deployer` ServiceAccount
  ```bash
    kubectl create rolebinding cicd-deployer-rolebinding --role=cicd-reader --serviceaccount=team-alpha:cicd-deployer -n team-alpha --dry-run=client -o yaml > cicd-deployer-rolebinding.yml
  ```
4. Verify all three
  ```bash
    kubectl get role cicd-reader
    kubectl get rolebinding cicd-deployer-rolebinding
    kubectl get sa cicd-deployer
  ```
5. Deploy a pod that uses `cicd-deployer` SA (not the default SA)
  ```bash
    kubectl create deployment test-pod --image=nginx:1.25 --replicas=3 --as=cicd-deployer
  ```
6. From inside that pod, use the mounted SA token to call the K8s API:
   ```bash
   TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
   curl -k -H "Authorization: Bearer $TOKEN" \
     https://kubernetes.default.svc/apis/apps/v1/namespaces/team-alpha/deployments
   ```
7. Try to list Secrets with the same token — verify it is forbidden

**Dig deeper:**
- Disable auto-mounting of the default SA token on a pod: `automountServiceAccountToken: false`
- Explain why you should do this for pods that don't need API access

**You should know how to answer:**
- What is the default ServiceAccount and why is it a security risk to use it for everything?
- Where is the SA token mounted inside a pod and what format is it in?

---

## Exercise 4 — Pod Security (securityContext)

**Scenario:** Security team flagged that some pods run as root. You need to fix this.

**Your task:**
```bash
    kubectl create deploy test-deploy --image=nginx:1.25 --replicas=3 -n team-alpha --dry-run=client -o yaml > test-deploy.yml
```
1. Deploy a pod without any securityContext — exec into it and run `whoami` (likely root)
  ```bash
      kubectl exec -it test-pod -- sh
      whoami
  ```
2. Add a `securityContext` to run as user `runAsUser: 1000`, group `runAsGroup: 3000`
  ```bash
      kubectl exec -it test-pod -- sh
      whoami
  ```
3. Set `readOnlyRootFilesystem: true` — then try to write a file inside the container and observe the error
  ```bash
      kubectl exec -it test-pod -- sh
      echo "Hello Hi" > test_file.txt
  ```
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
   ```bash
   kubectl label namespace team-alpha \
     pod-security.kubernetes.io/enforce=baseline \
     pod-security.kubernetes.io/enforce-version=latest \
     pod-security.kubernetes.io/warn=restricted \
     pod-security.kubernetes.io/warn-version=latest \
     pod-security.kubernetes.io/audit=restricted \
     pod-security.kubernetes.io/audit-version=latest
   ```
   ```bash
      kubectl run nginx --image=nginx --dry-run=client -o yaml > psa_pod.yml
    ```
2. Try to deploy a pod that runs as root (with no `securityContext`) — observe the warning from `restricted` and that the pod is created (because only `baseline` is `enforce`):
   ```bash
   kubectl run nginx --image=nginx:1.25 -n team-alpha
   # Warning: would violate PodSecurity "restricted:latest": allowPrivilegeEscalation != false ...
   # pod/nginx created  ← allowed because restricted is only warn/audit, not enforce
   ```
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

  PSP was removed because it was overly complex:
  - Required PSP object + RBAC Role + RoleBinding just to activate — easy to misconfigure
  - Could silently mutate Pods by injecting defaults, making behaviour unpredictable
  - Policy selection (which PSP applied to which pod) was confusing

  PSA replaces it with a simple namespace-label approach:
  - Label a namespace → enforcement is automatic, no extra objects needed
  - Three predefined profiles: `privileged`, `baseline`, `restricted`
  - PSA only validates, never mutates — behaviour is fully predictable

  For custom rules beyond PSA (registries, label requirements) → use Kyverno or OPA Gatekeeper.

**You should know how to answer:**
- What is the difference between a privileged container and a container with added capabilities?
- Why is `readOnlyRootFilesystem: true` a security best practice?

- **"How do you prevent developers from deploying root containers without trusting them to set securityContext themselves?"**

  Label the namespace with PSA `enforce=restricted`. The API server validates every pod at admission — pods missing required security fields are rejected before scheduling, regardless of what the developer put in their YAML. For custom rules beyond PSA (image registry restrictions, label requirements) → add Kyverno or OPA Gatekeeper.

- **What is the `restricted` PSA profile and what does it require on every pod?**

  The most secure built-in PSA profile. Every pod must have:
  - `runAsNonRoot: true`
  - `allowPrivilegeEscalation: false`
  - `capabilities.drop: ["ALL"]`
  - `seccompProfile.type: RuntimeDefault` or `Localhost`
---

## Exercise 5 — Secrets Security Audit

**Scenario:** You inherited a cluster. Audit how Secrets are being handled.

**Your task:**
1. Create a Secret and retrieve its value — observe it is base64 encoded, NOT encrypted
2. Check if etcd encryption at rest is configured: NOT FOund Also add by exec into docker control-plane container.
   ```bash
   sudo cat /etc/kubernetes/manifests/kube-apiserver.yaml | grep encryption
   ```
3. Find all pods in the cluster that mount Secrets as environment variables vs as volume files — which is more secure and why?
4. Find Secrets that are not being used by any pod (orphaned secrets) — list them
5. Research and write a short answer: what is the proper solution for secrets management at a company? (HashiCorp Vault, AWS Secrets Manager, Sealed Secrets)

**You should know how to answer:**
- Why is storing secrets in environment variables less secure than volume mounts?
- What is the External Secrets Operator?

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
kubectl describe policyreport <name> # see violation details
```

**You should know how to answer:**
- "What is the difference between RBAC and a policy engine like Kyverno?"
- "Can Kyverno be used to auto-remediate violations or only block them?"
- "What is the difference between `Audit` and `Enforce` mode in Kyverno?" (hint: use `Audit` to discover violations first before enabling `Enforce`)
- "How is Kyverno different from OPA Gatekeeper?"

---

## Completion Checklist

- [x] Create namespaced Roles with precise verb/resource permissions
- [x] Create ClusterRoles for cross-namespace access
- [ ] Set up ServiceAccounts with least-privilege access for CI/CD
- [ ] Apply securityContext to prevent root containers
- [ ] Apply PSA namespace labels to enforce security profiles cluster-wide
- [ ] Explain K8s secrets limitations and the real-world solution
- [ ] Install Kyverno and write validation and mutation policies
- [ ] Block deployments without resource limits using a ClusterPolicy

---

## Interview Questions This Task Prepares You For

- "How do you ensure a developer cannot delete production resources?"
- "Walk me through how you set up RBAC for a CI/CD pipeline."
- "Are Kubernetes Secrets secure? What do you use in production?"
- "What is a ServiceAccount and when would you use a custom one?"
- "How do you prevent pods from running as root?"
- "What replaced PodSecurityPolicy and how does PSA work?"
- "We had a security breach where a pod exfiltrated secrets. How could that happen and how do you prevent it?"
- "RBAC is in place but a developer deployed a root container with no resource limits. How does that happen and how do you prevent it?"
- "What is Kyverno and how does it complement RBAC?"
- "How do you enforce that only approved container registries are used in production?"

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
   - Runs as non-root user (UID 1000)
   - `readOnlyRootFilesystem: true`
   - `allowPrivilegeEscalation: false`
   - All capabilities dropped
   - `automountServiceAccountToken: false`
5. `psa-labels.sh` — a shell script (or document the commands inline in README) that applies PSA labels to `team-alpha`:
   - `enforce=baseline` — hard block on truly dangerous settings
   - `warn=restricted` + `audit=restricted` — warns developers and logs violations without breaking existing workloads
6. `kyverno-policies.yaml` — Two Kyverno ClusterPolicies (Exercise 6):
   - `require-resource-limits`: validate that every pod in `team-alpha` has CPU and memory limits set — reject pods without them
   - `disallow-root`: validate that no pod runs as root (`runAsNonRoot: true`) — reject violating pods

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
- Tighten to `enforce=restricted`, redeploy the same pod — show the API server rejection
- Deploy a compliant pod (correct `securityContext`) — show it is accepted
- Deploy a pod without resource limits in `team-alpha` — show Kyverno blocks it with a policy violation message
- Deploy a pod running as root — show Kyverno blocks it

---

**Next: Task-06-Observability.md**
