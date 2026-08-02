# Mini Project — Demo App Stack (Helm + Observability)

> This project is shared across **Task 06 (Helm)** and **Task 07 (Observability)**.
> Phase 1 builds and deploys the app using Helm. Phase 2 instruments and observes it.
> Don't jump to Phase 2 until the app is running cleanly from Phase 1.

---

## The App — `podinfo`

You will deploy **podinfo** — a small Go web app designed specifically for K8s demos.

Why this app, not a custom one:
- Exposes a proper Prometheus `/metrics` endpoint out of the box — no extra work needed to get metrics
- Has built-in **error injection**: you can make it return 500s on demand, which lets you trigger real alerts
- Has built-in **latency injection**: add artificial delay to test SLO breach scenarios
- Has built-in **CPU/memory stress** endpoint — useful for testing HPA in Phase 1
- Has a simple UI you can open in a browser to see the app is live
- Realistic enough for practice but simple enough to understand fully

Image: `ghcr.io/stefanprodan/podinfo` — available publicly, no auth needed.  
Default port: `9898`  
Metrics path: `/metrics`  
Health path: `/healthz`

**Fault injection endpoints** (you will use these in Phase 2):
- `POST /healthz/disable` — makes the app return `503` on every subsequent request. Simulates your app going down.
- `POST /healthz/enable` — re-enables the app (returns 200 again)
- `GET /delay/{seconds}` — responds after the given delay. Use `3` to simulate high latency.
- `POST /stress/{cores}/{duration}` — spins up CPU load. Useful for testing HPA.

---

## Namespace

Use namespace `demo` for the entire project.  
Create it once: `kubectl create namespace demo`

---

## Phase 1 — Helm Chart (Task 06)

The goal: package podinfo as a Helm chart you wrote yourself, and deploy it properly with values overrides.

---

### Step 1 — Create the chart scaffold

Use `helm create demo-app` to generate the chart skeleton.  
Delete all the generated files inside `templates/` — you will write your own.  
Keep the `Chart.yaml` and `values.yaml` files (you will edit them).

Update `Chart.yaml`:
- Set `name: demo-app`
- Set `appVersion` to the podinfo version you plan to use (e.g. `6.7.0`)
- Set `description` to something meaningful

---

### Step 2 — Write the Deployment template

The Deployment template must be parameterised using values — no hardcoded strings except kind/apiVersion.

Fields to pull from values:
- `image.repository` and `image.tag`
- `replicaCount`
- `resources.requests.cpu`, `resources.requests.memory`, `resources.limits.cpu`, `resources.limits.memory`
- `service.port` (for containerPort)

Probes:
- Wrap the readiness and liveness probes in a conditional — only render them if `probes.enabled` is `true`
- Use `path: /healthz` for both probes

Annotations:
- Add a template annotation `prometheus.io/scrape: "true"` and `prometheus.io/port` on the **pod** metadata — required so Prometheus can discover the pod automatically without a ServiceMonitor

---

### Step 3 — Write the Service template

- Type and port from values (`service.type`, `service.port`)
- targetPort should match the containerPort (9898)

---

### Step 4 — Write the HPA template

- Wrap the entire template in `{{- if .Values.autoscaling.enabled }}`
- `minReplicas`, `maxReplicas`, `targetCPUUtilizationPercentage` all from values
- Target the Deployment by name using `{{ .Release.Name }}`

---

### Step 5 — Write the ConfigMap template

podinfo can read a configuration file. Create a ConfigMap that holds:
- A key `config.yaml` with the value being whatever you want podinfo to display as its "config" (this is just for practice — podinfo will show it in its UI)
- Reference this ConfigMap as a volume mount in your Deployment at `/data`

---

### Step 6 — Write values.yaml

Define sensible defaults:
- `replicaCount: 1`
- image pointing to podinfo (repository + tag)
- `service.type: ClusterIP` and `service.port: 9898`
- Resources: small requests (10m CPU, 32Mi memory) and reasonable limits
- `probes.enabled: true`
- `autoscaling.enabled: false` with `minReplicas: 1`, `maxReplicas: 4`, `targetCPUUtilizationPercentage: 50`

---

### Step 7 — Write values-dev.yaml

This file only contains the **overrides** for a dev environment — not a full copy of values.yaml:
- `replicaCount: 1`
- `autoscaling.enabled: false`
- Resources smaller than defaults

---

### Step 8 — Dry-run and install

Before installing, render all templates with default values and inspect the output:
```
helm template demo-app ./demo-app
```
Make sure it looks correct — no empty fields, no rendering errors.

Lint the chart:
```
helm lint ./demo-app
```

