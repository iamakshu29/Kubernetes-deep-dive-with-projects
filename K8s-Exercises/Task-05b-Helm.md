# Task 05b — Helm: Packaging and Deploying Applications at Scale

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
charts/alpha-api/       → one set of templates
  values.yaml           → defaults
  values-dev.yaml       → overrides for dev
  values-staging.yaml   → overrides for staging
  values-prod.yaml      → overrides for prod
```
CI/CD runs `helm upgrade --install alpha-api ./charts/alpha-api -f values-prod.yaml --set image.tag=$GIT_SHA`. Done.

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
- What is a Helm revision?
- What is the difference between `helm upgrade` and `helm upgrade --install`?

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

**`alpha-api/templates/deployment.yaml`:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}-api
  namespace: {{ .Release.Namespace }}
  labels:
    app: {{ .Release.Name }}-api
    version: {{ .Values.image.tag | quote }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: {{ .Release.Name }}-api
  template:
    metadata:
      labels:
        app: {{ .Release.Name }}-api
    spec:
      containers:
      - name: api
        image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
        ports:
        - containerPort: {{ .Values.service.targetPort }}
        resources:
          requests:
            cpu: {{ .Values.resources.requests.cpu }}
            memory: {{ .Values.resources.requests.memory }}
          limits:
            cpu: {{ .Values.resources.limits.cpu }}
            memory: {{ .Values.resources.limits.memory }}
        {{- if .Values.probes.enabled }}
        readinessProbe:
          httpGet:
            path: /
            port: {{ .Values.service.targetPort }}
          initialDelaySeconds: 5
          periodSeconds: 10
        livenessProbe:
          httpGet:
            path: /
            port: {{ .Values.service.targetPort }}
          initialDelaySeconds: 30
          periodSeconds: 15
        {{- end }}
```

**`alpha-api/templates/service.yaml`:**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ .Release.Name }}-api
  namespace: {{ .Release.Namespace }}
spec:
  selector:
    app: {{ .Release.Name }}-api
  ports:
  - port: 80
    targetPort: {{ .Values.service.targetPort }}
  type: {{ .Values.service.type }}
```

**`alpha-api/templates/hpa.yaml`:**
```yaml
{{- if .Values.autoscaling.enabled }}
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ .Release.Name }}-api
  namespace: {{ .Release.Namespace }}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {{ .Release.Name }}-api
  minReplicas: {{ .Values.autoscaling.minReplicas }}
  maxReplicas: {{ .Values.autoscaling.maxReplicas }}
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: {{ .Values.autoscaling.targetCPUUtilizationPercentage }}
{{- end }}
```

### Step 4 — Write the default values

**`alpha-api/values.yaml`:**
```yaml
replicaCount: 2

image:
  repository: hashicorp/http-echo
  tag: "0.2.3"

service:
  type: ClusterIP
  targetPort: 5678

resources:
  requests:
    cpu: 100m
    memory: 64Mi
  limits:
    cpu: 300m
    memory: 128Mi

probes:
  enabled: true

autoscaling:
  enabled: false
  minReplicas: 2
  maxReplicas: 6
  targetCPUUtilizationPercentage: 60
```

### Step 5 — Create environment-specific override files

**`values-dev.yaml`:**
```yaml
replicaCount: 1
resources:
  requests:
    cpu: 50m
    memory: 32Mi
  limits:
    cpu: 200m
    memory: 64Mi
autoscaling:
  enabled: false
probes:
  enabled: false   # faster iteration in dev
```

**`values-prod.yaml`:**
```yaml
replicaCount: 3
image:
  tag: "1.0.0"
resources:
  requests:
    cpu: 200m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 256Mi
autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 10
  targetCPUUtilizationPercentage: 50
probes:
  enabled: true
```

### Step 6 — Lint, render, and deploy

```bash
# Check chart for errors
helm lint alpha-api/

# Preview what YAML will be created (dry run — does not touch cluster)
helm template alpha-api-dev alpha-api/ -f alpha-api/values-dev.yaml -n team-alpha

# Install to dev
helm install alpha-api-dev alpha-api/ \
  -f alpha-api/values-dev.yaml \
  -n team-alpha \
  --create-namespace

# Verify
kubectl get deploy,svc,hpa -n team-alpha

# Upgrade dev with a new image tag (simulating CI/CD)
helm upgrade alpha-api-dev alpha-api/ \
  -f alpha-api/values-dev.yaml \
  --set image.tag="0.2.4" \
  -n team-alpha

# Deploy to prod (separate release, same chart)
helm install alpha-api-prod alpha-api/ \
  -f alpha-api/values-prod.yaml \
  -n team-alpha
