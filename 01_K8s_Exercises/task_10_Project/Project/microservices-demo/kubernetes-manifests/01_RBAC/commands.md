# ServiceAccount

```bash
kubectl create serviceaccount devops-admin -n google-microservice --dry-run=client -o yaml > app_serviceAccount.yml
kubectl create serviceaccount deployer -n google-microservice --dry-run=client -o yaml > app_serviceAccount.yml
kubectl create serviceaccount readonly -n google-microservice --dry-run=client -o yaml > app_serviceAccount.yml
```

# Role

```bash
kubectl create role devOps-admin --verb="*" --resource="*" -n google-microservice --dry-run=client -o yaml > devOps_admin-role.yml

kubectl create role deployer \
--verb=get,list,watch,create,update \
--resource=deployments,services,secrets \
--verb=get,list,watch,update \
--resource=configmaps \
--verb=get,list,watch,create,update,patch,delete \
--resource=jobs \
--verb=get,list,watch \
--resource=pods,pods/status \
-n google-microservice --dry-run=client -o yaml > deployer-role.yml

kubectl create role readonly --verb="list,watch,get" --resource="*" -n google-microservice --dry-run=client -o yaml > readonly-role.yml
```

# Role Binding

```bash
kubectl create rolebinding devops-admin-binding --role=devOps-admin --serviceaccount=google-microservice:devOps-admin -n google-microservice
kubectl create rolebinding deployer-binding --role=deployer --serviceaccount=google-microservice:deployer -n google-microservice
kubectl create rolebinding readonly-binding --role=readonly --serviceaccount=google-microservice:readonly -n google-microservice
```
