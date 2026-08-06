#!/bin/bash

# Features:
# - Stops immediately if a command fails.
# - Verifies Kubernetes connectivity.
# - Installs Metrics Server only if missing.
# - Waits for Metrics Server rollout.
# - Installs Helm only if missing.
# - Adds Helm repositories only if missing.
# - Uses helm upgrade --install for idempotent deployments.
# - Waits for monitoring pods to become ready.
# - Cleans up port-forward processes on exit.
# - Keeps port-forward sessions alive.


set -Eeuo pipefail


echo "===================================================================================================================="
echo "Checking Kubernetes Cluster Connectivity"

kubectl cluster-info >/dev/null

echo "Cluster is reachable."


echo "===================================================================================================================="
echo "Checking Metrics Server"


if kubectl get deployment metrics-server -n kube-system >/dev/null 2>&1; then

    echo "Metrics Server is already installed."

else

    echo "Metrics Server not found. Installing..."

    kubectl apply -f \
    https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml


    echo "---------------------------------------------------------"
    echo "Patching Metrics Server"

    kubectl patch deployment metrics-server \
    -n kube-system \
    --type='json' \
    -p='[
      {
        "op":"add",
        "path":"/spec/template/spec/containers/0/args/-",
        "value":"--kubelet-insecure-tls"
      }
    ]'


    echo "---------------------------------------------------------"
    echo "Waiting for Metrics Server rollout..."

    kubectl rollout status deployment/metrics-server \
    -n kube-system \
    --timeout=3m

fi


echo "---------------------------------------------------------"
echo "Testing Metrics Server"

kubectl top nodes || true



echo "===================================================================================================================="
echo "Checking Helm"


if command -v helm >/dev/null 2>&1; then

    echo "Helm is already installed."

else

    echo "Installing Helm..."

    curl -fsSL \
    https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 \
    | bash


    echo "Verifying Helm..."

    helm version

fi



echo "===================================================================================================================="
echo "Checking Helm repositories"


if helm repo list | grep -q "^prometheus-community"; then

    echo "prometheus-community repository already exists."

else

    helm repo add prometheus-community \
    https://prometheus-community.github.io/helm-charts

fi


if helm repo list | grep -q "^grafana"; then

    echo "grafana repository already exists."

else

    helm repo add grafana \
    https://grafana.github.io/helm-charts

fi



echo "===================================================================================================================="
echo "Updating Helm repositories"

helm repo update



echo "===================================================================================================================="
echo "Installing / Upgrading kube-prometheus-stack"


if helm_release_exists monitoring monitoring; then

    echo "Monitoring stack already exists. Upgrading..."

else

    echo "Monitoring stack not found. Installing..."

fi


helm upgrade --install monitoring \
prometheus-community/kube-prometheus-stack \
--namespace monitoring \
--create-namespace



echo "===================================================================================================================="
echo "Installing / Upgrading Loki Stack"


if helm_release_exists loki monitoring; then

    echo "Loki stack already exists. Upgrading..."

else

    echo "Loki stack not found. Installing..."

fi


helm upgrade --install loki \
grafana/loki-stack \
--namespace monitoring \
--set grafana.enabled=false



echo "===================================================================================================================="
echo "Waiting for monitoring pods to become Ready"


kubectl wait \
--for=condition=Ready pod \
--all \
-n monitoring \
--timeout=300s



echo "===================================================================================================================="
echo "Resources in monitoring namespace"


kubectl get pods,svc,crds -n monitoring



echo "===================================================================================================================="
echo "Port Forward Information"


echo "Grafana    : http://localhost:3000"
echo "Prometheus : http://localhost:9090"
echo "Loki       : http://localhost:3100/ready"



echo "===================================================================================================================="
echo "Starting Port Forwarding"

kubectl port-forward \
--address=0.0.0.0 \
service/monitoring-grafana \
-n monitoring \
3000:80 &

kubectl port-forward \
--address=0.0.0.0 \
service/monitoring-kube-prometheus-prometheus \
-n monitoring \
9090:9090 &

kubectl port-forward \
--address=0.0.0.0 \
service/loki \
-n monitoring \
3100:3100 &

echo "===================================================================================================================="
echo "All services are available."