```

**You should know how to answer:**
- "What is the difference between `helm install` and `helm upgrade --install`?"
- "How do you pass a value that overrides `values.yaml` at deploy time?" (hint: `--set key=value`)
- "Which takes precedence — `values.yaml`, `-f values-prod.yaml`, or `--set`?" (answer: `--set` > `-f file` > `values.yaml`)

---

## Exercise 4 — Helm Hooks (Pre/Post Install Jobs)

**Scenario:** Before deploying a new version of the API, you need to run a database migration. This must complete successfully before the new pods start. Helm hooks let you run Jobs at specific points in the release lifecycle.

**Your task:**
1. Create `alpha-api/templates/migrate-job.yaml`:
   ```yaml
   apiVersion: batch/v1
   kind: Job
   metadata:
     name: {{ .Release.Name }}-migrate-{{ .Release.Revision }}
     namespace: {{ .Release.Namespace }}
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
2. Run `helm upgrade alpha-api-dev alpha-api/ -f alpha-api/values-dev.yaml -n team-alpha`
3. Watch: the Job runs first, completes, THEN the Deployment rolls out
4. Set the migration to fail (`exit 1`) — observe that the upgrade is blocked

**Key hook annotations:**
| Annotation | Meaning |
|---|---|
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
  --atomic              # rollback automatically if deployment fails
```

**Key flags to understand:**
| Flag | What it does |
|---|---|
| `--install` | Install if release doesn't exist, upgrade if it does |
| `--wait` | Block until all pods are Ready |
| `--atomic` | Automatically rollback on failure |
| `--timeout` | Maximum time to wait |
| `--dry-run` | Preview changes without applying |

**Your task:**
1. Simulate this: run `helm upgrade --install` twice with different `--set image.tag` values
2. Check history: `helm history alpha-api-prod -n team-alpha`
3. Simulate a failed upgrade (use an invalid image tag) — observe `--atomic` rollback
4. Write a shell script that mimics the CI deploy step using your alpha-api chart

---

## Exercise 6 — Debugging Helm Problems

The three most useful Helm debugging tools:

```bash
# 1. helm template — render templates locally without touching the cluster
#    Use this to see exactly what YAML will be applied BEFORE you apply it
helm template my-release ./alpha-api -f values-prod.yaml -n team-alpha

# 2. helm diff — show what WILL change in an upgrade (requires helm-diff plugin)
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

---

## Completion Checklist

- [ ] Explain what Helm solves and why raw YAML breaks at scale
- [ ] Install, upgrade, rollback, and uninstall a Helm release
- [ ] Build a chart from scratch with templates, values, and conditions
- [ ] Create separate values files for dev/staging/prod
- [ ] Use `helm template` and `helm lint` to validate before deploying
- [ ] Use Helm hooks for pre-upgrade database migrations
- [ ] Write an idempotent CI/CD deploy command using `helm upgrade --install --atomic`

---

## Interview Questions This Task Prepares You For

- "How does your team deploy applications to Kubernetes?"
- "How do you manage different configurations for dev, staging, and prod?"
- "A CI/CD deployment failed halfway. How does Helm handle that with `--atomic`?"
- "What is the difference between `helm install` and `helm upgrade --install`?"
- "How do you run a database migration safely before a new version of your app starts?"
- "Where does Helm store release state and what happens if that storage is lost?"
- "How do you see what values a currently deployed Helm release is using?"
- "We deployed a breaking change and need to rollback immediately — how do you do it with Helm?"

---

## Mini Project — Package team-alpha's Full Stack as a Helm Chart

> Estimated time: 2–3 hours. Put this in GitHub under `k8s-practice/task-05b/`.

**Scenario:** Package the Task 02 mini-project (api + redis) as a single Helm chart that can be deployed to dev and prod with different configurations.

**Deliverables:**

```
charts/alpha-stack/
  Chart.yaml
  values.yaml            → defaults (dev-friendly: 1 replica, small resources)
  values-prod.yaml       → prod overrides (3 replicas, HPA enabled, larger limits)
  templates/
    api-deployment.yaml
    api-service.yaml
    redis-deployment.yaml
    redis-service.yaml
    hpa.yaml             → conditional on .Values.autoscaling.enabled
    configmap.yaml       → contains non-sensitive API config
    _helpers.tpl         → define a reusable label helper
```

**Requirements:**
- `image.tag` must be overridable at deploy time (for CI/CD)
- HPA must be conditionally rendered — enabled in prod, disabled in dev
- Redis deployment should be conditional: `redis.enabled: true/false`
- All resource limits must be configurable via values
- Chart must pass `helm lint` with zero warnings

**Proof of completion (README.md):**
```bash
# Dev deploy
helm install alpha-dev ./charts/alpha-stack -f values-dev.yaml -n team-alpha --dry-run
helm install alpha-dev ./charts/alpha-stack -f values-dev.yaml -n team-alpha

# Prod deploy
helm install alpha-prod ./charts/alpha-stack -f charts/alpha-stack/values-prod.yaml -n team-alpha

# Upgrade (simulating CI pushing new image)
helm upgrade alpha-prod ./charts/alpha-stack -f charts/alpha-stack/values-prod.yaml \
  --set image.tag=v2 -n team-alpha --atomic

helm history alpha-prod -n team-alpha
```

---

**Next: Task-06-Observability.md** (you will install the monitoring stack using Helm in that task)
