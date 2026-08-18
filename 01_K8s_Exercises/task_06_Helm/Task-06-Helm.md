# Task 06 — Helm: Packaging and Deploying Applications at Scale

> Real-world relevance: No company deploys raw kubectl YAML at scale. Helm is the
> standard way to package, version, and deploy K8s applications — and to manage
> environment differences (dev vs staging vs prod) without duplicating YAML everywhere.
> You will use Helm in Task 06 (monitoring stack), Task 07 (ArgoCD), and Task 08 (final project).
> Do this task before those three.

> **Cluster needed:** kind single-node or 2-node — see **00-Setup.md Option A1**.
> No special add-ons required beyond a running cluster and Helm installed.

---

## What You Will Learn

- What Helm solves and why raw YAML breaks down at scale
- Chart structure — how a Helm chart is organised
- Templates — writing parameterised K8s manifests
- Values — how you customise charts per environment without touching templates
- Release lifecycle — install, upgrade, rollback, uninstall
- Helm in a CI/CD pipeline — the pattern every company uses
- Chart repositories and using community charts (like kube-prometheus-stack)
- Debugging Helm: `helm template`, `helm diff`, `helm lint`

---

## Background — Read Before Starting

Without Helm, you have folders of YAML for each environment:

```
manifests/
  dev/    → deployment.yaml, service.yaml, configmap.yaml
  staging → deployment.yaml, service.yaml, configmap.yaml (mostly same, different values)
  prod    → deployment.yaml, service.yaml, configmap.yaml (mostly same, different values)
```

Any change has to be made in 3 places. Values like image tag, replica count, resource limits, and hostnames are duplicated everywhere.

With Helm:

```
charts/podinfo-app/       → one set of templates
  values.yaml           → defaults
  values-dev.yaml       → overrides for dev
  values-staging.yaml   → overrides for staging
  values-prod.yaml      → overrides for prod
```

CI/CD runs `helm upgrade --install podinfo-app ./charts/podinfo-app -f values-prod.yaml --set image.tag=$GIT_SHA`. Done.

---

## Exercise 1 — Install Helm and Understand Chart Structure

**Install Helm on Windows:**

```powershell
choco install kubernetes-helm
# or
winget install Helm.Helm

helm version   # verify
```

**Explore an existing chart before building your own:**

```bash
# Add the bitnami repo (contains well-maintained charts for common apps)
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# Search for nginx
helm search repo nginx

# Pull the chart without installing to inspect its structure
helm pull bitnami/nginx --untar
ls nginx/
```

**Your task:**

1. Inspect the pulled `nginx/` chart structure — understand each directory and file:
   ```
   nginx/
     Chart.yaml          → chart metadata (name, version, appVersion)
     values.yaml         → default values
     templates/          → K8s YAML templates with {{ }} placeholders
     templates/NOTES.txt → printed after install (helpful for users)
     charts/             → sub-charts (dependencies)
   ```
2. Open `templates/deployment.yaml` — find where `{{ .Values.replicaCount }}` appears and trace it back to `values.yaml`
3. Run `helm template nginx ./nginx` — this renders all templates with default values WITHOUT installing anything. Use this to preview exactly what YAML will be applied to the cluster.

---

## Exercise 2 — Install and Manage a Release

**Your task:**

1. Install the nginx chart into namespace `team-alpha`:
   ```bash
   helm install alpha-web bitnami/nginx \
     --namespace team-alpha \
     --create-namespace \
     --set replicaCount=2
   ```
2. List all Helm releases:
   ```bash
   helm list -A
   ```
3. Check the release status:
   ```bash
   helm status alpha-web -n team-alpha
   ```
4. Upgrade the release — change replica count to 3:
   ```bash
   helm upgrade alpha-web bitnami/nginx -n team-alpha --set replicaCount=3
   ```
5. Check rollout history:
   ```bash
   helm history alpha-web -n team-alpha
   ```
