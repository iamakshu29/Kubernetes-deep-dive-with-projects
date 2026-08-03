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
1. Roles, Rolebinding, clsuterrole, clusterrolebinding, user, groups, serviceAccount (how they are different from user)
   - **Role** — permissions scoped to one namespace (verbs on resources)
   - **RoleBinding** — attaches a Role (or ClusterRole) to subjects within a namespace
   - **ClusterRole** — same as Role but cluster-wide; can be bound to a specific namespace via RoleBinding
   - **ClusterRoleBinding** — attaches a ClusterRole to subjects across the entire cluster
   - **User** — external identity (cert CN, OIDC token `sub` claim); K8s does NOT store or manage users
   - **Group** — a set of users; K8s does NOT manage groups — they come from the cert `O=` field or OIDC token claims
   - **ServiceAccount** — a K8s-managed identity for pods/processes (not humans); lives in a namespace; K8s creates a JWT token for it and auto-mounts it into every pod that uses it
     - Creation require a namespace, because ServiceAccounts are namespaced (no matter in `Rolebinding` or `Clusterrolebinding`)
2. Can we create user, group — can we add or delete user in group — can we create ServiceAccount?
   - **User / Group**: NO `kubectl create user`. K8s has no user store. Users are defined externally via certs (`openssl`, `kubeadm`) or an OIDC provider (Azure AD, Okta, AWS IAM). You "add a user to a group" by controlling what the identity provider puts in the cert `O=` field or OIDC `groups` claim. K8s only sees what it receives in the request.
   - **ServiceAccount**: YES — `kubectl create serviceaccount <name> -n <namespace>`. It is a first-class K8s object. K8s manages its JWT token lifecycle automatically.
3. Important terms for RBAC, authentication, and authorization:
   - **Subject** — who (User, Group, ServiceAccount) is listed in a RoleBinding/ClusterRoleBinding
   - **Principal** — generic term for "authenticated identity" in security literature
   - **Impersonation** — `kubectl --as=<user>` lets an admin test permissions as another identity without switching credentials
   - **OIDC** — OpenID Connect; the protocol used with external identity providers for human user auth
   - **`system:` prefix** — K8s reserved namespace: `system:serviceaccount:ns:name`, `system:masters` (= cluster-admin group), `system:authenticated`, `system:unauthenticated`
   - **cluster-admin** — built-in ClusterRole with unrestricted access to everything; effectively root for the cluster
   - **Admission Controller** — intercepts API requests *after* auth/RBAC but *before* persistence; PSA and Kyverno are admission controllers
   - **`automountServiceAccountToken`** — if true (default), K8s injects the SA JWT into the pod at `/var/run/secrets/kubernetes.io/serviceaccount/token`; set false for pods that don't call the K8s API
4. ServiceAccount token mechanics — how a pod actually calls the K8s API (Exercise 3):
   - When a pod runs with a ServiceAccount, K8s auto-mounts a JWT token at `/var/run/secrets/kubernetes.io/serviceaccount/token`
   - The pod reads that token and sends it as `Authorization: Bearer <token>` to `https://kubernetes.default.svc`
   - The API server verifies the token → resolves the identity to `system:serviceaccount:team-alpha:cicd-deployer` → runs the RBAC check → allows or denies
   - This is how ArgoCD, Prometheus, Helm, and every in-cluster tool authenticates
   - **`serviceAccountName: cicd-deployer`** in the pod spec = which SA's token K8s mounts INTO the running pod (actual pod identity)
   - **`--as=system:serviceaccount:ns:name`** in kubectl = impersonating that SA from outside for testing only — completely different concept
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
5. Deploy a deployment whose pods run with the `cicd-deployer` SA (not the default SA)
   > `--as=cicd-deployer` is impersonation (testing only) — it does NOT make the pod use that SA. You set the SA inside the pod spec.
  ```bash
    kubectl create deployment cicd-test --image=nginx:1.25 --replicas=1 -n team-alpha --dry-run=client -o yaml > cicd-test-deploy.yml
    # Then add under spec.template.spec:
    #   serviceAccountName: cicd-deployer
    kubectl apply -f cicd-test-deploy.yml -n team-alpha
  ```
