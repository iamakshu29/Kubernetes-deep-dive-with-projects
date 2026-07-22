# Task 01 — Namespaces, Contexts & Multi-Team Cluster Management

> Real-world relevance: At a company, a K8s cluster is shared by multiple teams.
> A DevOps engineer sets up isolation, access boundaries, and manages who talks to what.
> This is day-1 work when you join a company that runs K8s.

> **Cluster needed:** Any single-node cluster works fine.
> - **Easiest:** `minikube start` or `kind create cluster` — one command, done.
> - **Browser-based (no install):** [Killercoda](https://killercoda.com) → Kubernetes Playground.
> - Multi-node is NOT required here. All namespace and context concepts work on 1 node.

---

## What You Will Learn

- Why namespaces exist and how companies use them
- How to organise a cluster for multiple teams/environments
- kubectl context switching — how you manage multiple clusters in real work
- ResourceQuota and LimitRange — preventing one team from consuming all cluster resources
- Pod Security Admission Standards

---

## Background — Read Before Starting

At a company, a single cluster typically has namespaces like:

```
dev         → developers test their apps here
staging     → pre-production environment
production  → live traffic
monitoring  → Prometheus, Grafana live here
infra       → ingress controllers, cert-manager, etc.
team-alpha  → dedicated namespace for one product team
team-beta   → another product team
```

Everything from here forward: you will pretend you are the DevOps engineer managing this cluster for two product teams.

---

## Exercise 1 — Create the Company Namespace Structure

**Scenario:** You have just been given admin access to a fresh cluster. Set it up for two teams.

**Your task:**
1. Create namespaces: `team-alpha`, `team-beta`, `staging`, `monitoring`
# kubectl create ns <ns-name>
2. Label each namespace with `team=alpha`, `team=beta`, `env=staging`, `env=monitoring` respectively
# kubectl label <resource_type> <resource_name> <key>=<value>
# kubectl label ns staging env=staging
3. Verify all namespaces exist with their labels
# kubectl get <resource_type> --show-labels
4. List only namespaces that belong to a specific team using label selectors
# kubectl get <resource_type> --selector=<key>=<value>
# kubectl get ns --selector=env=staging
# kubectl get ns --selector=env ### or just use key to filter out

**You should know how to answer:**
- Why not just use one namespace for everything?
ANS - To isolate the resources based on teams or requirement
- What happens to resources when you delete a namespace?
ANS - All the ns related resource get deleted, and clusterscope resources like node, pv crd remains as it is

---

## Exercise 2 — ResourceQuota (Preventing Resource Abuse)

**Scenario:** `team-alpha` is known to deploy too many pods and starve other teams. You need to cap them.

**Your task:**
Apply a ResourceQuota to `team-alpha` that enforces:
- Maximum 10 pods
- Maximum CPU requests: 4 cores total
- Maximum memory requests: 4Gi total
- Maximum 5 ConfigMaps
- Maximum 2 Services

Then:
1. Try to create 11 pods in `team-alpha` and observe what happens
ANS - forbidden
2. Check quota usage with `kubectl describe`
# kubectl get resourceQuota <quota_name> -n <ns_name>
OR
# kubectl describe ns team-alpha

**You should know how to answer:**
- What is the difference between requests and limits in a quota?
ANS - requests are guaranteed resource provided to use or create for resource present inside NameSpace and Limits are maximum resources a Namespace resource can use or create
- What happens to existing pods if you add a quota after they are already running?
ANS - effects on the future pod as default but can change as per the flag I guess so that quota applied on existing pods which cause the pods to restart or recreate to had the effect.

---

## Exercise 3 — LimitRange (Default Resource Limits)

**Scenario:** Developers in `team-beta` keep forgetting to set resource requests on their pods. This causes the scheduler to make poor decisions. You need to enforce defaults.

**Your task:**
Apply a LimitRange to `team-beta` that sets:
- Default CPU request: `100m`, limit: `500m`
- Default memory request: `128Mi`, limit: `256Mi`
- Min CPU: `50m`, Max CPU: `1`
# kubectl describe ns team-beta
Then:
1. Deploy a pod in `team-beta` **without any resource requests** and check what limits got applied
ANS - Same as set in LimitRange 
2. Try to deploy a pod requesting `2` CPU and observe the rejection
ANS - forbidden

---

## Exercise 4 — Contexts (Managing Multiple Clusters)

**Scenario:** You manage 3 clusters — dev, staging, prod. You need to switch between them safely without risk of running a command on the wrong cluster.

**Your task:**
1. View your current kubeconfig with `kubectl config view`
# contains 3 different object - 
# cluster, user, context (identifies the context {cluster+user+namespace(optional)})

2. Rename your current context to `k8s-dev` (it represents your dev cluster)
# Just changes the context-name
# kubectl config rename-context <current_name> <updated_name>
# kubectl config rename-context kind-devops-lab k8s-dev
## To verify
# kubectl config get-contexts

3. Set your default namespace for the `k8s-dev` context to `team-alpha` so you don't have to type `-n team-alpha` every time
# kubectl config get-contexts
# >> kubectl config set-context <context-name> --namespace=team-alpha
# kubectl config set-context k8s-dev --namespace=team-alpha
## verify
# kubectl get pods

4. Simulate having a second cluster by creating a second context pointing to the same cluster but with namespace `team-beta` — name it `k8s-dev-beta`
# kubectl config set-context k8s-dev-beta --cluster=kind-devops-lab --user=kind-devops-lab --namespace=team-beta
# kubectl config get-contexts

5. Switch between contexts and verify that `kubectl get pods` shows the right namespace without specifying `-n`
# kubectl config get-contexts ## To check context-name
# kubectl config use-context <context-name>
# kubectl config use-context k8s-dev-beta
# kubectl get pods
# kubectl config get-contexts ## to verify again

**Bonus task:** Write a one-liner shell alias that shows you the current context and namespace in your terminal prompt. This is something real DevOps engineers do.
```
echo "Context: $(kubectl config current-context), $(kubectl config view --minify | grep namespace)"

# For alias
alias kctx='echo "Context: $(kubectl config current-context), $(kubectl config view --minify | grep namespace)" 2>/dev/null || echo default'
```


**You should know how to answer:**
- What is the difference between a context, a cluster, and a user in kubeconfig?
**Answer**
  - In Kubernetes, a kubeconfig has three main components: cluster, user, and context.
    - Cluster: Specifies where to connect. It contains the Kubernetes API server endpoint and certificate information.
    - User: Specifies how to authenticate. It contains credentials such as a token, client certificate, or an authentication plugin.
    - Context: Specifies which user should access which cluster, and can also define a default namespace. It is a combination of cluster + user + namespace.
- Why do we use context ?
**Answer**
  - Contexts provide a convenient way to switch between different Kubernetes environments without modifying the kubeconfig or passing command-line flags every time.
- How do you prevent accidentally running `kubectl delete` on production?
**Answer**
  - "To avoid accidentally deleting resources in production, I use separate Kubernetes contexts, always verify the current context before executing commands, enforce RBAC to restrict delete permissions, prefer CI/CD for production changes, and use --dry-run where appropriate. I also use context-aware shell prompts so it's obvious when I'm connected to a production cluster."

---

## Exercise 5 — Namespace Cleanup

**Scenario:** `team-alpha` project is decommissioned. You need to clean it up safely.

**Your task:**
1. List all resources inside `team-alpha` before deleting (pods, services, configmaps, secrets, deployments)
# kubectl get all
2. Delete the namespace
# kubectl delete ns
3. Observe that all resources inside were automatically removed
4. What would have happened if a PersistentVolumeClaim was in that namespace? Research and write a one-paragraph answer.
  - If a PersistentVolumeClaim (PVC) existed in the namespace and the namespace was deleted, the PVC would also be deleted because it is a namespaced resource. - - However, what happens to the underlying PersistentVolume (PV) depends on the PV's reclaim policy.
    - If the reclaim policy is Delete, the storage backend (such as an EBS volume, Azure Disk, or GCE Persistent Disk) is automatically deleted after the PVC is removed.
    - If the reclaim policy is Retain, the PV is released but the underlying storage remains, allowing an administrator to manually recover or reuse the data.
    - If the reclaim policy is Recycle (deprecated), the volume is scrubbed and made available for reuse. 
  - Therefore, accidentally deleting a namespace containing PVCs can result in permanent data loss if the associated PVs use the Delete reclaim policy, which is why production storage is often configured with the `Retain policy for critical data`.
---

## Exercise 6 — Pod Security Admission Standards

**Scenario:** Security team requires that `team-alpha` namespace enforces strict security posture — no root containers, no privilege escalation, no host namespaces. You must do this at the namespace level so it applies automatically to every pod deployed there, without relying on developers remembering to set `securityContext`.

**Background:** Pod Security Admission (PSA) is built into K8s 1.25+. It replaces the old PodSecurityPolicy. You label a namespace to enforce one of three profiles:
- `privileged` — no restrictions
- `baseline` — blocks the most dangerous settings
- `restricted` — enforced least-privilege (runs as non-root, no privilege escalation, seccomp applied)

The label you select defines what action the control plane takes if a potential violation is detected:
    Mode	     Description
- `enforce` -	Policy violations will cause the pod to be rejected.
- `audit`	- Policy violations will trigger the addition of an audit annotation to the event recorded in the audit log, but are otherwise allowed.
- `warn`	- Policy violations will trigger a user-facing warning, but are otherwise allowed.

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
2. Try to deploy a pod that runs as root (no `securityContext`) in `team-alpha` — observe the admission rejection message
  ```bash
    $ kubectl run nginx --image=nginx:1.25
    Warning: would violate PodSecurity "restricted:latest": allowPrivilegeEscalation != false (container "nginx" must set securityContext.allowPrivilegeEscalation=false), unrestricted capabilities (container "nginx" must set securityContext.capabilities.drop=["ALL"]),( runAsNcontainer "nginx" must set securityContext.seccompProfile.type to "RuntimeDefault" or "Localhost")
    pod/nginx created
  ```
# Pod is allowed to be created but with warnings, because restricted only has warn or audit mode, if it has enforce...the pod wont be created even

3. Deploy the same pod with a proper `securityContext` that satisfies `restricted`:
4. Leave `monitoring` namespace as `privileged` — understand why Prometheus node-exporter and some system tools legitimately need it

**Dig deeper:**
- What is the difference between `enforce`, `warn`, and `audit` modes?
**Answer**
  - enforce -> The API server rejects Pods that violate the selected Pod Security Standard.
  - warn -> The Pod is created, but Kubernetes prints a warning to the client.
  - audit -> The Pod is created without any warning to the user, but Kubernetes records the violation in its audit logs.

- Why did PodSecurityPolicy get removed and what problem did it cause that PSA solves?
**Answer**
  - PodSecurityPolicy (PSP) was removed because it was complex, difficult to configure, and often confusing to use. It required multiple resources (PSP, RBAC roles, and bindings), could mutate Pods by applying default values, and its policy selection behavior was not always intuitive. As a result, many Kubernetes users found it hard to manage and troubleshoot.

  - Pod Security Admission (PSA) was introduced as a simpler replacement. Instead of creating PSP objects, you enforce security by labeling namespaces with one of three predefined standards: Privileged, Baseline, or Restricted. PSA only validates Pods—it doesn't modify them—and supports three modes: enforce, warn, and audit. This makes Pod security easier to configure, more predictable, and consistent across clusters.

  - If organizations need more advanced or custom security policies beyond the predefined standards, they typically use policy engines like OPA Gatekeeper or Kyverno alongside PSA.

**You should know how to answer:**
**Answer**
- "How do you prevent developers from deploying root containers without trusting them to set securityContext themselves?"
  - Use Pod Security Admission (PSA) with the restricted profile in enforce mode. Apply the restricted policy at the namespace level using labels. The Kubernetes API server validates every Pod before creation. If a Pod tries to run as root or violates the required security settings, it is rejected automatically. This removes the need to trust developers to configure securityContext correctly.
  - For organization-specific rules beyond PSA (e.g., allowing only approved image registries or enforcing custom labels), use Kyverno or OPA Gatekeeper.

- What is the `restricted` PSA profile and what does it require on every pod?
**Answer**
  - restricted is the most secure built-in Pod Security Admission profile. It enforces Kubernetes security best practices by preventing privilege escalation and requiring Pods to run with minimal privileges.
  - The restricted profile enforces least privilege by ensuring Pods run as non-root, cannot gain extra privileges, use a secure seccomp profile, drop unnecessary capabilities, and avoid privileged or host-level access.

---

## Completion Checklist

Before moving to Task 02, you should be able to do all of these without looking at notes:

- [x] Create and label namespaces
- [x] Apply and inspect ResourceQuotas
- [x] Apply and test LimitRanges
- [x] Switch contexts and set default namespaces
- [x] Apply Pod Security Admission labels to enforce security profiles on namespaces
- [x] Explain to an interviewer why namespace isolation matters at a company level

---

## Interview Questions This Task Prepares You For

- "How do you manage resource fairness in a shared cluster?"
- "How do you handle multiple environments in K8s?"
- "Walk me through how you manage kubeconfig when dealing with multiple clusters."
- "What happens when a namespace is deleted?"
- "How do you enforce that no pod in a namespace can run as root, without relying on developers to set it?"
- "What replaced PodSecurityPolicy and how does it work?"

---

## Mini Project — Multi-Team Cluster Onboarding

> Estimated time: 1.5–2 hours. Put this in GitHub under `k8s-practice/task-01/`.

**Scenario:** You just joined a company as the DevOps engineer. A new project is starting with two teams — `team-alpha` (backend) and `team-beta` (frontend). Your job is to onboard them onto the shared cluster.

**Deliverables — you must produce all of these:**
1. A YAML file `namespaces.yaml` that creates both team namespaces with proper team labels
2. A YAML file `quotas.yaml` applying ResourceQuota to each namespace:
   - `team-alpha`: max 8 pods, 2 CPU, 4Gi memory
   - `team-beta`: max 6 pods, 1 CPU, 2Gi memory
3. A YAML file `limitranges.yaml` setting default pod limits for each namespace so devs who forget resource specs don't cause issues
  - Default CPU request: `100m`, limit: `500m`
  - Default memory request: `128Mi`, limit: `256Mi`
  - Min CPU: `50m`, Max CPU: `1`
4. A shell script `switch-context.sh` that takes a team name as argument and switches kubectl current context to that team's namespace
5. A `README.md` explaining: what you set up and why each decision was made

**Proof of completion:**
- `kubectl describe quota -n team-alpha` shows your quota applied
- `kubectl config current-context` changes when your script runs
- Deploy a pod that exceeds quota — screenshot the error

---

**Next: Task-02-Workloads.md**
