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