6. Rollback to revision 1:
   ```bash
   helm rollback alpha-web 1 -n team-alpha
   ```
7. Uninstall the release completely:
   ```bash
   helm uninstall alpha-web -n team-alpha
   ```

**You should know how to answer:**

- Where does Helm store release state? (hint: as Secrets in the release namespace — check `kubectl get secret -n team-alpha | grep helm`)
  - Helm stores every release revision as a **Kubernetes Secret** in the release's namespace. Each Secret is named `sh.helm.release.v1.<release-name>.v<revision>` and contains the full rendered manifest + metadata, base64-encoded. This means: no external database needed, release history travels with the cluster, and deleting those Secrets wipes Helm's memory of the release.
  - `kubectl get secret -n team-alpha | grep helm` → shows one Secret per revision.

- What is a Helm revision?
  - Every `helm install` creates revision 1. Every `helm upgrade` increments it (revision 2, 3, ...). Every `helm rollback` also creates a new revision (it does NOT rewrite history — it adds a new revision that re-applies an older manifest). `helm history <release>` shows the full revision log with timestamps, chart version, and status.

---

## Exercise 3 — Build Your Own Chart from Scratch

**Scenario:** You are packaging `team-alpha`'s API (the one from Task 02) as a Helm chart so it can be deployed to dev, staging, and prod with different configurations.

**Your task:**

### Step 1 — Create the chart scaffold:

```bash
helm create alpha-api
ls alpha-api/
```

This generates a chart with example templates. You will replace them.

### Step 2 — Clean out the generated templates:

```bash
rm -rf alpha-api/templates/*
rm alpha-api/templates/.helmignore
```

### Step 3 — Write the templates

**`alpha-api/templates/api-deployment.yaml`:**
**`alpha-api/templates/redis-deployment.yaml`:**
**`alpha-api/templates/service.yaml`:**
**`alpha-api/templates/hpa.yaml`:**
**`alpha-api/templates/pdb.yaml`:**

### Step 4 — Write the default values

**`alpha-api/values.yaml`:**

### Step 5 — Create environment-specific override files

**`values-dev.yaml`:**
**`values-prod.yaml`:**

### Step 6 — Lint, render, and deploy

```bash
# Check chart for errors
helm lint alpha-api/

# Preview what YAML will be created (dry run — does not touch cluster)
helm template alpha-api alpha-api/ -n team-alpha > final.yml

# Install chart
  # with default values.yml
  helm install alpha-api alpha-api/ -n team-alpha --create-namespace
  # with values-dev.yml
  helm install alpha-api-dev alpha-api/ -f alpha-api/values-dev.yaml -n dev-env --create-namespace
  # with values-prod.yml
  helm install alpha-api-prod alpha-api/ -f alpha-api/values-prod.yaml -n prod-env --create-namespace

# Verify
kubectl get deploy,svc,hpa -n team-alpha

# Upgrade dev with a new image tag (simulating CI/CD)
helm upgrade alpha-api-dev alpha-api/ -f alpha-api/values-dev.yaml --set backend.image.tag="1.0.0" -n dev-env

# Upgrade dev with a new arg version v1 -> v2
helm upgrade --install alpha-api-dev alpha-api/ \
-f alpha-api/values-dev.yaml \
--set-string backend.args[0]='-text="Hello from alpha-api Prod Environment v2"' \
-n dev-env
```

#### NOTES

- As alpha-pod project contains `PDB` as `minAvailable: 1` on redis-check (Backend)
- When we upgrade to newer version. It will not show it. As the earlier Pods are still in Pending State.
- Remove the Old Pods to get one of the new Pending Pod becomes running and ready.

#### To verify

```bash
    # Port forward Pod on port 5678
    kubectl port-forward <pod_name> 5678:5678 -n dev-env
```

### Step 5 — Check History, Rollback the Release