6. From inside that pod, use the mounted SA token to call the K8s API:
   > What's happening: K8s auto-mounted the `cicd-deployer` JWT at a fixed path inside the pod. You read it and use it as a Bearer token in an HTTP call to the K8s API server. The API server verifies the token → identifies the caller as `system:serviceaccount:team-alpha:cicd-deployer` → checks RBAC → allows (because that SA has `get,list` on deployments).
   ```bash
   # First exec into the running pod
   kubectl exec -it -n team-alpha $(kubectl get pod -n team-alpha -l app=cicd-test -o jsonpath='{.items[0].metadata.name}') -- sh

   # Inside the pod — read the mounted token and call the API
   TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
   curl -k -H "Authorization: Bearer $TOKEN" \
     https://kubernetes.default.svc/apis/apps/v1/namespaces/team-alpha/deployments
   # Expected: JSON response listing deployments in team-alpha
   ```
   > `https://kubernetes.default.svc` is the K8s API server's ClusterIP Service — it always exists in every cluster and is reachable from any pod.

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
2. Add a `securityContext` to run as user `runAsUser: 1000`, group `runAsGroup: 3000` (apply the emptyDir fix above first)
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
  ```bash
    kubectl create secret generic test-secret --from-literal=secret_key=secret_value -n team-alpha

    kubectl get secret test-secret -n team-alpha -o yaml
    # The 'data:' field shows base64 — decode it:
    echo "<base64value>" | base64 --decode
  ```
  > Anyone with `get secrets` RBAC permission can decode this instantly. base64 is encoding, not encryption.

2. Check if etcd encryption at rest is configured
   ```bash
   # For kind clusters — the control-plane runs inside a Docker container, not directly on your machine
   docker exec -it <your-kind-cluster-name>-control-plane \
     grep -i encryption /etc/kubernetes/manifests/kube-apiserver.yaml | grep encryption
   ```
   **Result:** Nothing returned — encryption is NOT configured (default in most clusters including kind).

   When encryption IS configured you would see a flag like:
   `--encryption-provider-config=/etc/kubernetes/pki/encryption-config.yaml`

   **What "not configured" means:** Secrets are written to etcd as base64-only. Anyone with direct etcd access (or a backup of etcd) can read every secret in plaintext. The `kube-apiserver.yaml` manifest controls this because the API server is the only component that writes to etcd.

3. Find all pods in the cluster that mounts Secrets as environment variables vs as volume files — which is more secure and why?

   **Environment variables (less secure):**
   - Visible in `kubectl describe pod` output — anyone with `get pods` can see them
   - Visible in the process list (`/proc/<pid>/environ`) inside the container
   - Leaked to child processes automatically by the OS
   - Printed accidentally in crash logs and debug output
   - Cannot be rotated without restarting the pod

   **Volume mounts (more secure):**
   - Not visible in `kubectl describe pod` — only the mount path is shown
   - Accessible as files inside the container, not exposed to subprocesses automatically
   - Can be rotated in-place: update the Secret, kubelet refreshes the file in the pod within ~1 minute — no pod restart needed
   - Can use `tmpfs` (in-memory) volumes so the secret never touches disk

4. Find the Orphaned Secrets, Secrets not referenced by any pod - list them

   There is no built-in `kubectl` command for this. Finding orphaned secrets requires cross-referencing:
   - All Secrets in the namespace
   - All pod specs' `env.valueFrom.secretKeyRef` and `envFrom.secretRef` references
   - All pod specs' `volumes.secret.secretName` references
   - All pod specs' `imagePullSecrets` references

   **Why they matter:** Orphaned secrets still exist in etcd in plaintext. They widen the blast radius of an etcd compromise without serving any active workload. Regular audits and deleting unused secrets is part of least-privilege hygiene.

5. What is the Proper solution for secrets management at a company? (Hashicorp Vault ,AWS Secret Manager, Sealed Secrets)
   - **HashiCorp Vault** — dedicated secrets store with fine-grained access policies, dynamic secrets (generates DB creds on demand), secret leasing and auto-rotation. Used via the Vault Agent sidecar or the Secrets Store CSI Driver.
   - **AWS Secrets Manager / Azure Key Vault / GCP Secret Manager** — cloud-native equivalents; tightly integrated with cloud IAM.
   - **Sealed Secrets (Bitnami)** — encrypts Kubernetes Secrets with a cluster-specific key so they can be safely stored in Git. Decrypted only inside the cluster.
   - **External Secrets Operator** — syncs secrets from any external store (Vault, AWS SM, Azure KV) into Kubernetes Secrets automatically; manages rotation.

