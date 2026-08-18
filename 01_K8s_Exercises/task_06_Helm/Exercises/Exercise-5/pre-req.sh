#!/bin/bash
set -euo pipefail

echo "=================================================================================================="
echo "Before Upgrading or mimic the CI/CD stage. The Project and helm chart should be present already"
echo "=================================================================================================="

echo ""

echo "=================================="
echo "Checking error in the helm chart"
helm lint ../Exercise-3/alpha-api/

echo "Check if chart is already present or not"
if helm status alpha-api-prod -n prod-env > /dev/null 2>&1; then
    echo "==========================================================="
    echo "Chart is Present, Delete it for a fresh Install for demo"

    echo ""

    echo "============================="
    echo "Deleting the existing Chart"
    helm uninstall alpha-api-prod -n prod-env

else

    echo "==================="
    echo "Chart Not Present"

fi

echo ""

echo "======================="
echo "Installing the Chart"

helm install alpha-api-prod ../Exercise-3/alpha-api/ \
-f ../Exercise-3/alpha-api/values-prod.yaml  \
--namespace prod-env \
--create-namespace --wait --timeout 100s

echo "================================================"
echo "Verify Image Before Upgrade"
kubectl describe deploy redis-check -n prod-env | grep -i hashicorp/http-echo