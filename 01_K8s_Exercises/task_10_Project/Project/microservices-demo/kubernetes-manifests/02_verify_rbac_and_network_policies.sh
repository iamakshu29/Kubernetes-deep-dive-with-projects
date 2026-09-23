#!/bin/bash

echo "============================================================================================================="
echo "Checking Role and their Permissions.."
echo "============================================================================================================="
echo ""
echo "Getting deployer role actions"
kubectl describe role deployer

echo "Getting devops-admin role actions"
kubectl describe role devops-admin

echo "Getting readonly role actions"
kubectl describe role readonly
echo ""
echo "Checking Permissions for 'readonly' role"

echo "---------------------------------------------------------------------------------------------"
echo "Should output No"

echo "-----------------------------------------------"
echo "kubectl auth can-i delete deploy --as=system:serviceaccount:google-microservice:readonly"
kubectl auth can-i delete deploy --as=system:serviceaccount:google-microservice:readonly

echo "-----------------------------------------------"
echo "kubectl auth can-i delete pods --as=system:serviceaccount:google-microservice:readonly"
kubectl auth can-i delete pods --as=system:serviceaccount:google-microservice:readonly
echo ""
echo "---------------------------------------------------------------------------------------------"
echo "Should output yes"

echo "-----------------------------------------------"
echo "kubectl auth can-i get deploy --as=system:serviceaccount:google-microservice:readonly"
kubectl auth can-i get deploy --as=system:serviceaccount:google-microservice:readonly

echo "-----------------------------------------------"
echo "kubectl auth can-i get pods --as=system:serviceaccount:google-microservice:readonly"
kubectl auth can-i get pods --as=system:serviceaccount:google-microservice:readonly

echo ""
echo "============================================================================================================="
echo "Checking Network Policies and their Permissions.."
echo "============================================================================================================="
echo ""

echo "-----------------------------------------------"
kubectl get networkpolicy | grep frontend
echo "Ingress - Get Request From ingress at Port 8080, loadgenerator at Port 8080"
echo "Egress - Send Request To adservice at Port 9555, cartservice at Port 7070, checkoutservice at Port 5050, currencyservice at Port 7000, productcatalogservice at Port 3550, recommendationservice at Port 8080, shippingservice at Port 50051"
echo ""
echo "-----------------------------------------------"
kubectl get networkpolicy | grep cartservice
echo "Ingress - Get Request From frontend at Port 7070, checkoutservice at Port 7070"
echo "Egress - Send Request To redis-cart at Port 6379"
echo ""
echo "-----------------------------------------------"
kubectl get networkpolicy | grep checkoutservice
echo "Ingress - Get Request From frontend at Port 5050"
echo "Egress - Send Request To cartservice at Port 7070, productcatalogservice at Port 3550, shippingservice at Port 50051, paymentservice at Port 50051, emailservice at Port 8080, currencyservice at Port 7000"
echo ""
echo "-----------------------------------------------"
kubectl get networkpolicy | grep currencyservice
echo "Ingress - Get Request From frontend at Port 7000, checkoutservice at Port 7000"
echo "Egress - Blocked Completely"
echo ""
echo "-----------------------------------------------"
kubectl get networkpolicy | grep emailservice
echo "Ingress - Get Request From checkoutservice at Port 8080"
echo "Egress - Blocked Completely"
echo ""
echo "-----------------------------------------------"
kubectl get networkpolicy | grep adservice
echo "Ingress - Get Request From frontend at Port 9555"
echo "Egress - Blocked Completely"
echo ""
echo "-----------------------------------------------"
kubectl get networkpolicy | grep loadgenerator
echo "Ingress - Blocked Completely"
echo "Egress - Send Request To frontend at Port 80"
echo ""
echo "-----------------------------------------------"
kubectl get networkpolicy | grep paymentservice
echo "Ingress - Get Request From checkoutservice at Port 50051"
echo "Egress - Blocked Completely"
echo ""
echo "-----------------------------------------------"
kubectl get networkpolicy | grep productcatalogservice
echo "Ingress - Get Request From frontend at Port 3550, checkoutservice at Port 3550, recommendationservice at Port 3550"
echo "Egress - Blocked Completely"
echo "-----------------------------------------------"
kubectl get networkpolicy | grep recommendationservice
echo "Ingress - Get Request From frontend at Port 8080"
echo "Egress - Send Request To productcatalogservice at Port 3550"
echo ""
echo "-----------------------------------------------"
kubectl get networkpolicy | grep redis-cart
echo "Ingress - Get Request From cartservice at Port 6379"
echo "Egress - Blocked Completely"
echo ""
echo "-----------------------------------------------"
kubectl get networkpolicy | grep shippingservice
echo "Ingress - Get Request From frontend at Port 50051, checkoutservice at Port 50051"
echo "Egress - Blocked Completely"
echo ""
echo "-----------------------------------------------"