# Task 07 — ArgoCD: GitOps Continuous Deployment

> Real-world relevance: Every company running K8s at scale has moved away from Jenkins
> running `kubectl apply` directly. ArgoCD (or Flux) is now the standard. The model is
> pull-based — an agent inside the cluster watches Git and reconciles. Your build server
> never touches the cluster. Git is the source of truth. This is GitOps.
>
> This task covers ArgoCD end-to-end: install, core GitOps patterns, production-level
> features (App of Apps, sync waves, RBAC), multi-environment via ApplicationSet,
> and progressive delivery via Argo Rollouts.

> **Cluster needed:** kind 2-node or Oracle Free Tier — see **00-Setup.md**.
> ArgoCD requires at least 2GB RAM available in the cluster.
> Argo Rollouts (Exercise 9) additionally needs a working Ingress controller.

---

## What You Will Learn

- What GitOps is and why pull-based CD beats push-based
- Install and access ArgoCD
- Create and manage `Application` resources
- Auto-sync, self-heal, drift detection — the core GitOps loop
- The two-repo pattern — why app code and K8s manifests live in separate repos
- App of Apps — managing multiple apps through a single root Application
- Sync waves and resource hooks — controlling deploy order (DB migration before app)
- RBAC — giving teams access to their apps, nothing else
- ApplicationSet — generating Applications for multiple environments from one template
- Argo Rollouts — canary deployments with automatic promotion and rollback

---

## Background — Read Before Starting

### Push-based vs Pull-based CD

**Push-based (Jenkins runs `kubectl apply`):**
```
Jenkins → kubectl apply → cluster
```
- Build server needs cluster-admin credentials
- If Jenkins is compromised, the cluster is compromised
- Drift is invisible — no one tracks what's actually running vs what's in Git

**Pull-based (ArgoCD):**
```
Jenkins → git push → GitOps repo
                         ▲
                         |
                    ArgoCD watches
                         │
                    ArgoCD applies → cluster
```
- Build server never touches the cluster
- ArgoCD continuously compares Git (desired) vs cluster (actual) — drift is visible
- Rollback = `git revert` — no special tooling

### The Two-Repo Pattern

```
app-repo                          gitops-repo
┌──────────────────┐              ┌────────────────────────┐
│ src/             │  CI builds   │ k8s/                   │
│ Dockerfile       │ ──────────►  │   deployment.yaml      │
│ Jenkinsfile      │  updates tag │   service.yaml         │
│ terraform/       │              │   values-prod.yaml     │
└──────────────────┘              └────────────────────────┘
                                           ▲
                                           |
                                      ArgoCD watches
```

**Why two repos:**
- Separates CI concerns (build, test, scan) from CD concerns (what version runs where)
- Audit trail: every deployment is a Git commit
- Rollback without re-running CI: just revert the image tag commit in the GitOps repo

---

## Exercise 1 — Install ArgoCD and Explore the UI

```bash
# Create namespace and install ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for all pods to be ready
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=180s

# Get the initial admin password
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d && echo

# Port-forward the UI
kubectl port-forward svc/argocd-server -n argocd 8443:443
```

> Open `https://localhost:8443` — accept the self-signed cert warning. Login with `admin` and the password above.

**Install the ArgoCD CLI:**
```bash
# Linux/WSL
curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x /usr/local/bin/argocd
```

**Explore the UI:**
1. Look at the Applications page — it's empty, that's expected
2. Go to Settings → Repositories — this is where you connect Git repos
3. Go to Settings → Clusters — your local cluster is already registered as `in-cluster`

**Understand `in-cluster`:** When ArgoCD runs inside the cluster it wants to manage, it authenticates using its own ServiceAccount — no external credentials needed. For managing external clusters, you'd add them explicitly.

---

## Exercise 2 — Your First Application (Manual Sync)

You need a Git repo with K8s manifests. Use your existing `gitops-repo` from the Pipeline project, or create a new public repo with this structure:

```
k8s/
  namespace.yaml
  deployment.yaml
  service.yaml
```

