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
  ```bash
      kubectl create deploy frontend --image=nginx --replicas=2 --dry-run=client -n team-alpha -o yaml > frontend.yml
      kubectl create deploy api --image=nginx --replicas=2 --dry-run=client -n team-alpha -o yaml > api.yml
      kubectl create deploy database --image=nginx --replicas=1 --dry-run=client -n team-alpha -o yaml > database.yml
      
      kubectl apply -f .
  ```

**Your task:**
1. Create a `ClusterIP` Service for `database` — accessible only inside the cluster
    ```bash
      kubectl expose deployment database --name=db-svc --port=80 --target-port=80 --type=ClusterIP
    ```
2. Create a `NodePort` Service for `api` — accessible on a specific node port
    ```bash
      kubectl expose deployment api --name=api-svc --port=80 --target-port=80 --type=NodePort
    ```
3. Try creating a `LoadBalancer` Service for `frontend`
    ```bash
      kubectl expose deployment frontend --name=frontend-svc --port=80 --target-port=80 --type=LoadBalancer
    ```
  Observe what happens without a cloud provider and how to work around it with `minikube tunnel` or port-forwarding
  - The EXTERNAL-IP stays `<pending>` because kind has no cloud provider to provision a real LB. Internal cluster traffic is unaffected — pods can still reach `frontend-svc` by ClusterIP.
  - Workaround on kind: use port-forward to access it from your machine
    ```bash
    kubectl port-forward svc/frontend-svc 8080:80 -n team-alpha
    # then open http://localhost:8080
    ```
4. Access each service from inside the cluster using `kubectl exec` + `curl`
    ```bash
      kubectl exec -it <pod_name> -n team-alpha -- bash
        curl api-svc
        curl db-svc
        curl frontend-svc
    ```

**You should know how to answer:**
- Why should a database never be exposed as a NodePort?
  - NodePort opens a port on every node's IP, making the DB reachable from anywhere on the network — including outside the cluster. Databases hold credentials and sensitive data; they must only be reachable from specific backend pods inside the cluster (via ClusterIP). The correct flow is: `Internet → Frontend → Backend → Database (ClusterIP only)`.
- What is the port, targetPort, nodePort distinction in a Service?
  - `port` — the Service's own port; what other pods inside the cluster dial (e.g. `curl db-svc:80`)
  - `targetPort` — the port the container is actually listening on; traffic is forwarded here
  - `nodePort` — only for NodePort/LoadBalancer type; opened on every Node's IP (range 30000-32767)
  - Flow: `NodeIP:nodePort` → Service → `PodIP:targetPort`
- What does `kubectl port-forward` do and when do you use it? Is it for production?
  - It forwards a local port on your machine to a port on a pod or service inside the cluster. Traffic goes through the Kubernetes API server — not a direct network tunnel. Used for local debugging and testing only, never production. It terminates the moment you close the terminal.
  ```bash
  kubectl port-forward pod/<pod-name> 8080:80       # local:8080 → pod:80
  kubectl port-forward svc/<svc-name> 8080:80       # local:8080 → service:80
  ```

---

## Exercise 2 — DNS and Service Discovery

**Scenario:** The `api` pod needs to connect to the `database` pod by name, not IP.

**Your task:**
1. Exec into the `api` pod
2. Without knowing the database pod IP, resolve the database service using its DNS name. The format is: `<service-name>.<namespace>.svc.cluster.local`
3. Ping and curl the database service using just its short name `db-svc` — understand when short names work vs when you need the full FQDN
    ```bash
        kubectl exec -it api-7db8db7947-b45sq -- sh
  
        # Resolved
          curl db-svc.team-alpha.svc.cluster.local
          curl db-svc
          curl db-svc.team-alpha
  
        # Not Resolved
          curl db-svc.cluster.local
            curl: (6) Could not resolve host: db-svc.cluster.local
          curl db-svc.svc.cluster.local
            curl: (6) Could not resolve host: db-svc.svc.cluster.local
    ```
