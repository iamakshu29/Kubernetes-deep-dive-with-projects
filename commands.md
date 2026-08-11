- Get the Attribute of Resources
```
kubectl explain <resource_name>

kubectl explain <resource_name> --recursive

kubectl explain <resource_name>.<attribute>
```

- Create namespace
```
kubectl create ns <namespace_name >
```

- Label resource
```
kubectl label <resource_name> <label_key1>=<label_value1>,<label_key2>=<label_value2>
```

- Create Pod
```
kubectl run <pod_name> --image=<image_name>:<image_tag> -n <namespace_name> --dry-run=client -o yaml > pod.yml
```

- Create Deployment
```
kubectl create deploy <deploy_name> --image=<image_name>:<image_tag> --replicas=<rep_num> -n <namespace_name> --dry-run=client -o yaml > deployment.yml
```

- Create Service
```
kubectl create service <service_name> --type=ClusterIP/LoadBalancer/NodePort/ExternalName -n <namespace_name> --dry-run=client -o yaml > service.yml
```

- Expose Service without Creating
```
kubectl expose service deploy/<deply_name> --type=ClusterIP/LoadBalancer/NodePort/ExternalName --port=<service_port> --targetPort=<pod/containerPort> -n <namespace_name>
```

- Create Secret
```
kubectl create secret generic <secret_name> --from-literal=key1=value1 --from-literal=key2=value2 -n <namespace_name> --dry-run=client -o yaml > secret.yml
```

- Create configMap
```
kubectl create configmap <map_name> --from-literal=key1=value1 --from-literal=key2=value2 -n <namespace_name> --dry-run=client -o yaml > configmap.yml
```

- Create role
```
kubectl create role <role_name> --verb= --resource= -n <namespace_name> --dry-run=client -o yaml > role.yml
```

- Create serviceAccount
```
kubectl create serviceaccount <sa_name> -n <namespace_name> --dry-run=client -o yaml > sa.yml
```

- Create roleBinding
```
kubectl create roleBidning <rolebind_name> --role=<role_name> --serviceAccount=<sa_name> -n <namespace_name> --dry-run=client -o yaml > role_binding.yml
```

- Create hpa (CLI will create v1) But use only manifest (For v2 {Recommended})
```
kubectl create autoscaling --min=<min_pod> --max=<max_pod> -n <namespace_name> --dry-run=client -o yaml > hpa.yml
```