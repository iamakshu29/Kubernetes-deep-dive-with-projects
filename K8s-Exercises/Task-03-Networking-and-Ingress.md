# Task 03 — Networking, Services & Ingress

> Real-world relevance: Networking is where most K8s problems surface.
> "Why can't my pod reach the database?", "Why is traffic not reaching my app?" —
> you will be the person who debugs and fixes these. This task builds that muscle.

> **Cluster needed:** 2-node kind cluster with **Calico CNI** (required for NetworkPolicies to actually be enforced).
> - **Critical:** Default kind CNI (kindnet) does NOT enforce NetworkPolicies. Applying a NetworkPolicy without Calico silently does nothing.
> - **Use:** kind + Calico — full setup in **00-Setup.md Option A2** (includes kind config with CNI disabled + Calico install).
> - **Easiest alternative for NetworkPolicy exercises:** Killercoda — it ships with Calico by default.
> - **Ingress exercises:** Use the same kind cluster — the `extraPortMappings` for port 80/443 are already in the Option A2 config.

---

## What You Will Learn

- How K8s networking actually works (pod-to-pod, pod-to-service, external traffic)
- Service types and when to use each
- Ingress — exposing multiple apps under one IP with path/host routing
- NetworkPolicies — locking down traffic between namespaces and pods
- CoreDNS — how name resolution works inside a cluster
- Debugging network issues like a senior engineer

---

## Background — Read Before Starting

Every pod gets an IP. But pod IPs are temporary — they change when pods restart. That is why Services exist. A Service gets a stable virtual IP (ClusterIP) and load-balances to all matching pods via label selectors.

Traffic flow at a company looks like this:
```
Internet
  → LoadBalancer / Ingress Controller
    → Ingress rules match host/path
      → Service (ClusterIP)
        → Pod (one of N replicas)
```

You will build and debug every layer of this chain.

---

## Exercise 1 — Service Types Deep Dive

**Scenario:** You have three apps deployed. Each needs to be exposed differently.

**Setup first:**
Deploy three simple apps (all using `nginx` image) in namespace `team-alpha`:
- `frontend` — 2 replicas, label `app=frontend`
- `api` — 2 replicas, label `app=api`
- `database` — 1 replica, label `app=database`

**Your task:**
1. Create a `ClusterIP` Service for `database` — accessible only inside the cluster
2. Create a `NodePort` Service for `api` — accessible on a specific node port
3. Try creating a `LoadBalancer` Service for `frontend` — observe what happens without a cloud provider and how to work around it with `minikube tunnel` or port-forwarding
4. Access each service from inside the cluster using `kubectl exec` + `curl`

**You should know how to answer:**
- Why should a database never be exposed as a NodePort?
- What is the port, targetPort, nodePort distinction in a Service?
- What does `kubectl port-forward` do and when do you use it? Is it for production?

---

## Exercise 2 — DNS and Service Discovery

**Scenario:** The `api` pod needs to connect to the `database` pod by name, not IP.

**Your task:**
1. Exec into the `api` pod
2. Without knowing the database pod IP, resolve the database service using its DNS name. The format is: `<service-name>.<namespace>.svc.cluster.local`
3. Ping and curl the database service using just its short name `database` — understand when short names work vs when you need the full FQDN
4. Check what DNS server the pod uses: `cat /etc/resolv.conf` — understand the `search` domain entries

**Deeper exercise:**
- Deploy a second namespace `team-beta` with an `api` service
- From `team-alpha`'s api pod, resolve `api.team-beta.svc.cluster.local`
- Explain: why does cross-namespace resolution require the full FQDN?

**You should know how to answer:**
- What is CoreDNS and where does it run in the cluster?
- What happens if CoreDNS is down? How would you debug it?

---

## Exercise 3 — Ingress (Company's Traffic Front Door)

**Scenario:** Your company runs two apps: `frontend` and `api`. Both should be accessible externally but through a single IP — routed by path.

**Your task:**
1. Install the NGINX Ingress Controller:
   ```
   kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.9.4/deploy/static/provider/baremetal/deploy.yaml
   ```