```bash
    # Check history for dev-env
    helm history alpha-api-dev -n dev-env

    # Rollback to previous version and revalidate.
    helm rollback alpha-api-dev 1 -n dev-env

      # This will create another version
      helm history alpha-api-dev -n dev-env
```

### Step 6 — Uninstall the Release

```bash
    helm uninstall alpha-api-dev -n dev-env
```

**Requirements met by this chart:**

- `image.tag` overridable at deploy time via `--set backend.image.tag=$GIT_SHA`
- HPA conditionally rendered — enabled in prod values, disabled in dev values
- Redis deployment conditional via `redis.enabled: true/false`
- All resource limits configurable via values
- Chart passes `helm lint` with zero warnings
- Pre-upgrade migration hook (Exercise 4) runs before new pods roll out

**Proof of completion:**

```bash
# Dev deploy
helm install alpha-api-dev alpha-api/ -f alpha-api/values-dev.yaml -n dev-env --dry-run
helm install alpha-api-dev alpha-api/ -f alpha-api/values-dev.yaml -n dev-env --create-namespace

# Prod deploy
helm install alpha-api-prod alpha-api/ -f alpha-api/values-prod.yaml -n prod-env --create-namespace

# CI/CD pattern — idempotent, auto-rollback on failure, waits for pods ready
helm upgrade --install alpha-api-prod alpha-api/ -f alpha-api/values-prod.yaml \
  --set backend.image.tag=v2 -n prod-env --rollback-on-failure --wait

helm history alpha-api-prod -n prod-env
```

- Show the pre-upgrade hook Job appears and completes before new pods roll out (`kubectl get jobs -n dev-env -w` during upgrade)
- Port-forward and hit the endpoint to confirm v1 → v2 change
- `helm rollback alpha-api-prod 1 -n prod-env` and verify app returns to v1

**You should know how to answer:**

- "How do you pass a value that overrides `values.yaml` at deploy time?" (hint: `--set key=value`)
  - `--set key=value` on the command line: `helm upgrade alpha-api ./alpha-api --set image.tag=abc1234`. For nested keys: `--set backend.image.tag=abc1234`. For multiple values: chain multiple `--set` flags. For values with special characters: use `--set-string`.
- "Which takes precedence — `values.yaml`, `-f values-prod.yaml`, or `--set`?" (answer: `--set` > `-f file` > `values.yaml`)
  - **`values.yaml`** — chart defaults, lowest priority
  - **`-f values-prod.yaml`** — environment overrides, middle priority (later `-f` files override earlier ones)
  - **`--set`** — CLI overrides, highest priority; always wins

---

## Helm Template Reference — Built-in Objects and `_helpers.tpl`

### Built-in Objects (not `.Values`)

Every Helm template has access to several built-in top-level objects injected by Helm at render time:

| Object                            | What it gives you                           | Example          |
| --------------------------------- | ------------------------------------------- | ---------------- |
| `.Release.Name`                   | The release name passed to `helm install`   | `alpha-api-dev`  |
| `.Release.Namespace`              | Namespace the release is deployed into      | `dev-env`        |
| `.Release.IsInstall`              | `true` on first install, `false` on upgrade | useful in hooks  |
| `.Release.IsUpgrade`              | `true` on upgrade                           | useful in hooks  |
| `.Chart.Name`                     | Name field from `Chart.yaml`                | `alpha-api`      |
| `.Chart.Version`                  | Chart version from `Chart.yaml`             | `0.1.0`          |
| `.Chart.AppVersion`               | AppVersion from `Chart.yaml`                | `1.0.0`          |
| `.Files.Get "config.ini"`         | Read a non-template file from the chart     | raw file content |
| `.Capabilities.KubeVersion.Minor` | K8s minor version of the target cluster     | `28`             |

**Usage in a template:**

```yaml
metadata:
  name: {{ .Release.Name }}-api          # → alpha-api-dev-api
  namespace: {{ .Release.Namespace }}    # → dev-env
  labels:
    app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
    helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
```