4. Check what DNS server the pod uses: `cat /etc/resolv.conf` — understand the `search` domain entries
    ```bash
        cat /etc/resolv.conf
        search team-alpha.svc.cluster.local svc.cluster.local cluster.local
        nameserver 10.96.0.10
        options ndots:5
    ```

**NOTE:** 
1. Why some dns above not get resolved ?
  - The DNS search list can only append search domains to the hostname you provide. 
  - It cannot insert or replace missing labels in the middle of the hostname.
  - For example - when you run `curl db-svc.cluster.local`. The resolver (because of the search entries in /etc/resolv.conf) tries names like:
    ```bash
        db-svc.cluster.local.team-alpha.svc.cluster.local
        db-svc.cluster.local.svc.cluster.local
        db-svc.cluster.local.cluster.local
    
        None of these are the correct Kubernetes Service FQDN: db-svc.team-alpha.svc.cluster.local
        The same reasoning applies to: curl db-svc.svc.cluster.local
    ```

**Deeper exercise:**
- Deploy a second namespace `team-beta` with an `api` deployment
  ```bash
      kubectl create deploy api --image=nginx --replicas=2 --dry-run=client -n team-beta -o yaml > api_team-beta.yml
      kubectl apply -f api_team-beta.yml
      kubectl get pods -n team-beta
  ```
- From `team-beta`'s api pod, resolve `api-svc.team-alpha.svc.cluster.local`
  ```bash
      kubectl exec -it api-7db8db7947-5p864 -n team-beta -- sh
      curl api-svc.team-alpha.svc.cluster.local
  ```
- Explain: why does cross-namespace resolution require the full FQDN?
  - The `search` domains in `/etc/resolv.conf` only contain the pod's **own** namespace (e.g. `team-beta.svc.cluster.local`). When you type `curl api-svc`, the resolver expands it to `api-svc.team-beta.svc.cluster.local` — which resolves to the service in `team-beta`, not `team-alpha`. To reach a service in another namespace you must provide the full FQDN `api-svc.team-alpha.svc.cluster.local` so there is no ambiguity.

**You should know how to answer:**
- What is CoreDNS and where does it run in the cluster?
  - CoreDNS is the DNS server for the cluster. It runs as a Deployment in the `kube-system` namespace. Every pod's `/etc/resolv.conf` points to it (`nameserver 10.96.0.10`). It resolves `<svc>.<namespace>.svc.cluster.local` to the Service's ClusterIP.
  ```bash
  kubectl get pods -n kube-system -l k8s-app=kube-dns
  ```
- What happens if CoreDNS is down? How would you debug it?
  - All service-name-based DNS resolution breaks — pods can only communicate by raw IP, not by name. `curl db-svc` fails but `curl <ClusterIP>` still works.
  - Debug steps:
  ```bash
  kubectl get pods -n kube-system -l k8s-app=kube-dns   # are CoreDNS pods Running?
  kubectl logs -n kube-system -l k8s-app=kube-dns        # check for errors
  kubectl describe pod <coredns-pod> -n kube-system       # check events
  ```

---

## Exercise 3 — Ingress (Company's Traffic Front Door)

**Scenario:** Your company runs two apps: `frontend` and `api`. Both should be accessible externally but through a single IP — routed by path.

**Your task:**
1. Install the NGINX Ingress Controller:
   ```bash
   kubectl delete -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.9.4/deploy/static/provider/baremetal/deploy.yaml
   # For kind clusters — uses hostPort so the controller binds directly to ports 80/443
   # on the node, matching the extraPortMappings in kind-calico.yaml.
   # The baremetal manifest uses random NodePorts that extraPortMappings can't reach — don't use it for kind.
   kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
   ```
2. Create an Ingress resource that routes:
   - `http://<cluster-ip>/` → `frontend` service on port 80
   - `http://<cluster-ip>/api` → `api` service on port 80
