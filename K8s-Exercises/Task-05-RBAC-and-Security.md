# Task 05 — RBAC & Security: Who Can Do What in the Cluster

> Real-world relevance: In a company cluster, not everyone should be able to delete
> production deployments. RBAC is how you enforce that — and a misconfigured RBAC
> is one of the most common K8s security incidents.

> **Cluster needed:** Any single-node cluster. RBAC is cluster-wide — node count doesn't matter.
> - **Easiest:** minikube, kind single-node, or Killercoda.
> - **Browser-based:** Killercoda works perfectly for all RBAC exercises.
> - No special add-ons required for this task.
> - If doing the Secrets audit (Exercise 5): Multipass or kind — you need shell access to the node to check etcd encryption config.

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

---

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
3. Verify with `--as=system:serviceaccount:monitoring:prometheus` that the SA can list pods in `team-alpha`
4. Verify it CANNOT create or delete anything

**You should know how to answer:**
- What built-in ClusterRoles exist in K8s that you should know about? (`cluster-admin`, `view`, `edit`)
- Why is binding `cluster-admin` to a CI/CD pipeline dangerous?

---

## Exercise 3 — ServiceAccounts for Applications

**Scenario:** Your CI/CD pipeline (running as a pod) needs to update Deployment images in `team-alpha`.

**Your task:**
1. Create a ServiceAccount `cicd-deployer` in `team-alpha`
2. Create a Role that allows `get`, `list`, `update`, `patch` on `deployments` only
3. Bind the role to the `cicd-deployer` ServiceAccount
4. Deploy a pod that uses `cicd-deployer` SA (not the default SA)
5. From inside that pod, use the mounted SA token to call the K8s API:
   ```bash
   TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
   curl -k -H "Authorization: Bearer $TOKEN" \
     https://kubernetes.default.svc/apis/apps/v1/namespaces/team-alpha/deployments
   ```
6. Try to list Secrets with the same token — verify it is forbidden

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
1. Deploy a pod without any securityContext — exec into it and run `whoami` (likely root)
2. Add a `securityContext` to run as user `1000`, group `3000`
3. Set `readOnlyRootFilesystem: true` — then try to write a file inside the container and observe the error
4. Set `allowPrivilegeEscalation: false`
5. Set `capabilities.drop: ["ALL"]` and `capabilities.add: ["NET_BIND_SERVICE"]` — explain what this does
6. Apply this to the `alpha-api` Deployment from Task 02

**Pod-level vs Container-level securityContext:**
Apply `fsGroup: 2000` at the pod level — mount a volume and verify files created there are owned by group 2000.

**You should know how to answer:**
- What is the difference between a privileged container and a container with added capabilities?
- Why is `readOnlyRootFilesystem: true` a security best practice?
- What is a Pod Security Admission (PSA) and what replaced PodSecurityPolicy?

---

## Exercise 5 — Secrets Security Audit

**Scenario:** You inherited a cluster. Audit how Secrets are being handled.

**Your task:**
1. Create a Secret and retrieve its value — observe it is base64 encoded, NOT encrypted
2. Check if etcd encryption at rest is configured:
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

## Completion Checklist

- [ ] Create namespaced Roles with precise verb/resource permissions
- [ ] Create ClusterRoles for cross-namespace access
- [ ] Set up ServiceAccounts with least-privilege access for CI/CD
- [ ] Apply securityContext to prevent root containers
- [ ] Explain K8s secrets limitations and the real-world solution

---

## Interview Questions This Task Prepares You For

- "How do you ensure a developer cannot delete production resources?"
- "Walk me through how you set up RBAC for a CI/CD pipeline."
- "Are Kubernetes Secrets secure? What do you use in production?"
- "What is a ServiceAccount and when would you use a custom one?"
- "How do you prevent pods from running as root?"
- "We had a security breach where a pod exfiltrated secrets. How could that happen and how do you prevent it?"

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

---

**Next: Task-06-Observability.md**