---

### `_helpers.tpl` — Reusable Named Templates

`_helpers.tpl` is a special file in `templates/`. Files starting with `_` are **never rendered as K8s manifests** — they exist only to define reusable template functions called with `{{- include }}` or `{{- template }}`.

**Why use it:** instead of copy-pasting the same labels block into every template, define it once and include it everywhere.

**Step 1 — Define a helper in `_helpers.tpl`:**

```yaml
{{/*
Common labels applied to all resources in this chart.
*/}}
{{- define "alpha-api.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}

{{/*
Selector labels — used in matchLabels and pod template labels.
Keep these stable; changing them breaks rolling updates.
*/}}
{{- define "alpha-api.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Full name helper — trims to 63 chars (K8s DNS limit).
*/}}
{{- define "alpha-api.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
```

**Step 2 — Use it in any template with `include`:**

```yaml
# In templates/deployment.yaml
metadata:
  name: {{ include "alpha-api.fullname" . }}-api    # → alpha-api-dev-alpha-api-api
  labels:
    {{- include "alpha-api.labels" . | nindent 4 }}  # indents the block 4 spaces
spec:
  selector:
    matchLabels:
      {{- include "alpha-api.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "alpha-api.selectorLabels" . | nindent 8 }}
```

**`include` vs `template`:**

- `{{- include "name" . }}` — returns the output as a string, so you can pipe it through `| nindent 4` or `| quote`. **Always use `include`.**
- `{{- template "name" . }}` — renders in-place, no piping possible. Older style, avoid.

**The `.` argument** — passing context:

- `.` = the current context (has `.Values`, `.Release`, `.Chart`, etc.)
- Always pass `.` when calling a helper so it can access those objects inside the function
- If you need to pass a subset: `{{- include "alpha-api.labels" (dict "Release" .Release "Chart" .Chart) }}`

**`nindent` vs `indent`:**

- `nindent N` = adds a newline first, then indents N spaces — use this inside blocks
- `indent N` = indents only, no leading newline — use this at the start of a file

---

### `NOTES.txt` — Post-Install User Output

`NOTES.txt` is another special file in `templates/`. Like `_helpers.tpl`, it is **never applied to the cluster as a K8s manifest**. Instead, Helm renders it as a Go template and prints the result to the terminal after every `helm install` or `helm upgrade`. It is purely user-facing output.

**What makes it special:**

- Full `{{ }}` Go template syntax works inside it (`.Values`, `.Release`, `.Chart`, `if/else`, etc.)
- Nothing in it is sent to Kubernetes
- It is the standard way to tell the user how to access their app after deployment

**Example `templates/NOTES.txt`:**

```
Release "{{ .Release.Name }}" deployed to namespace "{{ .Release.Namespace }}".

Access: https://{{ .Values.appName }}.local

{{- if .Values.app.autoscaling.enabled }}
HPA enabled — scaling between {{ .Values.app.autoscaling.minReplicas }} and {{ .Values.app.autoscaling.maxReplicas }} replicas.
{{- else }}
HPA disabled — running {{ .Values.app.replicas }} replica(s).
{{- end }}
```

**What the user sees after `helm install`:**

```
NOTES:
Release "petclinic" deployed to namespace "petclinic-dev".
Access: https://petclinic.local
HPA disabled — running 2 replica(s).
```

**Show it again anytime:**

```bash
helm get notes <release-name> -n <namespace>
```

---

## Exercise 4 — Helm Hooks (Pre/Post Install Jobs)

**Scenario:** Before deploying a new version of the API, you need to run a database migration. This must complete successfully before the new pods start. Helm hooks let you run Jobs at specific points in the release lifecycle.

**Your task:**