3. Test routing using `curl` with appropriate headers
4. Add host-based routing: route `frontend.local` to frontend, `api.local` to api (edit `/etc/hosts` on your machine to simulate DNS)
5. Check Ingress controller logs when a request comes in
    ```bash
      # 2. and 4. Create Ingress with all 4 rules
       kubectl create ingress app-ingress --class=nginx \
        --rule="/=frontend-svc:80" \ 
        --rule="/api=api-svc:80" \ 
        --rule="frontend.local/=frontend-svc:80" \
        --rule="api.local/=api-svc:80" \
        --dry-run=client -o yaml > ingress.yml
      
      # 3. Test Routing
      curl localhost
      curl localhost/api # gives error somehow

> **NOTE — Why `curl localhost/api` returns 404 (and how to fix it):**
> Without a `rewrite-target` annotation, the Ingress forwards the request **with the original path intact** — the pod receives `GET /api`, not `GET /`. nginx only serves content at `/`, so it returns 404.
> This is NOT a routing failure (the Ingress correctly reached `api-svc`) — the 404 comes from **inside the pod**.
>
> **Fix — always required when your Ingress path prefix differs from what the backend serves:**
> ```yaml
> annotations:
>   nginx.ingress.kubernetes.io/rewrite-target: /$2
> # path: /api(/|$)(.*)        ← regex captures everything after /api as group $2
> # pathType: ImplementationSpecific
> ```
> `/api/` → Ingress strips `/api` → pod receives `/` <- which is correct for nginx in this case.
  
      # Without editing /etc/hosts
      curl -H "Host: frontend.local" localhost
      curl -H "Host: api.local" localhost

      # 5. Check Logs
      kubectl get pods -n ingress-nginx
      kubectl logs ingress-nginx-controller-56dc4b4c6-kn475 -n ingress-nginx
    ```


**Dig deeper:**
- Add a `rewrite-target` annotation so `/api/users` strips `/api` before hitting the backend
  - Add these annotations to the Ingress and change the path to capture the suffix:
  ```yaml
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /$2
  # path: /api(/|$)(.*)
  # pathType: ImplementationSpecific
  ```
  - This captures everything after `/api` as group `$2` and rewrites the request to `/$2`. So `/api/users` hits the backend as `/users`.
- What happens when two Ingress resources have conflicting rules?
  - The NGINX Ingress controller uses **first-match wins** — the rule from the earlier-created (older) Ingress resource takes precedence. This causes silent routing bugs where one app's traffic gets silently sent to another app. Always use unique paths/hosts across Ingress resources.

**You should know how to answer:**
- What is an IngressClass and why was it introduced?
  - Before K8s 1.18, clusters used an annotation (`kubernetes.io/ingress.class: nginx`) to pick a controller — this was fragile and unofficial. IngressClass is the proper resource that links an Ingress to a specific controller. It was introduced so **multiple ingress controllers** (e.g. nginx + traefik) can coexist in one cluster, and each Ingress resource declares which one should handle it via `spec.ingressClassName`.