Install into the `demo` namespace:
```
helm install demo-app ./demo-app --namespace demo -f ./demo-app/values-dev.yaml
```

Verify:
- `helm list -n demo` shows the release
- `kubectl get all -n demo` shows the pod, service, and deployment
- Port-forward to port 9898 and open the UI in a browser

---

### Step 9 — Upgrade and rollback

1. Upgrade to 2 replicas using `--set` (not by editing the file):
   ```
   helm upgrade demo-app ./demo-app -n demo --set replicaCount=2
   ```
2. Check `helm history demo-app -n demo` — you should see 2 revisions
3. Roll back to revision 1
4. Verify only 1 replica is running again

---

### Step 10 — Enable HPA via upgrade

1. Upgrade with autoscaling enabled and max replicas 3:
   ```
   helm upgrade demo-app ./demo-app -n demo --set autoscaling.enabled=true --set autoscaling.maxReplicas=3
   ```
2. Verify the HPA was created: `kubectl get hpa -n demo`
3. Trigger CPU load using the podinfo stress endpoint (curl `POST /stress/1/30` from inside the cluster)
4. Watch the HPA react: `kubectl get hpa -n demo -w`

---

### Step 11 — Add Redis as a dependency

Update `Chart.yaml` to declare a chart dependency:
- Add the bitnami Redis chart as a dependency with a version pin
- Set the `alias` to `redis`

Run `helm dependency update` to pull in the dependency.

Add a `redis` section to `values.yaml` with at minimum:
- `enabled: true`
- `architecture: standalone`

Upgrade the release — Redis should now appear as a pod in the `demo` namespace.

> **Checkpoint:** At the end of Phase 1 you should be able to:
> - Install, upgrade, and rollback the app entirely from the chart
> - Change any configuration (replicas, image tag, autoscaling) without editing YAML directly
> - Know where Helm stores release state and how to inspect it
> - Explain what `helm diff upgrade` would tell you before applying a change

---

## Phase 2 — Observability (Task 07)

The goal: treat the Phase 1 deployment as your "production" app and build full observability on top of it.

**Prerequisite:** The `kube-prometheus-stack` (Prometheus + Grafana + Alertmanager) must be running in the `monitoring` namespace. Install it via Helm if you haven't already — this is covered in Task 07 Exercise 2.

---

### Step 1 — Add a ServiceMonitor template to the chart

The pod annotations you added in Phase 1 Step 2 let Prometheus scrape via annotation-based discovery. But the proper way is a **ServiceMonitor**.

Add a new template file `templates/servicemonitor.yaml`:
- Wrap it in `{{- if .Values.monitoring.enabled }}`
- It should select the Service created by your chart
- Set `endpoints.path` to `/metrics` and `endpoints.port` to the named port

Add `monitoring.enabled: false` to values.yaml (off by default).

Upgrade the release with `monitoring.enabled=true`:
```
helm upgrade demo-app ./demo-app -n demo --set monitoring.enabled=true
```

Verify the ServiceMonitor was created: `kubectl get servicemonitor -n demo`

---

### Step 2 — Verify Prometheus is scraping the app

Port-forward to Prometheus (port 9090).  
Go to Status → Targets and find your podinfo instance in the list.  
It should show as `UP`.

In the Prometheus query box, type `http_requests_total` and confirm data is coming in.

If it is NOT in Targets:
- Check that the ServiceMonitor's `namespaceSelector` covers the `demo` namespace
- Check that the label selector in the ServiceMonitor matches the Service labels
- Check Prometheus' `serviceMonitorSelector` in its config — it must allow your ServiceMonitor

---

### Step 3 — Generate traffic

You need ongoing traffic to make the dashboards and alerts meaningful.

From inside the cluster, run a pod that curls podinfo in a loop:
```
kubectl run traffic-gen --image=busybox -n demo --restart=Never -- \
  /bin/sh -c "while true; do wget -q -O- http://demo-app:9898/; sleep 0.5; done"
```

Let it run for at least 2–3 minutes before building dashboards.

---

### Step 4 — Build Grafana dashboards

Port-forward Grafana (port 3000). Create a new dashboard with these panels:

**Panel 1 — HTTP Request Rate**  
Query: `rate()` on `http_requests_total` for the `demo` namespace, grouped by status code.  
Visualization: Time series. This shows you requests/second split by HTTP status code.

**Panel 2 — Error Rate %**  
Query: the ratio of 5xx responses to all responses, as a percentage.  
Visualization: Stat or gauge. Threshold: green below 1%, red above 5%.

**Panel 3 — p99 Latency**  
podinfo exposes a histogram metric `http_request_duration_seconds_bucket`.  
Query: use `histogram_quantile(0.99, ...)` to get the 99th percentile latency.  
Visualization: Time series.

