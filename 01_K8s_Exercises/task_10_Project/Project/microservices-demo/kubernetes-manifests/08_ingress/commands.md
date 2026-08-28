# Ingress

```bash
kubectl create ingress microservices-ingress -n google-microservice --class=nginx --rule="/*=frontend:80" --dry-run=client -o yaml > ingress.yml
```
