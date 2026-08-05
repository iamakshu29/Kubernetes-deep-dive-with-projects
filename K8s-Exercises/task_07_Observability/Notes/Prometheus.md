# Prometheus — Quick Reference Notes

## Architecture

```
App / Node / K8s components
        ↓  (expose /metrics endpoint)
Prometheus Server  ←  scrapes on a schedule (default: 15s)
        ↓
Time Series DB (local, on-disk)
        ↓
PromQL queries → Grafana / Alertmanager
```

- Prometheus **pulls** (scrapes) metrics — apps don't push to it
- `kube-prometheus-stack` adds **Prometheus Operator**: manages Prometheus config via CRDs (`ServiceMonitor`, `PrometheusRule`) instead of editing raw YAML config files

---

## Metric Types

| Type | Description | Example |
|---|---|---|
| **Counter** | Only goes up; resets on restart | `http_requests_total`, `container_restarts_total` |
| **Gauge** | Can go up and down | `container_memory_usage_bytes`, `kube_pod_status_ready` |
| **Histogram** | Bucketed observations; tracks count + sum + buckets | `http_request_duration_seconds` |
| **Summary** | Like histogram but calculates quantiles client-side | Less common; prefer Histogram |

**Key rule:** use `rate()` on Counters, query Gauges directly.

---

## PromQL Essentials

### Selectors
```promql
# Exact match
http_requests_total{namespace="team-alpha"}

# Regex match
http_requests_total{pod=~"alpha-api-.*"}

# Not equal
container_cpu_usage_seconds_total{container!=""}
```

### Functions

| Function | Use on | What it does |
|---|---|---|
| `rate(metric[5m])` | Counter | Per-second average rate over 5m window |
| `irate(metric[5m])` | Counter | Instantaneous rate (last two samples) — spiky |
| `increase(metric[1h])` | Counter | Total increase over 1h |
| `sum(metric)` | Any | Aggregate across all label dimensions |
| `sum by (pod)(metric)` | Any | Aggregate, keep the `pod` label |
| `avg_over_time(metric[5m])` | Gauge | Average value over 5m |
| `histogram_quantile(0.95, rate(hist_bucket[5m]))` | Histogram | 95th percentile latency |
| `label_replace(metric, "dst", "$1", "src", "(.*)")` | Any | Rename/add a label |

### Common Queries

```promql
# CPU usage per pod (cores)
rate(container_cpu_usage_seconds_total{container!=""}[5m])

# Memory usage per pod (bytes)
container_memory_usage_bytes{container!=""}

# Pod restarts in last 15m
increase(kube_pod_container_status_restarts_total[15m]) > 0

# Pods NOT running
kube_pod_status_phase{phase!="Running"} == 1

# Node CPU usage %
1 - avg by(node)(rate(node_cpu_seconds_total{mode="idle"}[5m]))

# HTTP success rate (non-5xx)
sum(rate(http_requests_total{code!~"5.."}[5m]))
/
sum(rate(http_requests_total[5m]))
```

---

## Key Components Deployed by kube-prometheus-stack

| Component | What it does |
|---|---|
| **Prometheus** | Scrapes and stores metrics |
| **Alertmanager** | Receives alerts from Prometheus, routes to Slack/PagerDuty/email |
| **Grafana** | Visualises metrics from Prometheus |
| **node-exporter** | DaemonSet on every node — exposes host-level metrics (CPU, disk, network) |
| **kube-state-metrics** | Converts K8s API object state (pod phase, deployment replicas) into metrics |
| **Prometheus Operator** | Watches `ServiceMonitor` and `PrometheusRule` CRDs — manages Prometheus config automatically |

---

## CRDs You Need to Know

### ServiceMonitor
Tells Prometheus Operator which pods to scrape and how.
```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: alpha-api-monitor
  namespace: monitoring            # must be in monitoring ns (or wherever Prometheus watches)
  labels:
    release: monitoring            # must match Prometheus's serviceMonitorSelector
spec:
  namespaceSelector:
    matchNames: [team-alpha]
  selector:
    matchLabels:
      app: alpha-api               # matches the Service label
  endpoints:
  - port: http                     # port name on the Service
    path: /metrics
    interval: 15s
```

### PrometheusRule
Defines alert rules (and recording rules).
```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: alpha-api-alerts
  namespace: monitoring
  labels:
    release: monitoring
spec:
  groups:
  - name: alpha-api
    rules:
    - alert: HighPodRestartRate
      expr: increase(kube_pod_container_status_restarts_total{namespace="team-alpha"}[10m]) > 3
      for: 2m
      labels:
        severity: warning
      annotations:
        summary: "Pod {{ $labels.pod }} restarting frequently"
```

---

## Alert States

| State | Meaning |
|---|---|
| **Inactive** | Expression is false — no problem |
| **Pending** | Expression is true but `for` duration not yet elapsed |
| **Firing** | Expression has been true longer than `for` — alert sent to Alertmanager |

`for: 2m` prevents flapping — a transient spike doesn't page you.

---

## Useful kubectl Commands

```bash
# Check Prometheus targets (are all scrapes healthy?)
kubectl port-forward svc/monitoring-kube-prometheus-prometheus 9090 -n monitoring
# → open http://localhost:9090/targets

# Check Alertmanager
kubectl port-forward svc/monitoring-kube-prometheus-alertmanager 9093 -n monitoring

# See all ServiceMonitors
kubectl get servicemonitor -A

# See all PrometheusRules
kubectl get prometheusrule -A

# Check Prometheus Operator logs (if scraping isn't working)
kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus-operator
```
