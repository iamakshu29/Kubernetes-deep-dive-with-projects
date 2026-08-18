#!/bin/bash
set -euo pipefail

echo "============================="
echo "Running the Pre-Req Script"
./pre-req.sh 
echo "=============================="

echo ""

echo "========================================="
echo "Simulating shell script as CI Pipeline."
echo "========================================="

read -p "Enter the username - " user
read -s -p "Enter the password/token - " pass

echo "========================================="
echo "Dev Pushes Code"

echo ""

echo "========================================="
echo "Unit Test Run"

echo ""

echo "========================================="
echo "Integration Test Run"

echo ""

echo "========================================="
echo "OWASP scanning dependency files"

echo ""

echo "========================================="
echo "sonarQube scanning"

echo ""

echo "========================================="
echo "Build docker image"
echo "docker build -t image:tag ."

echo ""

echo "========================================="
echo "Login to DockerHub"
echo "docker login -u $user -p $pass"

echo ""

echo "========================================="
echo "Push docker image to DockerHub"
echo "docker tag image:tag docker.io/$user/image:tag"

echo ""

echo "================================================"
echo "Helm Upgrade to new image"
helm upgrade --install alpha-api-prod ../Exercise-3/alpha-api/ \
-f ../Exercise-3/alpha-api/values-prod.yaml  \
--set backend.image.tag=alpine \
--namespace prod-env \
--wait \
--timeout 100s \
--rollback-on-failure

echo ""

echo "================================================"
echo "Verify After Upgrade"

echo ""

helm status alpha-api-prod -n prod-env