2. Create an Ingress resource that routes:
   - `http://<cluster-ip>/` → `frontend` service on port 80
   - `http://<cluster-ip>/api` → `api` service on port 80
3. Test routing using `curl` with appropriate headers
4. Add host-based routing: route `frontend.local` to frontend, `api.local` to api (edit `/etc/hosts` on your machine to simulate DNS)
5. Check Ingress controller logs when a request comes in

**Dig deeper:**
- Add a `rewrite-target` annotation so `/api/users` strips `/api` before hitting the backend
- What happens when two Ingress resources have conflicting rules?

**You should know how to answer:**
- What is an IngressClass and why was it introduced?
- How is Ingress different from a LoadBalancer Service?
- At a company, who manages the Ingress controller — the platform team or app teams?

---

## Exercise 4 — NetworkPolicies (Zero-Trust Networking)

**Scenario:** Security audit found that any pod can talk to any other pod in the cluster. You need to lock it down so `team-beta` cannot reach `team-alpha`'s database.

**Note:** Calico must be installed (from the setup step) for NetworkPolicies to be enforced.

**Your task:**
1. Without any NetworkPolicy, verify that a pod in `team-beta` CAN reach `team-alpha`'s database service
2. Apply a NetworkPolicy to `team-alpha` that:
   - Denies all ingress to pods with label `app=database`
   - Except allows ingress from pods in `team-alpha` with label `app=api`
3. Verify that `team-beta` can no longer reach the database
4. Verify that `team-alpha`'s api can still reach the database
5. Apply a default-deny-all NetworkPolicy for namespace `team-beta` (blocks all ingress AND egress)
6. Add a specific egress rule that allows `team-beta` pods to reach CoreDNS (port 53) — observe what happens when you don't have this

**You should know how to answer:**
- Are NetworkPolicies firewall rules at the VM level or the K8s level?
- What happens to existing connections when you apply a NetworkPolicy?
- Why must you always allow port 53 egress before applying a default-deny egress policy?

---

## Exercise 5 — Debugging Network Issues (The Real Skill)

**Scenario:** A developer says "my pod can't connect to the database." You need to diagnose it.

**Your task — simulate and solve each of these:**

**Problem 1:** Service selector mismatch
- Create a Service with selector `app=databasee` (typo) — pod has label `app=database`
- Debug: how do you find the mismatch?

**Problem 2:** Wrong port
- Service targets `port: 5432` but pod listens on `port: 80`
- Debug: find which port the container actually exposes

**Problem 3:** Pod not in Running state
- The pod backing the service is in `CrashLoopBackOff`
- Service exists, DNS resolves, but curl fails — why?

**For each problem:** write down the exact kubectl commands you used to diagnose it. This is your debugging playbook.

**You should know how to answer:**
- What does `kubectl get endpoints` tell you that `kubectl get service` does not?
- Walk me through how you would debug "I can't reach my service from another pod."

---

## Exercise 6 — cert-manager: Automatic TLS (The Real Company Way)

**Scenario:** In Exercise 3, you generated a TLS certificate manually with `openssl`. No company does this in practice. Manually managed certs expire, get lost, and cause 3am outages. cert-manager automates the full certificate lifecycle — issuing, renewing, and rotating certs automatically.

**Your task:**

1. Install cert-manager:
   ```bash
   kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.4/cert-manager.yaml
   # Wait for all pods to be Running
   kubectl get pods -n cert-manager
   ```

2. Create a self-signed `ClusterIssuer` (for local practice — in production you'd use Let's Encrypt or an internal CA):
   ```yaml
   apiVersion: cert-manager.io/v1
   kind: ClusterIssuer
   metadata:
     name: selfsigned-issuer
   spec:
     selfSigned: {}
   ```

3. Create a `Certificate` resource for your Ingress domain:
   ```yaml
   apiVersion: cert-manager.io/v1
   kind: Certificate
   metadata:
     name: alpha-tls
     namespace: team-alpha
   spec:
     secretName: alpha-tls-secret
     issuerRef:
       name: selfsigned-issuer
       kind: ClusterIssuer
     dnsNames:
     - frontend.local
     - api.local
   ```