- How is Ingress different from a LoadBalancer Service?
  - A **LoadBalancer Service** gives **one external IP per service** — 10 services = 10 LBs = 10 IPs (expensive in cloud). It operates at L4 (TCP/UDP) with no awareness of HTTP paths or hostnames.
  - **Ingress** uses a **single external IP** (the ingress controller's LB) and routes to many services using L7 HTTP rules (path, hostname). It's cheaper and more flexible.
  - Real flow: `Internet → cloud LB (1 IP) → Ingress Controller pod → Ingress rules → ClusterIP Service → Pods`
- At a company, who manages the Ingress controller — the platform team or app teams?
  - The **platform/infra team** owns the Ingress controller — they install it, upgrade it, and ensure it is highly available. It is shared cluster infrastructure, not app-specific code.
  - App teams only create **Ingress resources** (rules) for their own services. They do not touch the controller itself.
  - This separation also prevents one team from accidentally misconfiguring routing for another team's traffic.

---

## Exercise 4 — NetworkPolicies (Zero-Trust Networking)

**Scenario:** Security audit found that any pod can talk to any other pod in the cluster. You need to lock it down so `team-beta` cannot reach `team-alpha`'s database.

**Note:** Calico must be installed (from the setup step) for NetworkPolicies to be enforced.

**Your task:**
1. Without any NetworkPolicy, verify that a pod in `team-beta` CAN reach `team-alpha`'s database service
    ```bash
      kubectl exec -it api-7db8db7947-5p864 -n team-beta -- sh
      curl db-svc.team-alpha #Reachable
    ```
2. Apply a NetworkPolicy to `team-alpha` that:
    - Denies all ingress to pods with label `app=database`
    - Except allows ingress from pods in `team-alpha` with label `app=api`
    ```bash
        kubectl apply -f networkpolicy_team-alpha.yml
    ```  
3. Verify that `team-beta` can no longer reach the database
    ```bash
      kubectl exec -it <pod_name> -n team-beta -- sh
        curl db-svc.team-alpha  # times out — Unreachable
    ```
4. Verify that `team-alpha`'s api can still reach the database
    ```bash
      kubectl exec -it <api_pod> -n team-alpha -- sh
        curl db-svc             # ✅ Reachable from api
      kubectl exec -it <frontend_pod> -n team-alpha -- sh
        curl db-svc             # ❌ Unreachable from frontend (policy only allows app=api)
    ```
5. Apply a default-deny-all NetworkPolicy for namespace `team-beta` (blocks all ingress AND egress)
    ```bash
      kubectl apply -f networkpolicy_team-beta_deny-all.yml
    ``` 
6. Add a specific egress rule that allows `team-beta` pods to reach CoreDNS pods (port 53)
  - CoreDNS usually runs in the kube-system namespace
  - DNS uses UDP port 53 primarily (TCP 53 is also used for larger responses), so you should allow both.
  - observe what happens when you don't allow this egress rule.
    - **Observation:** 
    ```bash
        # Get the labels for namespace and pods
        kubectl get ns --show-labels | grep kube-system
        kubectl get pods -n kube-system --show-labels | grep coredns
        
        # Add the code to networkpolicy_team-beta-deny-all.yml
        egress:
        - to:
          - namespaceSelector:
              matchLabels:
                 kubernetes.io/metadata.name: kube-system
            podSelector:
              matchLabels:
                 k8s-app: kube-dns
          ports:
          - protocol: UDP
            port: 53
          - protocol: TCP
            port: 53
    ```

**You should know how to answer:**
- Are NetworkPolicies firewall rules at the VM level or the K8s level?
  - They are at the **K8s level**, enforced by the CNI plugin (e.g. Calico) using eBPF/iptables on the node. They are NOT VM-level firewall rules — they only apply to pod-to-pod traffic, not to traffic to/from the node OS itself. Without a CNI that supports them (like Calico), applying a NetworkPolicy silently does nothing.

- What happens to existing connections when you apply a NetworkPolicy?
  - New connections are immediately evaluated against the policy. Existing TCP connections may be dropped — Calico typically drops them as soon as the policy is applied. There is no graceful draining of existing connections.
  
- Why must you always allow port 53 egress before applying a default-deny egress policy?
  - Port 53 is DNS. The moment you block all egress, the pod can no longer resolve any service names — `curl db-svc` breaks even if `db-svc` is listed as an allowed destination, because the pod can't translate that name to an IP. DNS resolution must succeed before any other connection can be established. So allow port 53 (UDP + TCP) to CoreDNS first, then layer the rest of your rules.

---

## Exercise 5 — Debugging Network Issues (The Real Skill)

**Scenario:** A developer says "my pod can't connect to the database." You need to diagnose it.

**Your task — simulate and solve each of these:**

**Problem 1:** Service selector mismatch
- Create a Service with selector `app=databasee` (typo) — pod has label `app=database`
- Debug: how do you find the mismatch?
  ```bash
      # Key command — if ENDPOINTSLICE shows <none>, the selector matches no pod
      # As It shows the Pod IPs, the service is connecting to.
      kubectl get endpointslice db-svc -n team-alpha

      # Cross-check: what does the service selector say vs what labels do pods actually have?
      kubectl describe svc db-svc -n team-alpha       # shows Selector: app=databasee
      kubectl get pods -n team-alpha --show-labels    # shows actual label: app=database
      # Spot the typo → fix the selector in the Service manifest
  ```
**Problem 2:** Wrong port
- Service targets `port: 5432` but pod listens on `port: 80`
- Debug: find which port the container actually exposes
  ```bash
      # Check what targetPort the Service is using
      kubectl describe svc db-svc -n team-alpha       # shows TargetPort: 5432

      # Check what port the pod actually listens on
      kubectl describe pod <pod_name> -n team-alpha   # shows Ports: 80/TCP

      # Or exec in and check active listeners
      kubectl exec -it <pod_name> -- sh
        ss -tlnp      # shows the actual listening port

      # Fix: update targetPort in the Service to match the container's port (80)
  ```
**Problem 3:** Pod not in Running state
- The pod backing the service is in `CrashLoopBackOff`
- Service exists, DNS resolves, but curl fails — why?
  ```text
  The pod keeps crashing and restarting. Even though the Service and DNS exist, there is no
  running process inside the pod to accept the connection. curl hangs or gets connection refused.
  ```
  ```bash
      # Diagnose
      kubectl get pods -n team-alpha                    # shows CrashLoopBackOff + high RESTARTS count
      kubectl logs <pod_name> -n team-alpha             # check why it's crashing
      kubectl logs <pod_name> -n team-alpha --previous  # logs from the last crashed container
      kubectl describe pod <pod_name> -n team-alpha     # check Events and Last State exit code
  ```
**For each problem:** write down the exact kubectl commands you used to diagnose it. This is your debugging playbook.

**You should know how to answer:**
- What does `kubectl get endpointslice` tell you that `kubectl get service` does not?
  - `kubectl get service` only shows the ClusterIP (the virtual/stable IP of the service itself).
  - `kubectl get endpointslice` shows the **actual pod IPs** backing the service.
    - If the list is empty, the service selector matches no running pod — this is the first place to check when a service is unreachable.
- Walk me through how you would debug "I can't reach my service from another pod."
  1. Does the Service exist? → `kubectl get svc -n <namespace>`
  2. Does it have pod IPs backing it? → `kubectl get endpoints <svc-name> -n <namespace>` ← **most important check; `<none>` = selector mismatch**
  3. Do pod labels match the Service selector? → `kubectl describe svc <svc-name>` vs `kubectl get pods --show-labels`
  4. Is the pod actually Running and Ready? → `kubectl get pods -n <namespace>`
  5. Is a NetworkPolicy blocking traffic? → `kubectl get networkpolicy -n <namespace>` then `kubectl describe`
  6. Test directly from inside the source pod → `kubectl exec -it <pod> -- curl <svc-name>.<namespace>`

---

## Exercise 6 — cert-manager: Automatic TLS (The Real Company Way)

**Scenario:** In Exercise 3, you generated a TLS certificate manually with `openssl`. No company does this in practice. Manually managed certs get expire, lost, and cause 3am outages. cert-manager automates the full certificate lifecycle — issuing, renewing, and rotating certs automatically.

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

  ```bash
    kubectl get clusterissuer
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

  ```bash
    kubectl get certificate
  ```

4. Observe cert-manager create the `alpha-tls-secret` automatically in `team-alpha`. It contains
  - tls.crt
  - tls.key
  - ca.crt
  ```bash
    kubectl get secret
  ```
5. Reference this secret in your Ingress `tls:` section — verify HTTPS works
  ```bash
      tls:
      - hosts:
        secretName: alpha-tls-secret
  ```  
6. Delete the Secret manually and watch cert-manager re-issue the certificate automatically — this is the whole point
  ```bash
    kubectl delete secret alpha-tls-secret
    kubectl get secret
  ```

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
  - Use cert-manager with a Let's Encrypt `ClusterIssuer`. Add the annotation `cert-manager.io/cluster-issuer: "letsencrypt-prod"` to each Ingress resource. cert-manager auto-issues the cert, stores it as a TLS Secret, and renews it automatically 30 days before expiry. Zero manual work after initial setup. For even less overhead, use a wildcard cert (`*.company.com`) — one Certificate covers all subdomains.
- "What is cert-manager and how does it interact with Let's Encrypt?"
  - cert-manager is a Kubernetes controller that automates TLS certificate lifecycle — issuing, storing, and renewing certs. It is NOT a CA itself. It watches `Certificate` and `ClusterIssuer` resources. When configured with a Let's Encrypt `ClusterIssuer`, it speaks to LE's ACME API to get certs signed, then stores the result as a Kubernetes TLS Secret. It also monitors expiry and renews automatically.
- "What is the ACME protocol and what is an HTTP-01 challenge?"
  - **ACME** (Automatic Certificate Management Environment) is the protocol cert-manager uses to communicate with Let's Encrypt's API — it is the language of the conversation, not the CA itself.
  - **HTTP-01 challenge** is how Let's Encrypt verifies you actually own the domain before signing a cert:
    1. LE tells cert-manager: "Put this token at `http://yourdomain/.well-known/acme-challenge/<token>`"
    2. cert-manager creates a temporary Ingress rule + pod that serves that token at that URL
    3. LE makes an HTTP GET from the public internet to that URL
    4. If the token matches → domain ownership proved → LE signs the cert → cert-manager stores it as TLS Secret
    5. cert-manager cleans up the temporary rule
  - **Limitation:** LE must reach your domain from the public internet. Does NOT work for `.local` domains or private internal services.
- "What happens when a cert-manager certificate is about to expire?"
  - cert-manager continuously monitors expiry of all `Certificate` resources it manages. 30 days before expiry, it automatically initiates renewal — re-runs the issuance flow (ACME challenge for LE, or local generation for self-signed), gets a new signed cert, and updates the TLS Secret in place. The Ingress Controller picks up the new Secret automatically. Zero downtime, zero manual intervention.

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

- [x] Explain all service types and choose the right one for a scenario
- [x] Resolve services by DNS name from inside a pod
- [x] Set up Ingress with path and host-based routing
- [x] Write NetworkPolicies that allow specific cross-pod traffic
- [x] Debug service connectivity issues using endpoints, logs, and exec
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
  ```bash
      kubectl create deploy frontend --image=nginx:alpine --replicas=2 -n team-alpha --dry-run=client -o yaml > frontend.yml
      kubectl create deploy api --image=hashicorp/http-echo --replicas=2 -n team-alpha --dry-run=client -o yaml > api.yml
      kubectl create deploy database --image=hashicorp/http-echo --replicas=1 -n team-alpha --dry-run=client -o yaml > database.yml
      # add text in manifest file
      
  ```
2. `services.yaml` — ClusterIP services for all 3
  ```bash
      kubectl expose deploy frontend --port=80 --target-port=80 -n team-alpha
      kubectl expose deploy api --port=80 --target-port=5678 -n team-alpha
      kubectl expose deploy database --port=80 --target-port=5678 -n team-alpha
  ```
3. `ingress.yaml` — Single Ingress resource:
   - `/` → frontend
   - `/api` → api service
   - Database has NO ingress rule (internal only)
   - TLS enabled using a cert-manager self-signed Certificate (Exercise 6)
  ```bash
    kubectl create ingress app-ingress --class=nginx --rules="/=frontend-svc:80" --rules="/api=api-svc:80" --dry-run=client -o yaml > ingress.yml
  ```
4. `network-policies.yaml` — Policies that enforce:
   - `frontend` can reach `api`
   - `api` can reach `database`
   - `frontend` CANNOT reach `database`
   - Default deny all for the namespace
   - DNS (port 53) egress allowed so pods can resolve names
  ```bash
      kubectl apply -f network-policies.yml
  ```  
5. `tls.yaml` — A self-signed `ClusterIssuer` + `Certificate` resource for the Ingress hostname (Exercise 6):
   - Use cert-manager's `selfsigned` issuer (no external ACME needed for local cluster)
   - Certificate should target the same hostname used in `ingress.yaml`

**Proof of completion:**
- `curl localhost/` → frontend response
- `curl localhost/api` → API response
- From inside `frontend` pod: `curl database` → connection refused/timeout
- From inside `api` pod: `curl database` → DB response
- `kubectl get networkpolicies -n team-alpha` shows your policies
- `kubectl get certificate -n team-alpha` shows `READY=True` for your self-signed cert

---

**Next: Task-04-Storage.md**