1. Create `alpha-api/templates/migrate-job.yaml`:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ .Values.hooks.migrate.name }}-migrate-{{ .Values.hooks.migrate.revision }}
  annotations:
    "helm.sh/hook": pre-upgrade,pre-install
    "helm.sh/hook-weight": "-5"
    "helm.sh/hook-delete-policy": hook-succeeded
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: migrate
        image: busybox
        command: ["/bin/sh", "-c", "echo 'Running DB migration...'; sleep 3; echo 'Done'"]
```

2. Run `helm install alpha-api-dev alpha-api/ -f alpha-api/values-dev.yaml -n dev-env --create-namespace`
3. Run `helm upgrade alpha-api-dev alpha-api/ -f alpha-api/values-dev.yaml -n dev-env`
4. Watch: the Job runs first, completes, THEN the Deployment rolls out

```bash
    # In another terminal check, while upgrading.
    # as delete-policy: hook-succeeded i.e the job will delete on succeeds
    kubectl get jobs -A -w
```

4. Set the migration to fail (`exit 1`) — observe that the upgrade is blocked

**Key hook annotations:**
| Annotation | Meaning |
| ----------------------------------------------| ------------------------------------------------|
| `helm.sh/hook: pre-install` | Run before resources are installed |
| `helm.sh/hook: pre-upgrade` | Run before an upgrade |
| `helm.sh/hook: post-install` | Run after all resources are ready |
| `helm.sh/hook-delete-policy: hook-succeeded` | Delete the Job after it succeeds |
| `helm.sh/hook-weight: "-5"` | Run this hook before hooks with higher weights |

---

## Exercise 5 — Helm in a CI/CD Pipeline

**Scenario:** Your team pushes a code change. The CI pipeline must build a new Docker image and deploy it. The deploy step should use Helm so it is idempotent (safe to re-run) and produces a trackable release history.

**The standard CI/CD Helm deploy pattern:**

```bash
# In your CI pipeline (GitHub Actions, Jenkins, etc.)

IMAGE_TAG=$GIT_COMMIT_SHA    # e.g. abc1234

# Build and push the image
docker build -t myregistry/alpha-api:$IMAGE_TAG .
docker push myregistry/alpha-api:$IMAGE_TAG

# Deploy — upgrade if release exists, install if it doesn't (idempotent)
helm upgrade --install alpha-api-prod ./charts/alpha-api \
  -f ./charts/alpha-api/values-prod.yaml \
  --set image.repository=myregistry/alpha-api \
  --set image.tag=$IMAGE_TAG \
  --namespace team-alpha \
  --create-namespace \
  --wait \              # wait for pods to be ready before marking success
  --timeout 300s \      # fail if not ready in 5 minutes
  --rollback-on-failure              # rollback automatically if deployment fails
```

**Key flags to understand:**
| Flag | What it does |
| -------------| ------------------------------------------------------|
| `--install` | Install if release doesn't exist, upgrade if it does |
| `--wait` | Block until all pods are Ready |
| `--rollback-on-failure` | Automatically rollback on failure |
| `--timeout` | Maximum time to wait |
| `--dry-run` | Preview changes without applying |

**Your task:**

1. Simulate this: run `helm upgrade --install` twice with different `--set image.tag` values
2. Check history: `helm history alpha-api-prod -n team-alpha`
3. Simulate a failed upgrade (use an invalid image tag) — observe `--rollback-on-failure` rollback
4. Write a shell script that mimics the CI deploy step using your alpha-api chart

```bash
  # Run shell script, to see the CI deploy to upgrade the image.
  ./mimic_cicd.sh
```

---

## Exercise 6 — Debugging Helm Problems

The three most useful Helm debugging tools:

```bash
# 1. helm template — render templates locally without touching the cluster
  # Use this to see exactly what YAML will be applied BEFORE you apply it
helm template my-release ./alpha-api -f values-prod.yaml -n team-alpha

# 2. helm diff — show what values WILL change in an upgrade (requires `helm-diff plugin`)
helm plugin install https://github.com/databus23/helm-diff
helm diff upgrade alpha-api-prod ./alpha-api -f values-prod.yaml -n team-alpha

