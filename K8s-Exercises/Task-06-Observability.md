# Task 06 — Observability: Metrics, Logs & Alerting

> Real-world relevance: "The app is down" — your job is to find out WHY in under 5 minutes.
> Observability is what makes that possible. Every DevOps engineer is expected to own this.

> **Cluster needed:** Multi-node cluster with 6GB+ available RAM. The Prometheus + Grafana stack is heavy.
> - **Recommended:** [Oracle Cloud Free Tier](https://www.oracle.com/cloud/free/) — 2 ARM VMs with 24GB RAM total, always free, persistent. Setup in **00-Setup.md Option B**.
> - **Alternative:** AWS EC2 (t3.large for master, t3.medium for worker) — ~$0.50/session. Setup in **00-Setup.md Option C**.
> - **Local fallback:** kind 3-node with `--memory=6144 --cpus=4` — only if your machine has 8GB+ free RAM. Not ideal.
> - **NOT recommended:** Killercoda (4-hour session limit — Prometheus setup and exercises take longer than that).

---

## What You Will Learn

- The three pillars: Metrics, Logs, Traces (focus on first two)
- Deploy Prometheus + Grafana via Helm — the industry standard stack
- Write PromQL queries to answer real operational questions
- Set up alerts that fire before users notice problems
- Centralised logging with a log aggregation pattern
- Reading and acting on K8s events

---

## Background — Read Before Starting

K8s generates a massive amount of data. Without observability, you are flying blind.

At a company, the monitoring stack is owned by the DevOps/Platform team. App teams consume dashboards and alerts but DevOps configures the infrastructure.

The standard stack:
```
Prometheus    → scrapes metrics from pods, nodes, K8s components
Grafana       → visualises metrics into dashboards
Alertmanager  → fires alerts to Slack/PagerDuty when thresholds breach
Loki/EFK      → log aggregation
```

---

## Exercise 1 — Install Metrics-Server and Understand Resource Metrics

Before anything else:
```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

**Your task:**
1. After metrics-server is running, check node resource usage: `kubectl top nodes`
2. Check pod resource usage: `kubectl top pods -A`
3. Sort pods by CPU usage — find the most resource-hungry pod in the cluster
4. Find pods that are close to their memory limits (compare `kubectl top` output with `kubectl describe pod` limits)
5. Explain: what is the difference between metrics-server and Prometheus? When is each used?

---

## Exercise 2 — Deploy Prometheus + Grafana with Helm

**Install Helm first:**
```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

**Your task:**
1. Add the Prometheus community Helm repo and install the `kube-prometheus-stack`:
   ```bash
   helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
   helm repo update
   helm install monitoring prometheus-community/kube-prometheus-stack \
     --namespace monitoring --create-namespace
   ```
2. Verify what was deployed: list all pods, services, and CRDs in the `monitoring` namespace
3. Port-forward to access Grafana in your browser:
   ```bash
   kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring
   ```
   Default credentials: admin / prom-operator
4. In Grafana, open the "Kubernetes / Compute Resources / Cluster" dashboard
5. Port-forward to Prometheus and explore the raw metrics UI
6. Understand what a `ServiceMonitor` CRD is — find the ones that were created during install

**You should know how to answer:**
- What is the difference between Helm install and kubectl apply?
- What is a Helm release and how do you upgrade or rollback one?

---

## Exercise 3 — Writing PromQL Queries

Access Prometheus UI (port-forward to port 9090) and write queries to answer:

**Your task — answer each question with a PromQL query:**

1. What is the CPU usage percentage for each node right now?
2. Which pods have been restarting frequently in the last hour?
3. What is the memory usage of the `alpha-api` deployment across all replicas?
4. How many pods are currently NOT in a Running state?
5. What percentage of a namespace's CPU quota is being used?

**Write each query and note what it returns. Do not copy answers — figure them out by exploring the Prometheus metrics browser.**

**Tip:** Start with `kube_pod_*`, `container_cpu_*`, `container_memory_*` metric families.

**You should know how to answer:**
- What is the difference between a Counter and a Gauge in Prometheus?
- What does `rate()` do in PromQL and why do you use it on counters?

---

## Exercise 4 — Set Up an Alert

**Scenario:** You want to be notified if any pod restarts more than 3 times in 10 minutes.

**Your task:**
1. Create a `PrometheusRule` CRD in the `monitoring` namespace:
   - Alert name: `HighPodRestartRate`
   - Condition: pod restart count increases by more than 3 in 10 minutes
   - Severity: `warning`
   - Add a message annotation that says which pod and namespace is affected
2. Force the alert to fire: deploy a pod that crashes on startup (`kubectl run crasher --image=busybox -- /bin/sh -c "exit 1"`)
3. See the alert appear as `Firing` in the Prometheus Alerts UI
4. Check Alertmanager — understand the routing concept (even without a real Slack webhook)

**You should know how to answer:**
- What is the difference between a Pending and Firing alert?
- What is alert inhibition and silencing in Alertmanager?

---

## Exercise 5 — Application Instrumentation (Exposing Custom Metrics)

**Scenario:** `team-alpha`'s API needs to expose its request count and response time to Prometheus.

**Your task:**
1. Deploy the Prometheus example app that exposes metrics on `/metrics`:
   ```
   kubectl run metrics-demo --image=quay.io/brancz/prometheus-example-app --port=8080 -n team-alpha
   ```
2. Port-forward and curl `/metrics` — read the output format (Prometheus exposition format)
3. Create a `ServiceMonitor` for this app so Prometheus scrapes it automatically
4. Verify the metrics appear in Prometheus by searching for `http_requests_total`
5. Build a Grafana panel showing request rate over time for this app

**You should know how to answer:**
- What is a ServiceMonitor and how does Prometheus Operator use it?
- What is the Prometheus exposition format?

---

## Exercise 6 — Logs (The K8s Way)

**Your task:**
1. `kubectl logs <pod>` — get the last 50 lines of a pod's logs
2. Stream live logs: `kubectl logs -f <pod>`
3. Get logs from a specific container in a multi-container pod
4. Get logs from the previous crashed container: `kubectl logs <pod> --previous`
5. Get logs from all pods of a Deployment at once (using label selector): `kubectl logs -l app=alpha-api -n team-alpha`

**Centralised logging concept:**
Install Loki + Promtail via Helm and connect it to Grafana. Then:
- Query logs from all `team-alpha` pods in Grafana's Explore tab
- Filter logs by pod name, namespace, and keyword

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm install loki grafana/loki-stack --namespace monitoring --set grafana.enabled=false
```

**You should know how to answer:**
- Why is `kubectl logs` not enough for a production company setup?
- What is the difference between Loki and Elasticsearch for log storage?

---

## Exercise 7 — SLO-Based Alerting and the Cluster Autoscaler

### Part A — SLO-Based Alerting (Alerting Like a Company)

**Scenario:** Most junior engineers set alerts on "CPU > 80%" and call it done. Production teams alert on SLOs — Service Level Objectives — which are user-facing indicators. The difference is fundamental: CPU high is a symptom; users can't checkout is the problem.

**Background:**
- **SLI (Service Level Indicator):** A measurable metric. Example: percentage of requests that return HTTP 2xx.
- **SLO (Service Level Objective):** A target for the SLI. Example: 99.5% of requests must succeed over any 30-day window.
- **Error budget:** What you have left. If SLO is 99.5%, your error budget is 0.5%. When it burns down, you stop deploying new features until reliability is restored.

**Your task:**
1. For `team-alpha`'s API, define these two SLOs (conceptually — you will implement alerts based on them):
   - **Availability SLO:** 99% of HTTP requests return non-5xx in any 10-minute window
   - **Latency SLO:** 95% of requests complete in under 500ms

2. Write a `PrometheusRule` that alerts when availability drops below the SLO threshold. Using the example app metrics:
   ```yaml
   - alert: AvailabilitySLOBreach
     expr: |
       (
         sum(rate(http_requests_total{namespace="team-alpha",code!~"5.."}[10m]))
         /
         sum(rate(http_requests_total{namespace="team-alpha"}[10m]))
       ) < 0.99
     for: 2m
     labels:
       severity: critical
       team: alpha
     annotations:
       summary: "Availability SLO breach for team-alpha"
       description: "Success rate is {{ $value | humanizePercentage }} — below 99% SLO"
   ```

3. Trigger this alert by deploying a pod that returns 500 errors and generating traffic through it

4. In Grafana, create a panel showing the **error budget burn rate** over the last hour:
   - If the burn rate is > 1, you are burning budget faster than you are accumulating it
   - If burn rate > 14 (meaning you will exhaust the monthly budget in 2 hours at this rate) → page immediately

5. Write a second alert for the latency SLO breach (hint: use `histogram_quantile(0.95, ...)`)

**You should know how to answer:**
- "What is the difference between alerting on symptoms vs causes?"
- "What is an error budget and why does it matter for deployment decisions?"
- "Why is a 99.9% SLO significantly harder to maintain than 99%?" (hint: ~43 min/month vs ~8.7 hrs/month of allowed downtime)

---

### Part B — Cluster Autoscaler (Node-Level Scaling)

**Scenario:** HPA scales pods. But if there are no free nodes to place new pods on, HPA does nothing — pods stay `Pending`. Cluster Autoscaler (CA) detects pending pods that can't be scheduled due to resource shortfall and adds a new node. When nodes are underutilised, CA removes them.

**This exercise is conceptual for local clusters — apply it on Oracle Free Tier or AWS where you can actually add nodes.**

**Your task (understanding + hands-on where possible):**

1. Understand the CA loop:
   ```
   Pod is Pending (can't be scheduled — no capacity)
     → CA detects it within 10 seconds
       → CA calls cloud provider API to add a node
         → New node registers with K8s
           → Pending pods get scheduled
   
   Node is underutilised for 10+ minutes
     → CA checks if all pods can fit on other nodes
       → If yes: drain and delete the node
   ```

2. Understand the interaction between HPA and CA:
   - HPA fires → adds pods → pods go Pending → CA fires → adds node → pods scheduled
   - Traffic drops → HPA scales down pods → nodes underutilised → CA removes nodes
   - This is the full auto-scaling story. HPA without CA means you can only scale within existing capacity.

3. On Oracle Free Tier or AWS: simulate node pressure
   - Deploy a workload that exceeds one node's capacity
   - With CA installed (cloud-provider specific), observe node addition
   - Remove the workload — observe node eventually being removed

4. Key CA configuration to understand:
   - `--scale-down-utilization-threshold=0.5` — nodes under 50% util are candidates for removal
   - `--scale-down-delay-after-add=10m` — wait 10 min after adding a node before considering scale-down
   - CA never removes a node if a pod has a PDB that would be violated or if a pod cannot be rescheduled

**You should know how to answer:**
- "What is the difference between HPA and Cluster Autoscaler?"
- "If HPA adds pods but they're all Pending — what does that tell you and what fixes it?"
- "What prevents Cluster Autoscaler from removing a node?"

---

## Completion Checklist

- [ ] Use `kubectl top` to identify resource-hungry pods/nodes
- [ ] Deploy and navigate Prometheus + Grafana via Helm
- [ ] Write PromQL queries to answer operational questions
- [ ] Create a PrometheusRule alert and trigger it
- [ ] Use `kubectl logs` effectively including previous container logs
- [ ] Explain the three pillars of observability to an interviewer
- [ ] Define an SLO and create an alert that fires on SLO breach
- [ ] Explain the difference between HPA and Cluster Autoscaler and when each fires

---

## Interview Questions This Task Prepares You For

- "How do you monitor a Kubernetes cluster? Walk me through your stack."
- "An alert fired for high memory usage on a node. What do you do?"
- "How do you access logs for a pod that already crashed?"
- "What is Prometheus and how does it collect metrics?"
- "How do you expose application metrics from a pod to Prometheus?"
- "What is the difference between monitoring and observability?"
- "What is an SLO and how does it drive your alerting strategy?"
- "HPA scaled up our app but the pods are stuck Pending. What happened?"
- "We get paged on every CPU spike even when users aren't affected. How do you improve the alerting?"
- "What is the difference between monitoring and observability?"

---

## Mini Project — Monitoring Dashboard for team-alpha API

> Estimated time: 2–3 hours. Put this in GitHub under `k8s-practice/task-06/`.

**Scenario:** `team-alpha`'s API is running. You need full observability — metrics, a dashboard, and an alert that fires before users notice a problem.

**Deliverables:**

1. `helm-values-monitoring.yaml` — Your custom values for `kube-prometheus-stack` Helm install (at minimum: set Grafana admin password, enable persistence false for local use)
2. `service-monitor.yaml` — A ServiceMonitor targeting `team-alpha` API pods (use the `prometheus-example-app` or instrument your own app)
3. `prometheus-rule.yaml` — Two alert rules:
   - `APIHighRestartRate`: fires if any pod in `team-alpha` restarts more than 3 times in 10 minutes
   - `APIHighErrorRate`: fires if HTTP 5xx responses exceed 5% of total requests (use the example app metrics)
4. `grafana-dashboard.json` — Export your Grafana dashboard as JSON (Grafana → Dashboard → Share → Export). It should show:
   - Pod restart count over time
   - CPU and memory usage for `team-alpha` pods
   - HTTP request rate (if using instrumented app)

**Proof of completion (README.md):**
- Screenshot of your Grafana dashboard
- Screenshot of a Firing alert in Prometheus UI (trigger it with a crashing pod)
- The PromQL query you wrote for the restart rate alert
- One paragraph: what would you add to this monitoring setup if this were a real production service?

---

**Next: Task-07-Troubleshooting.md**