4. Observe cert-manager create the `alpha-tls-secret` automatically in `team-alpha`
5. Reference this secret in your Ingress `tls:` section — verify HTTPS works
6. Delete the Secret manually and watch cert-manager re-issue the certificate automatically — this is the whole point

**Production path — Let's Encrypt (understand this, don't run it locally):**
```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@company.com
    privateKeySecretRef:
      name: letsencrypt-prod-key
    solvers:
    - http01:
        ingress:
          class: nginx
```
With this in place, adding `cert-manager.io/cluster-issuer: "letsencrypt-prod"` annotation to any Ingress resource automatically provisions a real TLS certificate. Understand what the HTTP-01 challenge is and how cert-manager proves domain ownership.

**You should know how to answer:**
- "How do you manage TLS certificates for 50 services without manually renewing each one?"
- "What is cert-manager and how does it interact with Let's Encrypt?"
- "What is the ACME protocol and what is an HTTP-01 challenge?"
- "What happens when a cert-manager certificate is about to expire?"

---

## Exercise 7 — LoadBalancer, MetalLB, ExternalName, and External Traffic Policy

### Part A — How LoadBalancer Services Actually Work

**Scenario:** Every company that runs K8s on cloud (AWS/GCP/Azure) uses LoadBalancer services or Ingress Controllers backed by a cloud load balancer. You need to understand what happens under the hood — not just "it gets an IP."

**How it works:**
```
LoadBalancer Service created
  → K8s calls the cloud provider's API (via cloud-controller-manager)
    → Cloud provisions an NLB/ALB/external LB
      → LB gets a public IP
        → K8s writes that IP to service.status.loadBalancer.ingress[0].ip
          → Traffic: Internet → LB → NodePort on each K8s node → kube-proxy → Pod
```

On local clusters (kind, kubeadm on bare metal), there is no cloud provider API to call. The service stays in `<pending>` state for the external IP forever. That is why you need **MetalLB**.

**Install MetalLB for local clusters:**
```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml
kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app=metallb \
  --timeout=90s
```

Configure MetalLB with an IP pool (for kind, use a range within the Docker network):
```bash
# Find your kind network range
docker network inspect kind | grep Subnet
# Typically 172.18.0.0/16 — pick a range within it that won't conflict
```

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: local-pool
  namespace: metallb-system
spec:
  addresses:
  - 172.18.200.0-172.18.200.20   # adjust to match your kind network
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: l2-advert
  namespace: metallb-system
