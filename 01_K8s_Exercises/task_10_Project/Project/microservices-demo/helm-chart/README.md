# Online Boutique — Helm Chart

Helm chart for deploying the Online Boutique microservices demo on Kubernetes.

## Prerequisites

| Tool                     | Version                                           |
| ------------------------ | ------------------------------------------------- |
| Helm                     | >= 3.10                                           |
| kubectl                  | >= 1.27                                           |
| Kubernetes               | >= 1.27                                           |
| NGINX Ingress Controller | any (if `ingress.enabled: true`)                  |
| Kyverno                  | >= 1.11 (only if `kyvernoPolicies.enabled: true`) |

---

## Quick Start (local kind cluster)

```bash
# Create namespace
kubectl create namespace google-microservice

# Install with defaults
helm upgrade --install boutique ./helm-chart \
  --namespace google-microservice \
  --create-namespace
```

---

# helm lint - check for errors

```bash
 helm lint ./helm-chart -f ./helm-chart/values.yaml -f ./helm-chart/values-dev.yaml
```

## Dev Environment

```bash
kubectl create namespace google-microservice-dev

# Reduced resources, no HPA/PDB, load generator enabled, Kyverno in Audit mode
helm upgrade --install boutique ./helm-chart \
  -f ./helm-chart/values.yaml \
  -f ./helm-chart/values-dev.yaml \
  --namespace google-microservice-dev \
  --create-namespace
```

"App: curl -k -H "Host: dev.boutique.local" https://localhost"

---

## Prod Environment

```bash
kubectl create namespace google-microservice

# Full resources, HPA + PDB enabled, load generator off, Kyverno in Enforce mode
helm upgrade --install boutique ./helm-chart \
  -f ./helm-chart/values.yaml \
  -f ./helm-chart/values-prod.yaml \
  --namespace google-microservice \
  --create-namespace
```

"App: curl -k -H "Host: boutique.example.com" https://localhost"

---

## Upgrade

```bash
# Dev
helm upgrade boutique ./helm-chart \
  -f ./helm-chart/values.yaml -f ./helm-chart/values-dev.yaml \
  --namespace google-microservice-dev

# Prod
helm upgrade boutique ./helm-chart \
  -f ./helm-chart/values.yaml -f ./helm-chart/values-prod.yaml \
  --namespace google-microservice
```

---

## Uninstall

```bash
helm uninstall boutique --namespace google-microservice
kubectl delete namespace google-microservice
```

---

## Dry Run / Template Preview

```bash
# Render templates without deploying
helm template boutique ./helm-chart -f ./helm-chart/values.yaml -f ./helm-chart/values-prod.yaml

# Validate against the cluster API
helm upgrade --install boutique ./helm-chart \
  -f ./helm-chart/values.yaml -f ./helm-chart/values-prod.yaml \
  --namespace google-microservice \
  --dry-run
```

## Values Files

| File               | Purpose                                                      |
| ------------------ | ------------------------------------------------------------ |
| `values.yaml`      | Base defaults — always applied first                         |
| `values-dev.yaml`  | Dev overrides — reduced resources, no HPA/PDB, Kyverno Audit |
| `values-prod.yaml` | Prod overrides — full resources, HPA+PDB on, Kyverno Enforce |

Image tag defaults to the chart `appVersion` (`v0.10.6`) when `images.tag` is left empty.
The prod values file pins this explicitly; dev inherits it from the chart.

---

## Debugging

```bash
# Check release status
helm status boutique -n google-microservice

# List all resources deployed
helm get manifest boutique -n google-microservice

# Check pod status
kubectl get pods -n google-microservice

# View logs for a service
kubectl logs -n google-microservice deploy/frontend

# Describe a failing pod
kubectl describe pod -n google-microservice -l app=frontend
```

---

## Key Configuration Reference

| Key                                       | Default                                                            | Description                                                 |
| ----------------------------------------- | ------------------------------------------------------------------ | ----------------------------------------------------------- |
| `images.repository`                       | `us-central1-docker.pkg.dev/online-boutique-ci/microservices-demo` | Container image repository                                  |
| `images.tag`                              | `""` (uses chart appVersion)                                       | Image tag for all services                                  |
| `networkPolicies.create`                  | `false`                                                            | Deploy per-service NetworkPolicies + default-deny-allow-dns |
| `securityContext.enable`                  | `true`                                                             | Set pod-level `runAsNonRoot`, `fsGroup` etc.                |
| `seccompProfile.enable`                   | `false`                                                            | Apply seccomp `RuntimeDefault` profile                      |
| `kyvernoPolicies.enabled`                 | `false`                                                            | Deploy Kyverno validation policies                          |
| `kyvernoPolicies.validationFailureAction` | `Audit`                                                            | `Audit` logs violations; `Enforce` blocks them              |
| `loadGenerator.create`                    | `true`                                                             | Deploy the Locust load generator                            |
| `ingress.enabled`                         | `true`                                                             | Create an NGINX Ingress for the frontend                    |
| `ingress.host`                            | `""`                                                               | Hostname for the Ingress rule (empty = all hosts)           |
| `<service>.hpa.enabled`                   | varies                                                             | Enable HorizontalPodAutoscaler for the service              |
| `<service>.pdb.enabled`                   | varies                                                             | Enable PodDisruptionBudget for the service                  |
| `<service>.antiAffinity`                  | varies                                                             | Spread pods across nodes via preferredDuringScheduling      |