# 3. helm get — inspect a deployed release
helm get values alpha-api-prod -n team-alpha    # what values are in use
helm get manifest alpha-api-prod -n team-alpha  # actual K8s YAML that was applied
helm get notes alpha-api-prod -n team-alpha     # NOTES.txt output
```

**Your task:**

1. Use `helm template` to preview a deploy before applying — compare the output with what's already in the cluster
2. Use `helm get values` to find what values a running release is using
3. Use `helm get manifest` to see the actual rendered YAML that was last applied
4. Run `helm lint alpha-api/` with a deliberately broken template (e.g., unclosed `{{`) and read the error

```bash
  cd Exercise-3/

  # template - to preview the deploy
  helm template alpha-api-prod alpha-api/ -f alpha-api/values-prod.yaml -n prod-env

  # install - to deploy the chart
  helm install alpha-api-prod alpha-api/ -f alpha-api/values-prod.yaml --namespace prod-env --create-namespace

  # get values - to check the values running in deployed chart
  helm get values alpha-api-prod -n prod-env

  # get manifest - to see the last values applied (almost similar to template if revision: 1)
  helm get manifest alpha-api-prod -n prod-env
```

---

## Completion Checklist

- [x] Explain what Helm solves and why raw YAML breaks at scale
- [x] Install, upgrade, rollback, and uninstall a Helm release
- [x] Build a chart from scratch with templates, values, and conditions
- [x] Create separate values files for dev/staging/prod
- [x] Use `helm template` and `helm lint` to validate before deploying
- [x] Use Helm hooks for pre-upgrade database migrations
- [x] Write an idempotent CI/CD deploy command using `helm upgrade --install --rollback-on-failure`

---

## Interview Questions This Task Prepares You For

- **"How does your team deploy applications to Kubernetes?"**
  - We use Helm charts stored in the same Git repo as the application. The CI pipeline builds the Docker image, tags it with the Git commit SHA, then runs `helm upgrade --install` with `--set image.tag=$GIT_SHA --rollback-on-failure --wait`. This is idempotent — safe to re-run — and produces a full revision history. Environment differences (dev/staging/prod) are handled with separate `-f values-<env>.yaml` override files.

- **"How do you manage different configurations for dev, staging, and prod?"**
  - One chart, multiple values files: `values.yaml` holds safe defaults, `values-dev.yaml` / `values-prod.yaml` override only what differs (replica count, resource limits, HPA enabled/disabled, image registry). CI passes `-f values-prod.yaml` at deploy time. No YAML duplication across environments.

- **"A CI/CD deployment failed halfway. How does Helm handle that with `--rollback-on-failure`?"**
  - `--rollback-on-failure` combines `--wait` with automatic rollback. Helm waits for all pods to reach Ready state. If any pod fails to become Ready within the timeout, Helm automatically rolls back to the previous revision and marks the release as `failed`. This means a broken deployment never stays "half-applied" — the cluster returns to the last known good state automatically.

- **"What is the difference between `helm install` and `helm upgrade --install`?"**
  - `helm install` fails if the release already exists.
  - `helm upgrade` fails if the release does NOT exist yet.
  - `helm upgrade --install` is idempotent — installs if new, upgrades if existing. This is the standard CI/CD pattern: one command that works on both first deploy and all subsequent deploys.

- **"How do you run a database migration safely before a new version of your app starts?"**
  - Use a **Helm pre-upgrade hook**: a `Job` with annotation `helm.sh/hook: pre-upgrade,pre-install`. Helm runs the Job, waits for it to complete successfully, and only then rolls out the new Deployment. If the Job fails, the upgrade is blocked — the old version keeps running. Add `helm.sh/hook-delete-policy: hook-succeeded` to clean up the Job after success.

- **"Where does Helm store release state and what happens if that storage is lost?"**
  - Helm stores each revision as a Kubernetes Secret (`sh.helm.release.v1.<name>.v<revision>`) in the release namespace. If those Secrets are deleted (e.g., namespace deleted, etcd corruption), Helm loses all knowledge of the release — `helm list` shows nothing, `helm rollback` is impossible. The actual workload (Deployment, Service, etc.) still exists in the cluster, but Helm can no longer manage it.
  - Recovery: `helm history` will be empty; you'd need to `helm uninstall` with `--no-hooks` or manually delete resources and re-install.

- **"How do you see what values a currently deployed Helm release is using?"**
  - `helm get values <release> -n <namespace>` — shows only the user-supplied values (overrides). Add `--all` to also show computed defaults from `values.yaml`.
  - `helm get manifest <release> -n <namespace>` — shows the actual rendered K8s YAML that was last applied.

- **"We deployed a breaking change and need to rollback immediately — how do you do it with Helm?"**
  - `helm history <release> -n <namespace>` — find the last good revision number.
  - `helm rollback <release> <revision> -n <namespace>` — re-applies that revision's manifest. This creates a new revision in history (does not delete the bad one). Add `--wait` to block until pods are Ready. If the release is completely broken: `helm rollback <release> 0` rolls back to the previous revision without specifying a number.

---

## Mini Project — podinfo Helm Chart

> Estimated time: 2–3 hours. Put this in GitHub under `k8s-practice/task-06/`.

**Scenario:** Package and deploy the [podinfo](https://github.com/stefanprodan/podinfo) app as a custom Helm chart from scratch.

**What was built (`podinfo-app/` chart):**

```
podinfo-app/
  Chart.yaml
  values.yaml            → defaults (dev-friendly: 1 replica, small resources)
  values-prod.yaml       → prod overrides (3 replicas, HPA enabled, larger limits)
  templates/
    deployment.yml
    service.yml
    hpa.yml            → conditional on autoscaling.enabled
    ingress.yml
    configMap.yml
```

**Supporting manifests (`podinfo_project/`):** raw K8s objects used alongside the chart — Namespace, ResourceQuota, LimitRange, NetworkPolicies, cert-manager Certificate + ClusterIssuer.

**Key things practiced here that differ from alpha-api:**

- Ingress + TLS certificate via cert-manager
- NetworkPolicies scoped to the podinfo namespace
- ResourceQuota + LimitRange enforced on the namespace
- `helm template podinfo-app podinfo-app/ > final.yml` to inspect full rendered output

**Requirements met:**

- HPA conditionally rendered via `autoscaling.enabled` in values
- Dev and prod environments handled with `values.yaml` + `values-dev.yaml`
- All resource limits configurable via values
- Chart passes `helm lint` with zero warnings

**Proof of completion:**

```bash
# Lint and render
helm lint podinfo-app/
helm template podinfo-app podinfo-app/ -n podinfo > final.yml

# Install with dev values
helm install podinfo-dev podinfo-app/ -f podinfo-app/values-dev.yaml -n podinfo --create-namespace

# Verify
kubectl get deploy,svc,hpa,ingress -n podinfo
helm get values podinfo-dev -n podinfo

# Upgrade and check history
helm upgrade podinfo-dev podinfo-app/ -f podinfo-app/values-dev.yaml --set image.tag=6.6.0 -n podinfo
helm history podinfo-dev -n podinfo

# Rollback
helm rollback podinfo-dev 1 -n podinfo
```

**Dig deeper:**

- `_helpers.tpl` is not yet in the chart — add a `{{- define "podinfo.labels" }}` helper and use it in all templates to avoid label duplication. This is standard in every production chart.
- Test the NetworkPolicy is actually enforced: `kubectl exec` into a pod in a different namespace and try to reach the podinfo service — it should be blocked.
- `helm get manifest podinfo-dev -n podinfo` — compare the rendered output with `final.yml` to confirm values were applied correctly.

---

**Next: Task-07-Observability.md** (you will install the monitoring stack using Helm in that task)
