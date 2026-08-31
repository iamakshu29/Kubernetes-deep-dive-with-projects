#!/bin/bash

set -Eeuo pipefail

echo "============================================================"
echo "Verifying cluster is reachable"
kubectl cluster-info >/dev/null

echo "============================================================"
echo "Applying RBAC (ServiceAccounts, Roles, RoleBindings)"
kubectl apply -f 01_RBAC/

echo "============================================================"
echo "Applying ResourceQuota and LimitRange"
kubectl apply -f 02_limitRange_and_resourceQuota/limitRange.yml
kubectl apply -f 02_limitRange_and_resourceQuota/resourceQuota.yml

echo "============================================================"
echo "Applying Kyverno Policies"
kubectl apply -f 03_kyverno/

echo "============================================================"
echo "Applying ConfigMaps"
kubectl apply -f 04_configMap/

echo "============================================================"
echo "Applying App Deployments and Services"
kubectl apply -f 05_App/

echo "============================================================"
echo "Waiting for all pods to be Ready"
kubectl wait \
--for=condition=Ready pod \
--all \
-n google-microservice \
--timeout=300s

echo "============================================================"
echo "Applying HPA"
kubectl apply -f 06_hpa/hpa.yml

echo "============================================================"
echo "Applying Ingress"
kubectl apply -f 07_ingress/

echo "============================================================"
echo "Applying PDB"
kubectl apply -f 08_pdb/

echo "============================================================"
echo "Applying NetworkPolicy (last, after pods are Running)"
kubectl apply -f 09_policy/

echo "============================================================"
echo "Deployment complete"
echo ""
kubectl get pods -n google-microservice
echo ""
echo "App : curl -k -H "Host: boutique.example.com" https://localhost"
