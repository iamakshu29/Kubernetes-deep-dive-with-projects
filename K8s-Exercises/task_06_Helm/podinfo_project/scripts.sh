echo "Check if NGINX Ingress Controller is present"

if kubectl get deployment -n ingress-nginx ingress-nginx-controller >/dev/null 2>&1; then
    echo "NGINX Ingress Controller is installed"

else

    echo "NGINX Ingress Controller is installed, Installing it ....."
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

    echo "Verifying"
    kubectl get deployment -n ingress-nginx ingress-nginx-controller

fi

echo "-----------------------------------------------------------------------------------------------------------------------------"

echo "Check if cert-manager is present"

if kubectl get cert-manager >/dev/null 2>&1; then
    echo "cert-manager is installed"

else

    echo "cert-manager is installed, Installing it ....."
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.4/cert-manager.yaml

    echo "Verifying"
    kubectl get cert-manager

fi

echo "-----------------------------------------------------------------------------------------------------------------------------"

echo "Check if Calico is present"

if kubectl get deploy calico-kube-controllers -n kube-system >/dev/null 2>&1; then
    echo "Calico is installed"

else

    echo "Calico is not installed, Installing it ....."
    kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml

    echo "Verifying"
    kubectl get deploy calico-kube-controllers -n kube-system

fi

echo "-----------------------------------------------------------------------------------------------------------------------------"

echo "Creating HPA Manifest"

if [[ -f podinfo-app-hpa.yml ]]; then
    echo "HPA already present"

else

    echo "HPA manifest not preset, creating it"
    kubectl autoscale deployment podinfo-app -n demo --min=2 --max=8 --cpu-percent=50 --dry-run=client -o yaml > podinfo-app-hpa.yml

fi

echo "Applying HPA manifest"
kubectl apply -f podinfo-app-hpa.yml

echo "-----------------------------------------------------------------------------------------------------------------------------"

echo "Checking if Namespace is present and adding PSA labels"

if ! kubectl get ns demo >/dev/null 2>&1; then
    echo "Namespace 'demo' does not exist, creating it..."
    kubectl create ns demo

    echo "Adding PSA Labels"
    
    kubectl label ns demo \
    pod-security.kubernetes.io/warn=restricted \
    pod-security.kubernetes.io/warn-version=latest \
    pod-security.kubernetes.io/enforce=baseline \
    pod-security.kubernetes.io/enforce-version=latest \
    pod-security.kubernetes.io/audit=restricted \
    pod-security.kubernetes.io/audit-version=latest

else
    
    echo "Adding PSA Labels"
    
    kubectl label ns demo \
    pod-security.kubernetes.io/warn=restricted \
    pod-security.kubernetes.io/warn-version=latest \
    pod-security.kubernetes.io/enforce=baseline \
    pod-security.kubernetes.io/enforce-version=latest \
    pod-security.kubernetes.io/audit=restricted \
    pod-security.kubernetes.io/audit-version=latest
    
fi

echo "Show labels"
kubectl get ns demo --show-labels

echo "-----------------------------------------------------------------------------------------------------------------------------"