```

**Your task:**
1. Apply the MetalLB config above
2. Create a LoadBalancer service for `frontend`:
   ```yaml
   apiVersion: v1
   kind: Service
   metadata:
     name: frontend-lb
     namespace: team-alpha
   spec:
     type: LoadBalancer
     selector:
       app: frontend
     ports:
     - port: 80
       targetPort: 80
   ```
3. Check: `kubectl get svc frontend-lb -n team-alpha` — it should now show an EXTERNAL-IP (from the MetalLB pool) instead of `<pending>`
4. Curl that IP from your host machine — the service is now externally accessible
5. Understand the difference:
   - **For cloud (AWS/GCP/Azure):** use LoadBalancer service OR Ingress backed by cloud LB. LB service = one LB per service (expensive). Ingress = one LB for all services (standard choice).
   - **For bare metal / on-prem:** use MetalLB + Ingress. No cloud LB available.

---

### Part B — ExternalName Service (Connecting K8s to External Resources)

**Scenario:** `team-alpha`'s API connects to a managed PostgreSQL database that lives OUTSIDE the cluster (e.g., AWS RDS). You want pods to reference it by a K8s service name (`postgres.team-alpha.svc.cluster.local`) rather than hardcoding the external hostname. This decouples your app from external endpoints — you can change the external DB without modifying pod configs.

**How it works:**
An ExternalName service is a DNS alias. `kube-dns` resolves the service name to a CNAME pointing at the external hostname. No proxying, no kube-proxy rules — just DNS.

**Your task:**
1. Create an ExternalName service that points to an external host:
   ```yaml
   apiVersion: v1
   kind: Service
   metadata:
     name: external-db
     namespace: team-alpha
   spec:
     type: ExternalName
     externalName: mydb.example.com   # in real world: mydb.us-east-1.rds.amazonaws.com
   ```
2. From inside a pod in `team-alpha`, resolve `external-db.team-alpha.svc.cluster.local`:
   ```bash
   kubectl exec -it <any-pod> -n team-alpha -- nslookup external-db.team-alpha.svc.cluster.local
   # Should return a CNAME → mydb.example.com
   ```
3. Understand: ExternalName has **no ClusterIP, no selector, no endpoints**. It is purely DNS.
4. Use case: change the external DB from staging to prod without touching the application Deployment — just update the ExternalName service.

**You should know how to answer:**
- "How do you avoid hardcoding an external database hostname in your pod environment variables?"
- "What are the four K8s Service types and when do you use each?"

---

### Part C — externalTrafficPolicy (Client IP Preservation)

**Scenario:** Your frontend logs client IPs for fraud detection. But after going through a NodePort or LoadBalancer service with the default policy, all requests appear to come from a node IP — not the real client IP. The `externalTrafficPolicy` field controls this.

**The two modes:**

| Policy | Behaviour | Use when |
|---|---|---|
| `Cluster` (default) | Traffic is load-balanced across ALL pods on ALL nodes. Source IP is SNAT'd to the node IP. Fast, balanced. | You don't need client IP |
| `Local` | Traffic is only sent to pods on the SAME node the traffic arrived on. Real client IP is preserved. But if a node has no pods, traffic to that node drops. | You need real client IP (logging, rate limiting, geo-routing) |

**Your task:**
1. Create a NodePort service with `externalTrafficPolicy: Local`:
   ```yaml
   apiVersion: v1
   kind: Service
   metadata:
     name: frontend-local
     namespace: team-alpha
   spec:
     type: NodePort
     externalTrafficPolicy: Local
     selector:
       app: frontend
     ports:
     - port: 80
       targetPort: 80
       nodePort: 30080
   ```
2. Hit the service and check the logs of the frontend pod — observe the real client IP in the request log
3. Switch to `externalTrafficPolicy: Cluster` and compare — the logged IP changes to the node's IP
4. Understand the trade-off: `Local` can cause uneven load distribution if pods are not evenly spread across nodes

**You should know how to answer:**
- "Our rate limiter is blocking all users because it thinks they're all coming from the same IP. What is causing this in K8s and how do you fix it?"
- "What is `externalTrafficPolicy: Local` and what is the risk of using it?"

---

### Part D — Gateway API (The Future of Ingress — Awareness)

**Background:** Ingress has been the standard for exposing HTTP services in K8s since 2015. But it has severe limitations:
- Only handles HTTP/HTTPS. TCP/UDP require custom annotations.
- Annotations are controller-specific (`nginx.ingress.kubernetes.io/...`, `alb.ingress.kubernetes.io/...`) — not portable.
- No traffic splitting, no header-based routing, no canary deployments in the spec.

**Gateway API** was introduced in K8s 1.24+ (stable in 1.28) to replace Ingress with a richer, more expressive model. It is where the ecosystem is heading.

```
Old model (Ingress):
  Ingress (single resource handles routing, TLS, and load balancing)

New model (Gateway API):
  GatewayClass  → defines the type of gateway (nginx, envoy, istio, etc.)
  Gateway       → the actual load balancer / ingress point (owned by platform team)
  HTTPRoute     → routing rules (owned by app teams) — maps hostnames/paths to services
  TCPRoute      → for TCP traffic
  GRPCRoute     → for gRPC traffic