**Panel 4 — Pod Restarts**  
Use `kube_pod_container_status_restarts_total` for the `demo` namespace.  
Visualization: Stat.

**Panel 5 — Replica Count**  
Use `kube_deployment_status_replicas_ready` filtered to your deployment.  
Visualization: Stat. Useful to see HPA scaling events.

Save the dashboard with a meaningful name and add it to a folder called `demo-app`.

---

### Step 5 — Set up alerts

Create a `PrometheusRule` (not through the chart yet — just a standalone YAML for now) with these two alerts:

**Alert 1 — HighErrorRate**
- Fires when: more than 5% of HTTP requests return 5xx over a 2-minute window
- Severity: `warning`
- Annotation: include the current error rate value in the message

**Alert 2 — HighP99Latency**
- Fires when: p99 latency exceeds 1 second for 2 minutes
- Severity: `warning`

Apply it and verify it appears in Prometheus → Alerts tab as `Inactive`.

---

### Step 6 — Trigger the alerts (error injection)

1. Port-forward to podinfo (port 9898)
2. Send `POST /healthz/disable` — this makes podinfo return 503 on every request
3. Keep the traffic generator running (it will now get all 503s)
4. Watch Prometheus → Alerts — within 2 minutes `HighErrorRate` should move from `Pending` to `Firing`
5. Re-enable: send `POST /healthz/enable`
6. Watch the alert resolve

Then test latency:
1. Change the traffic generator to call `/delay/2` instead of `/`
2. Watch `HighP99Latency` fire after 2 minutes
3. Restore normal traffic

---

### Step 7 — Move the alerts into the Helm chart

Now that the PrometheusRule works standalone, make it part of the chart:
- Add `templates/prometheusrule.yaml`
- Gate it with `{{- if .Values.monitoring.enabled }}`
- Put the alert thresholds in values.yaml so they can be overridden:
  - `monitoring.errorRateThreshold: 0.05`
  - `monitoring.latencyThreshold: 1`

Upgrade the release — the PrometheusRule should now be managed by Helm.

Verify: `helm get manifest demo-app -n demo` should include the PrometheusRule.

---

### Step 8 — Centralised logging with Loki (optional but recommended)

Install Loki + Promtail via Helm into the `monitoring` namespace (covered in Task 07 Exercise 6).

Once installed:
1. In Grafana → Explore, switch the data source to Loki
2. Query: `{namespace="demo"}` — you should see all podinfo logs
3. Filter further: `{namespace="demo"} |= "error"` — only log lines containing "error"
4. Add a **Logs panel** to your existing dashboard showing live logs from the demo namespace

---

## Extension Ideas (for when you expand Task 07)

These are not part of the current exercises but good to know so you keep the project around:

- **Distributed tracing**: Add Tempo (Grafana's trace backend) to the stack. podinfo can emit traces with a flag.
- **SLO dashboard**: Build an error-budget burn-rate panel using multi-window alerting (fast burn + slow burn, like Google SRE).
- **Runbook links**: Add `runbook_url` annotation to each alert that links to a local markdown file explaining how to respond.
- **Multi-environment**: Deploy the same chart into `demo-dev` and `demo-staging` namespaces with different values. Practice namespace-scoped dashboards in Grafana.
- **Alertmanager routing**: Configure Alertmanager to route `severity=critical` to one receiver and `severity=warning` to another. Test inhibition rules.
- **Dashboard-as-code**: Export the Grafana dashboard JSON and commit it to the chart as a ConfigMap + GrafanaDashboard CRD — so the dashboard is deployed automatically when the chart is installed.

---

## Proof of Completion

**Phase 1 (Helm):**
- [ ] `helm list -n demo` shows `demo-app` deployed
- [ ] Chart has Deployment, Service, HPA, ConfigMap, ServiceMonitor templates (all conditional or parameterised)
- [ ] Can upgrade image tag with a single `--set` flag and confirm the pod restarts with new image
- [ ] `helm rollback` restores previous revision and the old pod comes up
- [ ] Redis dependency pod is running in the `demo` namespace

**Phase 2 (Observability):**
- [ ] podinfo appears in Prometheus Targets as UP
- [ ] Grafana dashboard shows live request rate, error rate, p99 latency, restart count
- [ ] `HighErrorRate` alert fires after calling `/healthz/disable` and traffic is running
- [ ] Alert resolves after calling `/healthz/enable`
- [ ] PrometheusRule is now part of the Helm chart and shows in `helm get manifest`
- [ ] (Optional) Loki query `{namespace="demo"}` returns logs in Grafana Explore