**You should know how to answer:**
- **Why is storing secrets in environment variables less secure than volume mounts?**
  Env vars are visible in `kubectl describe pod`, leaked to child processes, and appear in crash dumps. Volume-mounted secrets are not exposed in describe output, can be rotated without pod restarts, and can be backed by in-memory `tmpfs`.

- **What is the External Secrets Operator?**
  A K8s controller that watches `ExternalSecret` custom resources. Each `ExternalSecret` points to a secret in an external store (HashiCorp Vault, AWS Secrets Manager, Azure Key Vault, etc.) and a target K8s Secret. The operator fetches the value, creates/updates the K8s Secret, and re-syncs on a schedule. Teams store secrets in the real secrets store and the operator handles bridging them into the cluster — you never manually manage Secret YAML.

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
- [x] Set up ServiceAccounts with least-privilege access for CI/CD
- [x] Apply securityContext to prevent root containers
- [x] Apply PSA namespace labels to enforce security profiles cluster-wide
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
  ```bash
      kubectl create serviceaccount dev-viewer -n team-alpha --dry-run=client -o yaml > dev-sa.yml
      kubectl create serviceaccount cicd-deployer -n team-alpha --dry-run=client -o yaml > cicd-sa.yml
      kubectl create serviceaccount ns-admin -n team-alpha --dry-run=client -o yaml > ns-sa.yml
  ```
2. `roles.yaml` — Three Roles:
   - `viewer`: get/list/watch pods, logs, deployments, services
   - `deployer`: everything in viewer + create/update/patch deployments and services
   - `admin`: full access within `team-alpha` namespace only
  ```bash
      # Update the manifest before applying
      kubectl create role viewer -n team-alpha --verb=get,list,watch --resource=pods,pod/logs,deployments,services --dry-run=client -o yaml > viewer.yml
      kubectl create role deployer -n team-alpha --verb=get,list,watch,create,update,patch --resource=pods,pod/logs,deployments,services --dry-run=client -o yaml > deployer.yml
      kubectl create role admin -n team-alpha --verb="*" --resource="*" --dry-run=client -o yaml > admin.yml
  ```
3. `rolebindings.yaml` — Bind each SA to its role
  ```bash
      kubectl create rolebinding dev-viewer-rb -n team-alpha --role=viewer --serviceaccount=team-alpha:dev-viewer --dry-run=client -o yaml > devviewer-rb.yml
      kubectl create rolebinding cicd-deployer-rb -n team-alpha --role=deployer --serviceaccount=team-alpha:cicd-deployer --dry-run=client -o yaml > cicddep-rb.yml
      kubectl create rolebinding ns-admin-rb -n team-alpha --role=admin --serviceaccount=team-alpha:ns-admin --dry-run=client -o yaml > nsadmin-rb.yml
  ```
4. `secure-deployment.yaml` — A deployment with:
   - Uses `cicd-deployer` ServiceAccount (not default)
   - Runs as non-root user (UID 1000)
   - `readOnlyRootFilesystem: true`
   - `allowPrivilegeEscalation: false`
   - All capabilities dropped
   - `automountServiceAccountToken: false` (not yet implemented)
  ```bash
      kubectl create deployment secure-deploy -n team-alpha --image=nginx:1.25 --replicas=1 --dry-run=client -o yaml > secure-deployment.yml
  ```
5. `psa-labels.sh` — a shell script (or document the commands inline in README) that applies PSA labels to `team-alpha`:
   - `enforce=baseline` — hard block on truly dangerous settings
   - `warn=restricted` + `audit=restricted` — warns developers and logs violations without breaking existing workloads
  ```bash
      kubectl label ns team-alpha pod-security.kubernetes.io/enforce=baseline pod-security.kubernetes.io/enforce-version=latest pod-security.kubernetes.io/warn=restricted pod-security.kubernetes.io/warn-version=latest pod-security.kubernetes.io/audit=restricted pod-security.kubernetes.io/audit-version=latest
  ```
6. `kyverno-policies.yaml` — Two Kyverno ClusterPolicies (Exercise 6):
   - `require-resource-limits`: validate that every pod in `team-alpha` has CPU and memory limits set — reject pods without them
   - `disallow-root`: validate that no pod runs as root (`runAsNonRoot: true`) — reject violating pods
  ```bash
  ```

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
