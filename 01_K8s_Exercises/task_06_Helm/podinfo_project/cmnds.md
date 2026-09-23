## Namespace

```bash
kubectl create ns demo -o yaml --dry-run=client > namespace.yml
```

## Update Context to ns demo

```bash
kubectl config set-context kind-calico-lab --namespace=demo
```

## Deployment

```bash
kubectl create deploy podinfo-app -n demo \
--replicas=3 --image=ghcr.io/stefanprodan/podinfo \
--dry-run=client -o yaml > podinfo-deployment.yml

 # updated with securityContext for PSA
 # update for configMap
```

## Service

```bash
kubectl expose deploy podinfo-app --port=9898 -n demo --dry-run=client -o yaml > podinfo-app-svc.yml
```

## Create a test-pod to test service

```bash
kubectl run test-pod -n demo --image=curlimages/curl -it --rm --restart=Never -- curl podinfo-app:9898
```

## ConfigMap

```bash
kubectl create configmap podinfo-configmap --from-literal=message="Hi This is my Project App" -n demo --dry-run=client -o yaml > podinfo-configmap.yml
```

## Ingress

```bash
kubectl create ingress podinfo-ingress -n demo --rule="/\*=podinfo-app:9898" --dry-run=client -o yaml > podinfo-ingress.yml
 # Update the manifest to add tls
```

## WITH HOSTS ADDED

> add the hostname i.e. podinfo.local in local hosts file 127.0.0.1 podinfo.local

# ON WEB

```bash
https://podinfo.local/
https://podinfo.local/metrics
https://podinfo.local/healthz
```

# USING CURL -k is required as we are using TLS for http(s)

- curl -k https://podinfo.local
- curl -k https://podinfo.local/metrics
- curl -k https://podinfo.local/healthz

## WITHOUT HOSTS ADDED, we have to explicitly provide host using -H

```bash
curl -k -H "Host: podinfo.local" https://localhost
curl -k -H "Host: podinfo.local" https://localhost/metrics
```

# Health Check, they dont requires hosts, as they are not accessing application just the status Code as such

```bash
curl -v http://localhost/healthz
curl -i http://localhost/healthz
curl -k -H "Host: podinfo.local" https://localhost/healthz
curl -o /dev/null -s -w "%{http_code}\n" http://localhost/healthz
```
