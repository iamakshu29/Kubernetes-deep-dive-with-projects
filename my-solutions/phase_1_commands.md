# Task 1.1 — Namespace Isolation

### My Notes & Commands

```bash

# Create separate namespace
>> kubectl create namespace <namespace>
kubectl create namespace team-alpha
kubectl create namespace team-beta

# Deploy a pod in each namespace
>> kubectl run <pod_name> --image=<img_name> -n <namespace>
kubectl run frontend --image=nginx:alpine -n team-alpha
kubectl run frontend --image=nginx:alpine -n team-beta

# Verify
>> kubectl get pod <pod_name> -n <namespace>
kubectl get pod frontend -n team-alpha
kubectl get pod frontend -n team-beta

# Setting a namesapce as default
>> kubectl config set-context --current --namespace=<namespace>

```


# Task 1.2 — Labels and Selectors Deep Dive

### My Notes & Commands

```bash

# Create pod (not via deployment) using labels
>> kubectl run <pod_name> --image=<img_name> --labels='<key1>=<value1>,<key2>=<value2>'

# List the labelled pods using Selectors
>> kubectl get pods --selector='<key1>=<value1>,<key2>=<value2>'

# Command to create a service and attach it to an existing workload  automatically using its label selector
>> kubectl expose <resource_type> <resource_name> --name=<svc_name> --type=<svc_type> --port=<host_port> --target-port=<container_port> # target-port is optional, ClusterIP is default (if type flag not provided)

# To create a service only, then edit it using manifest files
>> kubectl create service <service_type> <service_name> --tcp=<host_port>:<target_port>

```

# Task 1.3 — Watch the Control Loop in Action

### My Notes & Commands

```bash

# create deployment with n replicas
>> kubectl create deployment <deployment_name> --image=<image:tag> --replicas=<replica_count>

# delete a pod and watch it
>> kubectl delete pods <pod_name>
>> kubectl get pods -w

# scale in/out replicas to 0 then back to 3
>> kubectl scale --replicas=<replica_count> <resource_type>/<resource_name>

```