**Create the ArgoCD Application manifest** (the GitOps way — apply a YAML, don't click the UI):

```yaml
# argocd-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: sample-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/gitops-repo.git
    targetRevision: main
    path: k8s/
  destination:
    server: https://kubernetes.default.svc
    namespace: sample-app
  syncPolicy: {}   # manual sync — ArgoCD detects drift but does not auto-apply
```

```bash
kubectl apply -f argocd-app.yaml
```

**Login to the ArgoCD CLI and check the status:**
```bash
# Login via CLI
argocd login localhost:8443 --username admin --insecure

# Check the app status
argocd app get sample-app
```

Status will show `OutOfSync` — ArgoCD has compared Git to the cluster and found the resources don't exist yet.

**Manually sync:**
```bash
argocd app sync sample-app
# or: kubectl -n argocd patch app sample-app --type merge -p '{"operation":{"sync":{}}}'
```

Verify:
```bash
kubectl get all -n sample-app
argocd app get sample-app   # should now show Synced + Healthy
```

**Key concept — the difference between Synced and Healthy:**
- `Synced` — the cluster matches Git (correct manifest applied)
- `Healthy` — the resource is actually working (pod is Running, Deployment has desired replicas)
- An app can be Synced but Unhealthy (manifest applied but pod is CrashLoopBackOff)

---

## Exercise 3 — Auto-Sync, Drift Detection, and Self-Heal

**Enable auto-sync and self-heal:**

```yaml
# Update argocd-app.yaml syncPolicy section
syncPolicy:
  automated:
    prune: true       # delete resources removed from Git
    selfHeal: true    # revert manual cluster changes back to Git state
  syncOptions:
    - CreateNamespace=true
```

```bash
kubectl apply -f argocd-app.yaml
```

**Test drift detection — manually scale the Deployment:**
```bash
kubectl scale deployment sample-app -n sample-app --replicas=5
kubectl get deployment sample-app -n sample-app  # shows 5 replicas

# Wait ~30 seconds (ArgoCD reconciliation interval)
kubectl get deployment sample-app -n sample-app  # back to 2 — ArgoCD reverted it
```

**Observe in the UI:** Settings → Applications → sample-app → Events tab. You'll see ArgoCD log the drift and correction.

**Test prune — delete a resource from Git:**
1. Delete `service.yaml` from your Git repo and commit
2. Wait for ArgoCD to detect the commit
3. The Service in the cluster is deleted automatically (`prune: true`)

Without `prune: true`, deleted manifests in Git leave orphaned resources in the cluster forever — a common source of cluster clutter.

**Test CreateNamespace=true:**
Remove the `namespace.yaml` from Git and rely on the `CreateNamespace=true` syncOption. ArgoCD will create the namespace itself if it doesn't exist.

---

## Exercise 4 — The Two-Repo Pattern in Practice

This exercise connects ArgoCD to the output of a Jenkins pipeline.

**Scenario:** Jenkins builds, scans, and pushes a new image to Nexus. It commits the updated image tag to the GitOps repo. ArgoCD detects the commit and deploys.

**The Jenkins `Update GitOps Repo` stage** (from `09_ArgoCD/tasks.md` in the Pipeline folder) commits a change like:
```yaml
# Before
image: nexus:8082/sample-app:41
# After
image: nexus:8082/sample-app:42
```

**Simulate this from the command line:**
```bash
# Clone your gitops repo
git clone https://github.com/your-org/gitops-repo.git
cd gitops-repo

# Update the image tag (simulating what Jenkins does)
sed -i 's|image: nginx:1.25|image: nginx:1.26|' k8s/deployment.yaml
git commit -am "ci: update image to nginx:1.26"
git push
```

Watch ArgoCD in the UI — within 3 minutes (default poll interval) it detects the commit and syncs. The Deployment rolls out the new image.

**Speed up detection with a webhook (optional but worth knowing):**
GitHub → Settings → Webhooks → Add webhook:
- URL: `https://<argocd-server>/api/webhook`
- Content type: `application/json`
- Events: Just the push event

With a webhook, ArgoCD syncs within seconds of a push instead of waiting for the poll interval.

---

## Exercise 5 — App of Apps Pattern

**Problem it solves:** You have 10 microservices. Do you create 10 ArgoCD Application manifests by hand? And who manages those Application manifests — are they also in Git?

**The pattern:** One root Application in ArgoCD points to a Git directory that contains only Application manifests. ArgoCD applies those Applications, which in turn sync their own resources.

```
root-app (ArgoCD Application)
  └── points to: gitops-repo/apps/
          ├── frontend-app.yaml    (Application manifest)
          ├── backend-app.yaml     (Application manifest)
          ├── database-app.yaml    (Application manifest)
          └── monitoring-app.yaml  (Application manifest)
```

**Set it up:**

Create `apps/` directory in your gitops repo:

```yaml
# apps/sample-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: sample-app
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io  # deletes app resources when Application is deleted
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/gitops-repo.git
    targetRevision: main
    path: k8s/
  destination:
    server: https://kubernetes.default.svc
    namespace: sample-app
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

```yaml
# root-app.yaml (apply this once to bootstrap)
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/gitops-repo.git
    targetRevision: main
    path: apps/
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

```bash
kubectl apply -f root-app.yaml
```

**Now to add a new application to the cluster:** add a YAML file to `apps/` in Git and push. ArgoCD picks it up through the root app — no `kubectl apply` needed on your machine.

**The finalizer explained:** `resources-finalizer.argocd.argoproj.io` means when you delete an Application in ArgoCD, it also deletes all the K8s resources that Application manages. Without it, deleting the Application leaves orphaned pods, services, etc.

---

## Exercise 6 — Sync Waves and Resource Hooks

**Problem:** Your app depends on a database. If ArgoCD applies everything at once, the app pods start before the DB is ready and crash. You need ordering.

**Sync waves** control the order in which resources are applied. Lower wave number = applied first. ArgoCD waits for each wave to be healthy before starting the next.

```yaml
# database/deployment.yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "1"   # applied first

# database/service.yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "1"

# app/deployment.yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "2"   # applied after wave 1 is healthy
```

**Resource hooks** run at specific points in the sync lifecycle:

| Hook | When it runs |
|------|-------------|
| `PreSync` | Before any resource is applied — use for DB migrations |
| `Sync` | During the sync (same as no hook) |
| `PostSync` | After all resources are Healthy — use for smoke tests |
| `SyncFail` | If the sync fails — use for cleanup or notifications |

**DB migration Job with PreSync hook:**
```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: db-migrate
  annotations:
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded  # delete Job after it completes
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: migrate
          image: nexus:8082/sample-app:42
          command: ["python", "manage.py", "migrate"]
```

**What to do:**
1. Add sync wave annotations to your deployment and service YAML — DB on wave 1, app on wave 2
2. Add the PreSync migration Job to your gitops repo
3. Commit and push — observe in the ArgoCD UI that resources apply in the correct order
4. Intentionally break the migration Job (bad command) — observe ArgoCD stop before applying the app

---

## Exercise 7 — RBAC

ArgoCD RBAC controls who can see and sync which applications. Default: all logged-in users are read-only. Admins can sync anything.

**Roles and policies** are stored in a ConfigMap:

```bash
kubectl edit configmap argocd-rbac-cm -n argocd
```

```yaml
data:
  policy.default: role:readonly   # all authenticated users get read-only by default
  policy.csv: |
    # team-alpha members can sync apps in the team-alpha project
    p, role:team-alpha-deployer, applications, sync, team-alpha/*, allow
    p, role:team-alpha-deployer, applications, get, team-alpha/*, allow

    # bind the role to a specific user
    g, alice@example.com, role:team-alpha-deployer

    # admins can do everything
    g, admin, role:admin
```

**Create an AppProject to scope what a team can deploy:**

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: team-alpha
  namespace: argocd
spec:
  description: Team Alpha applications
  sourceRepos:
    - https://github.com/your-org/gitops-repo.git   # only this repo allowed
  destinations:
    - namespace: team-alpha                           # only this namespace
      server: https://kubernetes.default.svc
  clusterResourceWhitelist:
    - group: ''
      kind: Namespace                                 # team can create namespaces
  namespaceResourceBlacklist:
    - group: ''
      kind: ResourceQuota                             # team cannot modify quotas
```

**What to do:**
1. Create the `team-alpha` AppProject
2. Create a second Application using project `team-alpha` instead of `default`
3. Update the RBAC ConfigMap to allow a test user to sync only team-alpha apps
4. Verify: `argocd app list` — see that apps outside team-alpha are read-only for that user

---

## Exercise 8 — ApplicationSet: Multi-Environment from One Template

**Problem:** You have three environments (dev, staging, prod). Without ApplicationSet you write three nearly-identical Application manifests. With ApplicationSet, you write one template and a generator produces all three.

**List generator** — hardcode the environments:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: sample-app-envs
  namespace: argocd
spec:
  generators:
    - list:
        elements:
          - env: dev
            namespace: sample-app-dev
            values_file: values-dev.yaml
          - env: staging
            namespace: sample-app-staging
            values_file: values-staging.yaml
          - env: prod
            namespace: sample-app-prod
            values_file: values-prod.yaml
  template:
    metadata:
      name: 'sample-app-{{env}}'
    spec:
      project: default
      source:
        repoURL: https://github.com/your-org/gitops-repo.git
        targetRevision: main
        path: helm/sample-app
        helm:
          valueFiles:
            - '{{values_file}}'
      destination:
        server: https://kubernetes.default.svc
        namespace: '{{namespace}}'
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
```

```bash
kubectl apply -f applicationset.yaml

# Three Applications are created automatically
argocd app list
```

**Git generator** — create one Application per directory found in Git (no hardcoding):

```yaml
generators:
  - git:
      repoURL: https://github.com/your-org/gitops-repo.git
      revision: main
      directories:
        - path: apps/*   # creates one Application per subdirectory under apps/
```

**What to do:**
1. Create three `values-dev/staging/prod.yaml` files in your Helm chart with different replica counts and image tags
2. Apply the ApplicationSet
3. Verify three Applications appear in ArgoCD UI
4. Change a value in `values-dev.yaml` — confirm only the dev Application syncs
5. Delete one environment directory from Git — confirm ArgoCD prunes that Application

---

## Exercise 9 — Argo Rollouts: Canary Deployments

Argo Rollouts is a separate controller (not part of ArgoCD itself) that replaces the standard Kubernetes Deployment for progressive delivery. It adds canary and blue-green rollout strategies.

**Why canary:**
A standard Kubernetes rolling update replaces all pods with the new version. If the new version has a bug, all users are affected before you catch it. Canary sends a small percentage of traffic to the new version first, monitors metrics, and only promotes if healthy.

**Install Argo Rollouts:**
```bash
kubectl create namespace argo-rollouts
kubectl apply -n argo-rollouts -f \
  https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml

# Install the kubectl plugin
curl -LO https://github.com/argoproj/argo-rollouts/releases/latest/download/kubectl-argo-rollouts-linux-amd64
chmod +x kubectl-argo-rollouts-linux-amd64
sudo mv kubectl-argo-rollouts-linux-amd64 /usr/local/bin/kubectl-argo-rollouts
```

**Replace your Deployment with a Rollout:**

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: sample-app
  namespace: sample-app
spec:
  replicas: 5
  selector:
    matchLabels:
      app: sample-app
  template:
    metadata:
      labels:
        app: sample-app
    spec:
      containers:
        - name: app
          image: nginx:1.25
          ports:
            - containerPort: 80
  strategy:
    canary:
      steps:
        - setWeight: 20        # send 20% of traffic to new version
        - pause: {duration: 30s}  # wait 30 seconds (in prod: wait for metrics)
        - setWeight: 50        # increase to 50%
        - pause: {duration: 30s}
        - setWeight: 100       # full rollout
      # canaryService and stableService are required for proper traffic splitting
      canaryService: sample-app-canary
      stableService: sample-app-stable
```

**Trigger a canary rollout:**
```bash
# Update the image
kubectl argo rollouts set image rollout/sample-app app=nginx:1.26 -n sample-app

# Watch the rollout progress
kubectl argo rollouts get rollout sample-app -n sample-app --watch
```

**Manually abort a rollout** (simulate catching a bad deploy at 20%):
```bash
kubectl argo rollouts abort rollout/sample-app -n sample-app
# Traffic returns 100% to stable version
```

**Manually promote** (skip pause and proceed to 100%):
```bash
kubectl argo rollouts promote rollout/sample-app -n sample-app
```

**ArgoCD + Argo Rollouts together:**
ArgoCD manages the Rollout manifest from Git the same way it manages Deployments. The Rollout controller handles the traffic splitting. They work independently — ArgoCD syncs the manifest, Rollouts executes the strategy.

---

## Mini Project — Full GitOps Setup

Wire everything from this task together:

1. **GitOps repo structure:**
   ```
   gitops-repo/
     apps/                      ← App of Apps root
       sample-app-dev.yaml
       sample-app-prod.yaml
     helm/sample-app/           ← Helm chart
       templates/
       values.yaml
       values-dev.yaml
       values-prod.yaml
     migrations/
       db-migrate-job.yaml      ← PreSync hook
   ```

2. **Deploy the root app** pointing to `apps/` → it creates dev and prod Applications

3. **Add sync waves:** DB migration Job (wave 1, PreSync hook) → Deployment (wave 2)

4. **Add RBAC:** Create an AppProject that restricts the dev Application to the `sample-app-dev` namespace only

5. **Trigger a pipeline deploy:** Update the image tag in `values-prod.yaml` via a Git commit. Watch ArgoCD sync the prod Application. Verify the new image is running.

6. **Test rollback:** Revert the image tag commit in Git. ArgoCD syncs back to the previous image — no `kubectl rollout undo` needed.

**Deliverables:**
- Screenshot of ArgoCD UI showing both dev and prod Applications in Synced + Healthy state
- Screenshot of the App of Apps view
- `apps/` directory and Helm chart committed to your GitHub gitops repo

---

## Interview Questions

**Q: What is GitOps and how is it different from traditional CD?**
A: GitOps is a practice where the desired state of infrastructure and deployments is stored in Git and an automated agent continuously reconciles the live system to match Git. Traditional CD is push-based — the CI server (Jenkins) directly applies changes to the cluster using `kubectl` or Helm, requiring cluster credentials on the build server. GitOps is pull-based — the agent (ArgoCD) runs inside the cluster, watches Git, and pulls changes. The build server never touches the cluster.

**Q: What is drift and how does ArgoCD handle it?**
A: Drift is when the live cluster state diverges from what's in Git — someone ran `kubectl edit` or `kubectl scale` manually. ArgoCD continuously compares the desired state (Git) with the live state (cluster). With `selfHeal: true`, it automatically reverts any drift back to Git state within the reconciliation interval (default 3 minutes or immediately via webhook).

**Q: What does `prune: true` do and why would you NOT set it?**
A: `prune: true` tells ArgoCD to delete cluster resources that no longer exist in Git. You would NOT set it in environments where some resources are managed outside Git (e.g., auto-created PVCs, CRDs installed by other tools). In those cases, pruning would delete resources ArgoCD doesn't own, causing outages.

**Q: How do you deploy to multiple environments without duplicating Application manifests?**
A: Use `ApplicationSet` with a generator. A list generator hardcodes environments; a Git generator auto-discovers them from directory structure. The template section defines the Application shape with `{{placeholder}}` variables that the generator fills in per environment.

**Q: What are sync waves and when do you use them?**
A: Sync waves assign an order to resources. ArgoCD applies lower-numbered waves first and waits for them to be healthy before proceeding to the next wave. Use them when resources have dependencies — a DB migration Job in wave 1, the application Deployment in wave 2. Without waves, ArgoCD applies everything in parallel and your app pod may crash because the DB isn't ready yet.

**Q: What is the difference between a PreSync hook and sync wave 1?**
A: Sync waves order the application of resources. A PreSync hook runs before any sync wave begins. Use a PreSync hook for operations that must complete before any resource is touched — DB schema migrations, validation scripts. Use sync waves for ordering the apply of K8s resources relative to each other.

**Q: How does ArgoCD handle rollback?**
A: The GitOps way: `git revert` the commit that introduced the change, push to Git, ArgoCD detects the revert and syncs the previous state. The cluster-direct way: ArgoCD UI → App → History → select a previous sync → Rollback (this syncs from a cached previous manifest, not the current Git HEAD — it creates drift until Git catches up).

**Q: What is the App of Apps pattern?**
A: A root ArgoCD Application that points to a Git directory containing only Application manifests. ArgoCD applies those manifests, creating child Applications. This means adding a new application to the cluster is just adding a YAML file to Git — no direct ArgoCD access needed. The entire Application configuration is version-controlled.

**Q: What is a canary deployment and how does Argo Rollouts implement it?**
A: A canary deployment routes a small percentage of traffic to a new version while the stable version serves the rest. If the canary shows no errors, traffic gradually shifts to 100%. Argo Rollouts replaces the standard Deployment with a `Rollout` resource that has a `canary` strategy. It manages stable and canary Services, stepping traffic weight through configured percentages with pause intervals between steps. If you abort, all traffic returns to the stable version immediately.

**Q: ArgoCD vs Flux — when would you choose one over the other?**
A: ArgoCD has a richer UI, multi-cluster support from a central control plane, and the App of Apps pattern for managing many applications. Flux is more lightweight, follows a stricter GitOps model (everything is managed via CRDs, no central UI), and integrates natively with tools like Flagger for progressive delivery. ArgoCD is more common in multi-team environments where visibility matters. Flux is preferred in teams that want minimal operational overhead and strict GitOps discipline.

---

## Beyond This Task — Deeper Concepts

What this task covers is sufficient for standard DevOps/Platform Engineering work. The following topics go deeper and are relevant when operating ArgoCD at larger scale.

| Concept | What it does |
|---|---|
| **ArgoCD Image Updater** | Watches a container registry for new image tags and automatically commits the updated tag to the GitOps repo — removes the `Update GitOps Repo` Jenkins stage entirely |
| **ApplicationSet — Git generator** | Auto-creates one Application per directory or file found in a Git repo — no need to list environments manually; adding a new env is just adding a folder to Git |
| **ApplicationSet — Cluster generator** | Creates one Application per registered cluster — used when ArgoCD manages deployments across many clusters from a single control plane |
| **ApplicationSet — Matrix generator** | Combines two generators (e.g. cluster × environment) to produce the cartesian product — one Application per cluster/env combination from one template |
| **ArgoCD Notifications controller** | Sends Slack/Teams/PagerDuty alerts on sync success, failure, health degradation — separate controller, configured via ConfigMaps |
| **Multi-cluster management** | ArgoCD acts as a hub managing multiple target clusters (dev cluster, prod cluster, DR cluster) — each cluster is registered and Applications are targeted at specific clusters |
| **ArgoCD + Vault (ESO / AVSO)** | Secrets cannot be stored in Git. External Secrets Operator (ESO) or ArgoCD Vault Plugin (AVSO) pulls secrets from Vault at sync time and injects them as K8s Secrets — keeps Git clean of sensitive values |
| **Argo Rollouts — Blue/Green** | Runs old and new version simultaneously on separate Services; switches traffic instantly with a single cutover rather than gradually — lower complexity than canary, instant rollback |
| **Argo Rollouts — Analysis templates** | Automatically queries Prometheus metrics (error rate, latency) during a canary step; promotes or aborts based on metric thresholds without human intervention |
| **Argo CD Disaster Recovery** | Backing up and restoring ArgoCD state (all Application and AppProject CRDs) using `argocd-disaster-recovery` or Velero — important when the argocd namespace itself is lost |
| **ArgoCD API / CLI automation** | Scripting Application creation, sync triggering, and status checks via the ArgoCD REST API or CLI — used in pipelines that need to wait for a sync to complete before running tests |
