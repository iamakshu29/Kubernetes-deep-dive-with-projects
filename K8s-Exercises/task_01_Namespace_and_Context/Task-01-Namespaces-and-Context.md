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
echo "Context: $(kubectl config current-context), Namespace: $(kubectl config view --minify -o jsonpath='{..namespace}')"

# For alias
alias kctx='echo "Context: $(kubectl config current-context) | Namespace: $(kubectl config view --minify -o jsonpath="{..namespace}" 2>/dev/null || echo default)"'
```


**You should know how to answer:**
- What is the difference between a context, a cluster, and a user in kubeconfig? Why do we use context ?
ANS - NOTE - for above we use same cluster and create different context for it. but in real-time I dont think we do this we just use different context for different cluster..but still I dont understand why we are switching a complete cluster ...mostly we work between namespaces or nodes max to max but switching Cluster I didnt understand this functioning. (SEARCH FOR IT ALONG WITH ANSWERES)
- How do you prevent accidentally running `kubectl delete` on production?

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

---

## Exercise 6 — Pod Security Admission Standards

**Scenario:** Security team requires that `team-alpha` namespace enforces strict security posture — no root containers, no privilege escalation, no host namespaces. You must do this at the namespace level so it applies automatically to every pod deployed there, without relying on developers remembering to set `securityContext`.

**Background:** Pod Security Admission (PSA) is built into K8s 1.25+. It replaces the old PodSecurityPolicy. You label a namespace to enforce one of three profiles:
- `privileged` — no restrictions
- `baseline` — blocks the most dangerous settings
- `restricted` — enforced least-privilege (runs as non-root, no privilege escalation, seccomp applied)

**Your task:**
1. Label `team-alpha` to warn on `baseline` violations and enforce `restricted` profile:
   ```bash
   kubectl label namespace team-alpha \
     pod-security.kubernetes.io/enforce=restricted \
     pod-security.kubernetes.io/enforce-version=latest \
     pod-security.kubernetes.io/warn=baseline \
     pod-security.kubernetes.io/warn-version=latest
   ```
2. Try to deploy a pod that runs as root (no `securityContext`) in `team-alpha` — observe the admission rejection message
3. Deploy the same pod with a proper `securityContext` that satisfies `restricted`:
   ```yaml
   securityContext:
     runAsNonRoot: true
     runAsUser: 1000
     allowPrivilegeEscalation: false
     readOnlyRootFilesystem: true
     seccompProfile:
       type: RuntimeDefault
     capabilities:
       drop: ["ALL"]
   ```
4. Apply `baseline` enforcement to `team-beta` — observe the difference in what is and isn't allowed
5. Leave `monitoring` namespace as `privileged` — understand why Prometheus node-exporter and some system tools legitimately need it

**Dig deeper:**
- What is the difference between `enforce`, `warn`, and `audit` modes?
- Why did PodSecurityPolicy get removed and what problem did it cause that PSA solves?

**You should know how to answer:**
- "How do you prevent developers from deploying root containers without trusting them to set securityContext themselves?"
- What is the `restricted` PSA profile and what does it require on every pod?

---

## Completion Checklist

Before moving to Task 02, you should be able to do all of these without looking at notes:

- [ ] Create and label namespaces
- [ ] Apply and inspect ResourceQuotas
- [ ] Apply and test LimitRanges
- [ ] Switch contexts and set default namespaces
- [ ] Apply Pod Security Admission labels to enforce security profiles on namespaces
- [ ] Explain to an interviewer why namespace isolation matters at a company level

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
4. A shell script `switch-context.sh` (or PowerShell equivalent) that takes a team name as argument and switches kubectl context to that team's namespace
5. A `README.md` explaining: what you set up and why each decision was made

**Proof of completion:**
- `kubectl describe quota -n team-alpha` shows your quota applied
- `kubectl config current-context` changes when your script runs
- Deploy a pod that exceeds quota — screenshot the error

---

**Next: Task-02-Workloads.md**
