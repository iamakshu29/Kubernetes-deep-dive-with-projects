# Task 2.1 — Deploy a Multi-Tier Application

### My Notes & Commands

```bash

# Deploy pod for frontend and backend
>> kubectl create deployment <dep_name> --image=<img_name> -n <namespace>
kubectl create deployment frontend --image=nginx:alpine
kubectl create deployment backend --image=hashicorp/http-echo

# To edit the manifest file
>> export KUBE_EDITOR="code --wait"
>> kubectl edit deployment backend

# Add arg attribute under spec and the arg to use
spec:
  containers:
    args:
      - "-text=Hello from backend"

# To check the YAML
>> kubectl get deployment backend -o yaml

# Create Services for frontend (target_port:5678) and backend (target_port:80)
>> kubectl expose <resource_type> <resource_name> --name=<svc_name> --type=<svc_type> --port=<host_port> --target-port=<target_port> # target-port is optional, ClusterIP is default (if type flag not provided)

# frontend accessible from browser, NodePort
kubectl expose deployment frontend --name=front-svc --type=NodePort --port=80 --target-port=80
# backend reachable from frontend not outside, ClusterIP
kubectl expose deployment backend --name=back-svc --port=9090 --target-port=5678

# Verify the services
kubectl get svc

# Access the Backend Pod from Frontend
>> kubectl exec -it frontend-<pod_name> -- sh
>> curl <backend_clusterIP>:<backend_host_port>
curl 10.96.58.212:9090
OR
>> curl http://<backend_svc-name>:<backend_host_port> # (Recommended)
curl http://back-svc:9090

Hello from backend # OUTPUT

# To access the pods or Service from internet, we can't access using NodePort:NodeIp due to Kind Cluster restriction
# So we do port-forward and can access any Service or Pod

kubectl port-forward pod/<pod_name> <host_port>:<target_port> # pod_port 5678,80
kubectl port-forward svc/<svc_name> <host_port>:<target_port> # service_port 9090,80

```


# Task 2.2 — Health Probes Done Right

### My Notes & Commands

```bash

kubectl create deployment is-ready --image=nginx:alpine

kubectl edit deployment is-ready

  startupProbe:
    httpGet:
      path: /
      port: 80
    failureThreshold: 30
    periodSeconds: 10
  livenessProbe:
    httpGet:
      path: /
      port: 80
    initialDelaySeconds: 10
    periodSeconds: 5
    timeoutSeconds: 3
    failureThreshold: 3
  readinessProbe:
    httpGet:
      path: /
      port: 80
    periodSeconds: 5

kubectl get pods -w
```

# Task Task 2.3 — Configuration and Secrets

### My Notes & Commands

```bash

# Create ConfigMap
>> kubectl create configmap <configMap_name> --from-literal=key1=config1 --from-literal=key2=config2
kubectl create configmap my-config --from-literal=color=red --from-literal=cloud=aws

# Create Secret
>> kubectl create secret <secret_type> <secret_name> --from-literal=key1=supersecret --from-literal=key2=topsecret
kubectl create secret generic my-secret --from-literal=db-password=secretPass123

# Verify
kubectl get configmap
kubectl get secret

# Create a DB Pod manifest and inject the configMap and secrets manually (preferred approach) 
kubectl run postgres --image=postgres:15 --dry-run=client -o yaml > postgres_pod.yaml

# code for injecting configMap and secret map
  env:
    - name: APP_ENV
      valueFrom:
        configMapKeyRef:
          name: <config_name>
          key: <config_key>

    - name: POSTGRES_PASSWORD_FILE
      value: /etc/secrets/db-password
  # Mount Secret as files
  volumeMounts:
    - name: secret-volume
      mountPath: /etc/secrets
      readOnly: true

volumes:
  - name: secret-volume
    secret:
      secretName: <secret_name>

# Verify env vairables are correctly configured
kubectl exec -it postgres -- sh
echo $APP_ENV
cat /etc/secrets/db-password

```

# Task 2.4 — Rolling Updates and Rollbacks

### My Notes & Commands

```bash

# Create deployment manifest with 3 replicas
kubectl create deployment nginx --image=nginx:1.24 --replicas=3 --dry-run=client -o yaml > nginx_dep.yaml

# add strategy section and change image to 1.25
strategy:
   type: RollingUpdate
   rollingUpdate:
     maxSurge: 1
     maxUnavailable: 1

# set up a broken image
>> kubectl set image deployment/<deployment-name> <container-name>=<image>:<tag>
kubectl set image deployment/nginx nginx=nginx:doesnotexist

# Rollback to last stable version
>> kubectl rollout undo deployment/<deployment-name>
kubectl rollout undo deployment/nginx

# To verify
>> kubectl rollout status deployment/<deployment-name>
kubectl rollout status deployment/nginx

```

# Task 2.5 — Resource Requests, Limits, and Quotas

### My Notes & Commands

```bash

# create namespace
kubectl create ns team-alpha

# Verify LimitRange and ResourceQuota
kubectl get LimitRange default-limits
kubectl get ResourceQuota team-alpha-quota

# Error we get if the pod exceeds the ResourceQuota
Error from server (Forbidden): error when creating "check_pod.yml": pods "check-pod" is forbidden: exceeded quota: team-alpha-quota, requested: requests.cpu=7,requests.memory=1536Mi, used: requests.cpu=0,requests.memory=0, limited: requests.cpu=5,requests.memory=1Gi

```