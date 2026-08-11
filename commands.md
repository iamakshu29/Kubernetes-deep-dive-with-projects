## Below are the CLI commands to create the resources. Apart from this we need manifest files to create the resources unable to create using CLI.

- Get the Attribute of Resources
```
kubectl explain <resource_name>

kubectl explain <resource_name> --recursive

kubectl explain <resource_name>.<attribute>
```

- Create namespace
```
kubectl create ns <namespace_name>
```

- Label resource
```
kubectl label <resource_type> <resource_name> key1=value1 key2=value2 -n <namespace_name>

# Remove a label — append minus sign after the key
kubectl label <resource_type> <resource_name> <key>- -n <namespace_name>
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
kubectl create service clusterip <service_name> --tcp=<port>:<target_port> -n <namespace_name> --dry-run=client -o yaml > service.yml

kubectl create service nodeport <service_name> --tcp=<port>:<target_port> --node-port=<nodeport_num> -n <namespace_name> --dry-run=client -o yaml > service.yml

kubectl create service loadbalancer <service_name> --tcp=<port>:<target_port> -n <namespace_name> --dry-run=client -o yaml > service.yml
```

- Expose an existing Deployment as a Service
```
kubectl expose deployment <deploy_name> --type=ClusterIP --port=<service_port> --target-port=<container_port> -n <namespace_name>
```

- Create Ingress
```
kubectl create ingress <ingress_name> --class=nginx --rule="<host>/<path>=<service_name>:<port>,tls=<secret_name>" -n <namespace_name> --dry-run=client -o yaml > ingress.yml
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
kubectl create role <role_name> --verb=get,list,watch --resource=pods -n <namespace_name> --dry-run=client -o yaml > role.yml
```

- Create serviceAccount
```
kubectl create serviceaccount <sa_name> -n <namespace_name> --dry-run=client -o yaml > sa.yml
```

- Create roleBinding
```
kubectl create rolebinding <rolebind_name> --role=<role_name> --serviceaccount=<namespace_name>:<sa_name> -n <namespace_name> --dry-run=client -o yaml > role_binding.yml
```

- Create HPA (CLI creates v1 — use manifest for v2 which is recommended)
```
kubectl autoscale deployment <deploy_name> --min=<min_pod> --max=<max_pod> --cpu-percent=<percent> -n <namespace_name> --dry-run=client -o yaml > hpa.yml
```

---

## Debugging & Inspection Commands

- Get resources
```
kubectl get <resource_type> -n <namespace_name>
kubectl get <resource_type> -A                      # all namespaces
kubectl get <resource_type> -o wide                 # extra columns (node, IP)
kubectl get <resource_type> -o yaml                 # full YAML output
kubectl get <resource_type> --show-labels
kubectl get <resource_type> -w                      # watch live
```

- Describe resource (events + full spec)
```
kubectl describe <resource_type> <resource_name> -n <namespace_name>
```

- Logs
```
kubectl logs <pod_name> -n <namespace_name>
kubectl logs <pod_name> -n <namespace_name> --previous    # logs from crashed container
kubectl logs <pod_name> -n <namespace_name> -f            # follow live
kubectl logs <pod_name> -n <namespace_name> -c <container_name>  # multi-container pod
```

- Exec into a pod
```
kubectl exec -it <pod_name> -n <namespace_name> -- /bin/sh
kubectl exec -it <pod_name> -n <namespace_name> -- /bin/bash
```

- Scale
```
kubectl scale deployment <deploy_name> --replicas=<num> -n <namespace_name>
```

- Update image
```
kubectl set image deployment/<deploy_name> <container_name>=<new_image>:<tag> -n <namespace_name>
```

- Rollout commands
```
kubectl rollout status deployment/<deploy_name> -n <namespace_name>
kubectl rollout history deployment/<deploy_name> -n <namespace_name>
kubectl rollout undo deployment/<deploy_name> -n <namespace_name>
kubectl rollout undo deployment/<deploy_name> --to-revision=<num> -n <namespace_name>
```

- Port forward
```
kubectl port-forward pod/<pod_name> <local_port>:<pod_port> -n <namespace_name>
kubectl port-forward svc/<service_name> <local_port>:<service_port> -n <namespace_name>
```

- Resource usage (requires metrics-server)
```
kubectl top node
kubectl top pod -n <namespace_name>
```

---

## Resources Only Creatable via Manifest (no CLI create command)
- StatefulSet
- DaemonSet
- NetworkPolicy
- PersistentVolume / PersistentVolumeClaim
- LimitRange
- ResourceQuota
- HorizontalPodAutoscaler v2
- CertificateIssuer / Certificate (cert-manager CRDs)