```

**This separation is powerful:** the platform team manages the `Gateway` (the load balancer). App teams manage their own `HTTPRoute` resources without needing access to the full Ingress object. No more annotation wars.

**Your task (awareness level — no need to fully implement locally):**
1. Read the Gateway API documentation overview: https://gateway-api.sigs.k8s.io/
2. Install the CRDs to see the resources:
   ```bash
   kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml
   kubectl get crd | grep gateway
   ```
3. Write (but do not apply) an equivalent HTTPRoute for your Exercise 3 Ingress:
   ```yaml
   apiVersion: gateway.networking.k8s.io/v1
   kind: HTTPRoute
   metadata:
     name: alpha-routes
     namespace: team-alpha
   spec:
     parentRefs:
     - name: main-gateway
       namespace: infra
     hostnames:
     - "frontend.local"
     rules:
     - matches:
       - path:
           type: PathPrefix
           value: /api
       backendRefs:
       - name: api
         port: 80
     - matches:
       - path:
           type: PathPrefix
           value: /
       backendRefs:
       - name: frontend
         port: 80
   ```
4. Identify: what is the same as Ingress and what is different?

**You should know how to answer:**
- "What is Gateway API and how is it different from Ingress?"
- "Why is Gateway API better for multi-team clusters than Ingress?"
- "If someone asked you to set up traffic splitting (90% to v1, 10% to v2) — can Ingress do it? Can Gateway API?"

---

## Completion Checklist

- [ ] Explain all service types and choose the right one for a scenario
- [ ] Resolve services by DNS name from inside a pod
- [ ] Set up Ingress with path and host-based routing
- [ ] Write NetworkPolicies that allow specific cross-pod traffic
- [ ] Debug service connectivity issues using endpoints, logs, and exec
- [ ] Install cert-manager and automate TLS certificate issuance and renewal
- [ ] Install MetalLB and configure a LoadBalancer service with a real external IP
- [ ] Create an ExternalName service to decouple apps from external hostnames
- [ ] Explain `externalTrafficPolicy: Local` vs `Cluster` and when each is appropriate
- [ ] Explain what Gateway API is and why it is replacing Ingress

---

## Interview Questions This Task Prepares You For

- "How does DNS work inside a Kubernetes cluster?"
- "Walk me through how you expose an application to the internet in K8s."
- "We had a security incident where one compromised pod could reach all databases. How do you prevent that?"
- "How would you debug a pod that can't connect to a service?"
- "What is the difference between Ingress and a LoadBalancer Service?"
- "How do you manage TLS certificates at scale in K8s?"
- "One of our Ingress TLS certs expired and users got browser errors. How do you prevent this?"
- "Our rate limiter blocks all users because they look like they're from the same IP. What is causing this in K8s?"
- "How do you connect a K8s service to an external database without hardcoding its hostname?"
- "What is MetalLB and when do you need it?"
- "What is Gateway API and how is it different from Ingress? Why would you use it?"

---

## Mini Project — Unified Ingress Gateway with Network Isolation

> Estimated time: 2–3 hours. Put this in GitHub under `k8s-practice/task-03/`.

**Scenario:** Your company runs 3 services. They all sit behind one domain. External users hit one IP. Internally, the database should be unreachable from the frontend — only the API can talk to it.

**Services to deploy:**
- `frontend` — `nginx:alpine`, responds at `/`
- `api` — `hashicorp/http-echo -text="API response"`, responds at `/api`
- `database` — `hashicorp/http-echo -text="DB response"`, reachable only by `api`

**Deliverables — all as YAML files:**

1. `deployments.yaml` — All 3 deployments in `team-alpha` namespace
2. `services.yaml` — ClusterIP services for all 3
3. `ingress.yaml` — Single Ingress resource:
   - `/` → frontend
   - `/api` → api service
   - Database has NO ingress rule (internal only)
4. `network-policies.yaml` — Policies that enforce:
   - `frontend` can reach `api`
   - `api` can reach `database`
   - `frontend` CANNOT reach `database`
   - Default deny all for the namespace
   - DNS (port 53) egress allowed so pods can resolve names

**Proof of completion:**
- `curl localhost/` → frontend response
- `curl localhost/api` → API response
- From inside `frontend` pod: `curl database` → connection refused/timeout
- From inside `api` pod: `curl database` → DB response
- `kubectl get networkpolicies -n team-alpha` shows your policies

---

**Next: Task-04-Storage.md**
