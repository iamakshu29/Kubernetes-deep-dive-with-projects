# Grafana — Quick Reference Notes

## URL and Login
```bash
kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring
# http://localhost:3000
# Default: admin / prom-operator
```

---

## Data Sources
Grafana visualises data — it does not store it. It reads from a **data source**.

- `kube-prometheus-stack` auto-configures Prometheus as the default data source
- To verify: **Connections → Data Sources → Prometheus → Save & Test**
- To add Loki (logs): **Connections → Data Sources → Add → Loki** → URL: `http://loki:3100`

---

## Panel Types

| Type | Use for |
|---|---|
| **Time series** | Any metric over time — CPU, memory, request rate |
| **Stat** | Single current value with colour threshold — error rate, uptime |
| **Gauge** | Single value as % of a range — disk usage, quota utilisation |
| **Table** | Compare multiple metrics across multiple pods side by side |
| **Bar chart** | Compare values across labels at a point in time |
| **Logs** | Stream log lines from Loki |
| **Heatmap** | Histogram bucket distribution over time — latency spread |

---

## Creating a Dashboard

```
Dashboards → New → New Dashboard → Add Visualization
```
1. Select data source (Prometheus)
2. Enter PromQL query in the query box
3. Choose visualization type (top right)
4. Set panel title under **Panel options**
5. **Apply** → **Save dashboard** (floppy icon)

**Keyboard shortcuts inside a panel editor:**
- `Ctrl+S` — save
- `Escape` — exit panel edit back to dashboard

---

## Dashboard Variables (Templating)

Variables create dropdowns that filter all panels using them.

```
Dashboard Settings (gear icon) → Variables → Add variable
```

| Field | Value |
|---|---|
| Name | `namespace` |
| Type | Query |
| Data source | Prometheus |
| Query | `label_values(kube_pod_info, namespace)` |

Use in panel queries: `container_memory_usage_bytes{namespace="$namespace"}`

**Common variable queries:**
```promql
label_values(kube_pod_info, namespace)          # all namespaces
label_values(kube_pod_info{namespace="$namespace"}, pod)  # pods in selected ns
label_values(kube_node_info, node)              # all nodes
```

---

## Thresholds and Colour Coding

In any panel → **Field** tab (right side) → **Thresholds**:
- Click **+ Add threshold**
- Enter a value and pick a colour (green/orange/red)
- The panel background or value colour changes when the metric crosses the threshold

---

## Importing Dashboards

```
Dashboards → New → Import
```
- **By ID:** enter a dashboard ID from [grafana.com/grafana/dashboards](https://grafana.com/grafana/dashboards)
- **By JSON:** upload a `.json` file (useful for dashboards committed to Git)

**Useful dashboard IDs:**
| ID | Dashboard |
|---|---|
| 15760 | Kubernetes pod resource usage |
| 1860 | Node Exporter full (host metrics) |
| 13770 | Kubernetes all-in-one cluster monitoring |
| 12740 | Kubernetes persistent volumes |

---

## Exporting a Dashboard

```
Dashboard → Share icon (top bar) → Export → Save to file
```
Saves as `<name>.json`. Commit to Git. On a new cluster: Import → upload JSON → dashboard restored.

**Auto-provisioning via Helm values** (GitOps approach):
```yaml
# in kube-prometheus-stack values.yaml
grafana:
  dashboardProviders:
    dashboardproviders.yaml:
      providers:
      - name: custom
        folder: Custom
        type: file
        options:
          path: /var/lib/grafana/dashboards/custom
  dashboards:
    custom:
      my-dashboard:
        json: |
          { ... dashboard JSON ... }
```

---

## Alerting in Grafana vs Prometheus Alertmanager

| | Grafana Alerting | Prometheus Alertmanager |
|---|---|---|
| Defined in | Grafana UI / YAML | `PrometheusRule` CRD |
| Managed by | Grafana | Prometheus Operator |
| Routing | Grafana contact points | Alertmanager routes |
| **Use when** | Simple threshold alerts on dashboards | SLO-based, multi-condition, team routing |

For K8s production: prefer **PrometheusRule + Alertmanager** (code-reviewable, Git-storable).

---

## Loki (Logs in Grafana)

Once Loki data source is added:
- **Explore** (compass icon) → select Loki data source
- Use **LogQL** to query:
  ```logql
  {namespace="team-alpha"}                          # all logs from namespace
  {namespace="team-alpha", pod=~"alpha-api-.*"}     # filter by pod
  {namespace="team-alpha"} |= "ERROR"               # grep for ERROR
  {namespace="team-alpha"} | json | level="error"   # parse JSON logs
  ```

---

## Useful Shortcuts

| Action | Shortcut |
|---|---|
| Refresh dashboard | `d r` |
| Edit a panel | Click panel title → Edit |
| Duplicate a panel | Click panel title → More → Duplicate |
| View panel in full screen | Click panel title → View |
| Toggle legend | `v` |
