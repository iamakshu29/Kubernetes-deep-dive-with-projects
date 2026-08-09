- I will deploy the app in 3 env, using helm 
    - dev
    - staging
    - prod

so creating manifest in dev for testing and all

```bash
git clone --depth 1 --branch release/v0.10.6 https://github.com/GoogleCloudPlatform/microservices-demo.git
```


```bash
# kubectl autocomplete
source <(kubectl completion bash) # set up autocomplete in bash into the current shell, bash-completion package should be installed first.
echo "source <(kubectl completion bash)" >> ~/.bashrc # add autocomplete permanently to your bash shell.
```

```bash
# use alias for kubectl as k
alias k=kubectl
complete -o default -F __start_kubectl k
```

```bash
# Traverse to Project workspace
cd /c/Users/Lenovo/Desktop/K8s/Kubernetes-deep-dive-with-projects/K8s-Exercises/task_09-Project/Project
```


```bash
# Create Namespace
kubectl create ns dev

kubectl config set-context --current --namespace dev
```


## Phase 1 — Foundation: Cluster & Base Workloads

```bash
# Create deployment 
kubectl create deploy boutique-app --replicas=3 --image=gcr.io/google-samples/microservices-demo -n dev --dry-run=client -o yaml > deployment.yml
```

```bash
# Create Services for deployment
kubectl expose service boutique-app --port=80 -n dev --dry-run=client -o yaml > app-service.yml
```

```bash
# Create Services for statefuleset
kubectl expose service redis-cart --cluster-ip='None' -n dev --dry-run=client -o yaml > redis-service.yml
```