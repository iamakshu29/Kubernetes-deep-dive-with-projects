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
      curl localhost/api # will give error on path: exact, fix below

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

**Part B — Manual TLS (The hard way — so you appreciate cert-manager in Exercise 6)**

Before cert-manager existed, teams had to generate and manage TLS certs manually. Do this once to understand what cert-manager automates away:

1. Generate a self-signed certificate using openssl:
   ```bash
   # Generate private key and self-signed cert for frontend.local
   openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
     -keyout tls.key \
     -out tls.crt \
     -subj "/CN=frontend.local/O=team-alpha"
   ```
2. Create a K8s TLS Secret from those files:
   ```bash
   kubectl create secret tls frontend-tls \
     --cert=tls.crt \
     --key=tls.key \
     -n team-alpha
   
   kubectl get secret frontend-tls -n team-alpha
   ```
3. Update your Ingress to use HTTPS:
   ```yaml
   spec:
     tls:
     - hosts:
       - frontend.local
       secretName: frontend-tls
     rules:
     - host: frontend.local
       http:
         paths:
         - path: /
           pathType: Prefix
           backend:
             service:
               name: frontend-svc
               port:
                 number: 80
   ```
4. Test HTTPS (use `-k` to skip cert verification since it's self-signed):
   ```bash
   curl -k -H "Host: frontend.local" https://localhost
   ```
5. Notice the problems with this approach:
   - You manually ran openssl — error-prone, not repeatable
   - The cert expires in 365 days — someone must remember to renew it
   - If `tls.key` or `tls.crt` files are lost, you regenerate from scratch
   - In a team, who owns this? Where is it stored? How is it rotated?

This is exactly why cert-manager exists — Exercise 6 automates all of this.

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

**Scenario:** Every company that runs K8s on cloud (AWS/GCP/Azure) uses LoadBalancer services or Ingress Controllers backed by a cloud load balancer. You need to understand what happens under the hood — not just "it gets an public IP."

**How it works:**
```
Service: LoadBalancer created
  → K8s calls the cloud provider's API (via cloud-controller-manager)
    → Cloud provisions an NLB/ALB/external LB
      → LB gets a public IP
        → K8s writes that IP to service.status.loadBalancer.ingress[0].ip
          → Traffic: Internet → LB → NodePort on each K8s node → kube-proxy → Pod
```

**On Cloud (AWS/GCP/Azure)**
- The **cloud-controller-manager** is pre-installed by the cloud provider when they provision the cluster (EKS/GKE/AKS). You never install it yourself.
- It watches for `type: LoadBalancer` services and automatically calls the cloud API to provision a real LB.
- Region is auto-inherited from where your nodes run. AZ, LB type, and other config are passed via **annotations** on the Service:
  ```yaml
  apiVersion: v1
  kind: Service
  metadata:
    name: frontend-svc
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-type: nlb          # NLB vs CLB
      service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
      service.beta.kubernetes.io/aws-load-balancer-subnets: subnet-abc123,subnet-def456  # AZs
  spec:
    type: LoadBalancer
    selector:
      app: frontend
    ports:
    - port: 80
      targetPort: 80
  ```
  GKE and AKS have their own annotation keys but the same concept applies.

**On local clusters (kind, kubeadm on bare metal)**
  - There is no cloud provider API to call. The service stays in `<pending>` state for the external IP forever. That is why you need **MetalLB**.
  ```bash
  # you can run and check front-svc which is LoadBalancer service type. It will be in pending state.
  # After all config done below it will get an External IP
  kubectl get svc frontend-svc
  ```

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
  ```bash
  kubectl get ns metallb-system
  kubectl get IPAddressPool -n metallb-system
  kubectl get L2Advertisement -n metallb-system
  ```
2. Create a LoadBalancer service for `frontend`:
   ```yaml
   apiVersion: v1
   kind: Service
   metadata:
     name: frontend-svc
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
  ```bash
      # The EXTERNAL-IP is present and its within the range of IPAddressPool configured above.
      kubectl get svc frontend-svc
  ```
4. Curl that IP from your host machine — the service is now externally accessible
   > **Windows note:** PowerShell has no route to the Docker bridge subnet (`172.18.x.x`) where kind nodes and MetalLB IPs live — that network only exists inside the Docker Desktop Linux VM. 
  ```bash 
      # Use WSL2 to curl those IPs directly
      curl http://<ext-ip>

      # Validate with a curl pod inside the cluster
      kubectl run curl-test --image=curlimages/curl --restart=Never --rm -it -- curl http://<ext-ip>
      
      # Run it from inside the kind node container by exec into it.
      docker exec -it <kind-control-plane|kind-worker> curl http://<ext-ip>
  ```
**Comparison — MetalLB vs Cloud LB:**
| | MetalLB (bare-metal/kind) | Cloud LB (EKS/GKE/AKS) |
|---|---|---|
| Controller | You install from a manifest | Pre-installed by cloud provider |
| IP pool config | `IPAddressPool` + `L2Advertisement` CRDs | Annotations on the Service |
| IP assignment | Picked from your defined pool | Cloud provisions and returns it |

**Understand the difference:**
   - **For cloud (AWS/GCP/Azure):** use LoadBalancer service OR Ingress backed by cloud LB. LB service = one LB per service (expensive). Ingress = one LB for all services (standard choice).
   - **For bare metal / on-prem:** use MetalLB + Ingress. No cloud LB available.

**You should know how to answer:**
- "If we know there's no cloud LB on a bare-metal cluster, why create a `LoadBalancer` type service at all — why not just use `NodePort`?"
  - **Portability:** The same YAML manifest works unchanged on cloud (gets a real cloud LB) and on-prem (MetalLB assigns an IP). Hardcoding `NodePort` means changing manifests when moving between environments.
  - **Abstraction:** App teams write `type: LoadBalancer` and don't care what backs it. Infrastructure teams decide whether that's an AWS NLB or MetalLB — the app manifest is never touched.

- "Where does the EXTERNAL-IP come from — do you specify it in the Service YAML?"
  - **No, you never specify it.** 
  - On cloud, the cloud-controller-manager calls the cloud API, the cloud provisions a real LB and returns its IP/hostname — K8s writes it to `service.status.loadBalancer.ingress[0].ip` automatically.
    - You can check it in metallb example by `kubectl edit svc frontend-svc` at the last.
  - On bare-metal with MetalLB, the MetalLB controller picks a free IP from your `IPAddressPool` and writes it to the same field. The L2Advertisement then broadcasts ARP so other machines on the network can route to it. You only define the *pool* — assignment is automatic.

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
      kubectl run dns-test --image=busybox --restart=Never -it --rm nslookup external-db.team-alpha.svc.cluster.local
     # Should return a CNAME → mydb.example.com
   ```
3. Understand: ExternalName has **no ClusterIP, no selector, no endpoints**. It is purely DNS.
4. Use case: change the external DB from staging to prod without touching the application Deployment — just update the ExternalName service.

**You should know how to answer:**
- "How do you avoid hardcoding an external database hostname in your pod environment variables?"
  - Use a K8s **ExternalName service**.
  - The pod's env var which needs the external service endpoint to connect, points to the K8s DNS name (`external-db.team-alpha.svc.cluster.local`) — never the actual external hostname. When you switch DBs (staging → prod), you update only the ExternalName service's `externalName` field.
  - No pod restarts, no ConfigMap changes, no redeployments.

- "What are the four K8s Service types and when do you use each?"
  - **ClusterIP** — Default. Only reachable within the cluster. Use for internal pod-to-service communication (e.g., API → DB).
  - **NodePort** — Exposes the service on a static port (30000–32767) on every node's IP. Use for dev/testing or when you need external access without a cloud LB. Access via `<NodeIP>:<NodePort>`.
  - **LoadBalancer** — Provisions an external LB (cloud) or uses MetalLB (bare-metal) to give the service a public IP. In practice, you don't create one LB per service — you put a single Ingress Controller behind one LB, then use Ingress rules for path/host-based routing to fan traffic out to multiple services.
  - **ExternalName** — DNS alias for an external resource (e.g., RDS endpoint). No ClusterIP, no proxying — purely CNAME resolution via CoreDNS. Decouples pods from external hostnames.

---

### Part C — externalTrafficPolicy (Client IP Preservation)

**Scenario:** Your frontend logs client IPs for fraud detection. But after going through a NodePort or LoadBalancer service with the default policy, all requests appear to come from a node IP or LB public IP — not the real client IP. The `externalTrafficPolicy` field controls this.

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

**Key insight — why `Cluster` is the default and where `Local` actually belongs:**

`Cluster` is default because most services are **backends** — they don't need client IPs and benefit from even load distribution. With `Local`, if a node has no pods for that service, traffic hitting that node is dropped:
```
Node1 → 2 pods  ✓ (handles all traffic to Node1)
Node2 → 0 pods  ✗ (traffic DROPPED)
Node3 → 1 pod   ✓ (handles all traffic to Node3)
```
With `Cluster`, kube-proxy forwards from Node2 to pods elsewhere — no drops, even distribution.

`Local` is only set on the **one service facing the internet** — the Ingress Controller's LoadBalancer service:
```
LoadBalancer service for Ingress Controller pod (externalTrafficPolicy: Local, external IP via MetalLB/Cloud)
        ↓
  Ingress Controller pod  ← real client IP arrives here
        ↓  stamps X-Forwarded-For header
  Ingress rules → backend ClusterIP services (Cluster policy)
        ↓
  Backend reads X-Forwarded-For header if it needs the client IP
```

The uneven pod risk is eliminated if we deployed Ingress Controllers as a **DaemonSet** — one pod per node — so every node always has a pod and no traffic is ever dropped:
```
Node1 → Ingress Controller pod ✓
Node2 → Ingress Controller pod ✓
Node3 → Ingress Controller pod ✓
```

**You should know how to answer:**
- "Our rate limiter is blocking all users because it thinks they're all coming from the same IP. What is causing this in K8s and how do you fix it?"
  - The default `externalTrafficPolicy: Cluster` SNATs the client IP to the node IP before it reaches the pod — so all requests appear to come from the same node IP. Fix: set `externalTrafficPolicy: Local` on the Ingress Controller's service so the real client IP is preserved and stamped into `X-Forwarded-For`.

- "What is `externalTrafficPolicy: Local` and what is the risk of using it?"
  - `Local` sends traffic only to pods on the same node that received the request, preserving the real client IP. The risk is traffic drops if a node has no pods for that service. This is mitigated by deploying the Ingress Controller as a DaemonSet so every node always has a pod.
- "Why is `Cluster` the default if `Local` preserves real IPs — shouldn't everyone want real IPs?"
  - Most services are backends (DB, internal APIs) that don't need client IPs. `Cluster` gives even load distribution and no traffic drops. Only the edge service (Ingress Controller) needs `Local` — set it once there, and backends read the client IP from the `X-Forwarded-For` header if needed.

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
  - Gateway API is the successor to Ingress, stable since K8s 1.28. Ingress only handles HTTP/HTTPS and uses controller-specific annotations (not portable). Gateway API introduces three resources: `GatewayClass` (defines the LB type), `Gateway` (the actual entry point with listeners), and `HTTPRoute` (routing rules). It supports TCP/UDP, traffic splitting, header-based routing, and canary deployments natively in the spec — no annotations needed.
- "Why is Gateway API better for multi-team clusters than Ingress?"
  - In Ingress, all routing rules live in one resource — any team can affect any other team's routes. Gateway API separates concerns: the platform team owns the `Gateway`, app teams own their `HTTPRoute`. Each team only controls their own routes, and the Gateway enforces boundaries. This is proper separation of responsibilities.
- "If someone asked you to set up traffic splitting (90% to v1, 10% to v2) — can Ingress do it? Can Gateway API?"
  - Ingress cannot do it natively — you'd need controller-specific annotations (e.g., nginx canary annotations) that only work with that specific controller. Gateway API supports it natively in the `HTTPRoute` spec using `backendRefs` with `weight` fields — portable across any Gateway API-compliant controller.

---

## Completion Checklist

- [x] Explain all service types and choose the right one for a scenario
- [x] Resolve services by DNS name from inside a pod
- [x] Set up Ingress with path and host-based routing
- [x] Write NetworkPolicies that allow specific cross-pod traffic
- [x] Debug service connectivity issues using endpoints, logs, and exec
- [x] Install cert-manager and automate TLS certificate issuance and renewal
- [x] Install MetalLB and configure a LoadBalancer service with a real external IP
- [x] Create an ExternalName service to decouple apps from external hostnames
- [x] Explain `externalTrafficPolicy: Local` vs `Cluster` and when each is appropriate
- [x] Explain what Gateway API is and why it is replacing Ingress

---

## Interview Questions This Task Prepares You For

- "How does DNS work inside a Kubernetes cluster?"
  - CoreDNS runs as a pod in `kube-system` and acts as the cluster's internal DNS server. When a pod queries `api-svc.team-alpha.svc.cluster.local`, CoreDNS resolves it to the Service's **ClusterIP** — not directly to pod IPs. kube-proxy then handles routing from the ClusterIP to an actual pod via iptables/IPVS rules. DNS gives you the stable virtual IP; load balancing to pods happens at the network layer after that.

- "Walk me through how you expose an application to the internet in K8s."
  - For a single service: create a Deployment, then a `LoadBalancer` service — on cloud it gets a public IP automatically, on bare-metal MetalLB assigns one.
  - For multiple services (production pattern): deploy the NGINX Ingress Controller (backed by one `LoadBalancer` service for a single external IP), then create `ClusterIP` services for each app, and write Ingress rules for path or host-based routing. Traffic flows: `Internet → LB (1 IP) → Ingress Controller → Ingress rules → ClusterIP service → pod`.

- "We had a security incident where one compromised pod could reach all databases. How do you prevent that?"
  - Apply NetworkPolicies. Start with a default-deny-all ingress and eggress policy on the namespace.
  - Add an egress rule allowing DNS (port 53 UDP+TCP to CoreDNS) so service name resolution still works. 
  - Add a specific ingress rule on the database pods allowing traffic only from backend pods. 
  - Result: frontend can only reach api, api can only reach the database, and database is unreachable from everything else.

- "How would you debug a pod that can't connect to a service?"
  1. Check if the Service exists: `kubectl get svc -n <namespace>`
  2. Check if it has pod IPs behind it: `kubectl get endpointSlice <svc> -n <namespace>` — if `<none>`, the selector matches no pod (most common cause)
  3. Cross-check: `kubectl describe svc <svc>` (shows selector) vs `kubectl get pods --show-labels` (shows actual labels)
  4. Check if the pod is Running and Ready: `kubectl get pods -n <namespace>`
  5. Check for NetworkPolicies blocking the path: `kubectl get networkpolicy -n <namespace>`
  6. Test directly from the source pod: `kubectl exec -it <pod> -- curl <svc-name>.<namespace>`

- "What is the difference between Ingress and a LoadBalancer Service?"
  - A `LoadBalancer` service provisions one external IP per service — 10 services = 10 LBs = expensive, and it operates at L4 (no HTTP awareness).
  - **Ingress** is a K8s resource that defines HTTP routing rules. The **Ingress Controller** (e.g. NGINX) is the pod that reads those rules and routes traffic. One Ingress Controller sits behind a single `LoadBalancer` service and fans traffic out to many backend ClusterIP services using L7 rules (path, hostname). One IP, many services — this is the standard production pattern.

- "How do you manage TLS certificates at scale in K8s?"
  - Use **cert-manager**. Install it in the cluster.
  - create a `ClusterIssuer` (self-signed for internal, Let's Encrypt for production).
  - Then either create a `Certificate` resource directly or add the `cert-manager.io/cluster-issuer` annotation to an Ingress.
  - cert-manager issues the certificate, stores the cert as a TLS Secret, and auto-renews before expiry. Zero manual intervention.

- "One of our Ingress TLS certs expired and users got browser errors. How do you prevent this?"
  - Install cert-manager with a `ClusterIssuer` backed by Let's Encrypt (or internal CA).
  - cert-manager monitors certificate expiry and auto-renews certs before they expire — typically 30 days before.
  - No manual renewal, no 3am outages.

- "Our rate limiter blocks all users because they look like they're from the same IP. What is causing this in K8s?"
  - The default `externalTrafficPolicy: Cluster` SNATs all incoming traffic to the node's IP before it reaches the pod — so every request appears to come from the same node IP.
  - Fix: set `externalTrafficPolicy: Local` on the Ingress Controller's `LoadBalancer` service. 
    - This preserves the real client IP, which NGINX stamps into the `X-Forwarded-For` header.
  - Deploy the Ingress Controller as a DaemonSet (one pod per node) so `Local` doesn't cause traffic drops on nodes without pods.

- "How do you connect a K8s service to an external database without hardcoding its hostname?"
  - Create an **ExternalName service** in the same namespace: `spec.type: ExternalName`, `spec.externalName: mydb.us-east-1.rds.amazonaws.com`. The pod's env var is set to the K8s DNS name of that service (`external-db.team-alpha.svc.cluster.local`) — never the actual external hostname. When you switch from staging to prod DB, you update only the ExternalName service's `externalName` field. No pod restarts, no Deployment changes.

- "What is MetalLB and when do you need it?"
  - On cloud clusters (EKS/GKE/AKS), the `cloud-controller-manager` is pre-installed and automatically provisions a real load balancer when you create a `LoadBalancer` service.
  - On bare-metal or local clusters (kind, kubeadm), there is no cloud-controller-manager — so `LoadBalancer` services stay in `<pending>` forever. MetalLB fills that gap: it runs inside the cluster, assigns IPs from a pool you define, and announces them via L2 ARP so traffic reaches the right node.

- "What is Gateway API and how is it different from Ingress? Why would you use it?"
  - Ingress only handles HTTP/HTTPS, uses controller-specific annotations (not portable between nginx/traefik/alb), and has no native support for traffic splitting or canary deployments.
  - Gateway API (stable since K8s 1.28) introduces three resources: `GatewayClass` (LB type), `Gateway` (entry point with listeners), and `HTTPRoute` (routing rules). It supports TCP/UDP, traffic splitting via `backendRefs` weights, and header-based routing — all in the spec, no annotations needed.
  - In multi-team clusters it's also better: the platform team owns the `Gateway`, app teams own their `HTTPRoute` — clean separation of responsibility.

---

## Mini Project — Unified Ingress Gateway with Network Isolation

> Estimated time: 2–3 hours. Put this in GitHub under `k8s-practice/task-03/`.

**Scenario:** Your company runs 3 services. They all sit behind one domain. External users hit one IP. Internally, the database should be unreachable from the frontend — only the API can talk to it.

**Create namespace team-alpha and Label it**
  ```bash
      kubectl create ns team-alpha
      kubectl label ns team-alpha team=alpha
  ```

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
      # add args text in manifest file
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
      kubectl create ingress app-ingress --class=nginx --rule="/=frontend-svc:80" --rule="/api=api-svc:80" --dry-run=client -o yaml > ingress.yml
  
      # Configure pathType, tls, annotations in manifest later.
  ```
4. `network-policies.yaml` — Policies that enforce:
   - `frontend` can reach `api`
   - `api` can reach `database`
   - `frontend` CANNOT reach `database`
   - Default deny all for the namespace
   - DNS (port 53) egress allowed so pods can resolve names
  ```bash
      kubectl apply -f network-policies.yml
      
      # Kubernetes NetworkPolicy Design
      1. Apply a default deny policy for the namespace. 
        - Deny all Ingress. 
        - Deny all Egress. 
        - Allow only DNS (CoreDNS on port 53) as an egress exception. 
        
      2. Create application-specific policies. 
        2.1 Frontend 
          - Accept traffic only from the Ingress Controller.
          - Allow egress only to the API. 
          
          Result: 
          Internet -> Ingress Controller -> Frontend -> API
          Frontend cannot directly communicate with the Database. 
        
        2.2 API
          - Accept traffic from the Frontend (pod-to-pod calls).
          - Accept traffic from the Ingress Controller (for the /api ingress route).
          - Allow egress only to the Database. 
          
          Result:
          Internet -> Ingress Controller -> API (direct, via /api ingress rule)
          Frontend -> API -> Database 
        
        2.3 Database
          - Accept traffic only from the API.
          - No additional egress permissions (unless explicitly required).
  ```  
5. `tls.yaml` — A self-signed `ClusterIssuer` + `Certificate` resource for the Ingress hostname (Exercise 6):
   - Use cert-manager's `selfsigned` issuer (no external ACME needed for local cluster)
   - Certificate should target the same hostname used in `ingress.yaml`
  ```bash
      # apply tls.yml
      kubectl apply -f tls.tml
      # check secret
      kubectl get secret # alpha-tls-secret
      
      # Add hosts and secret-name in ingress.yml
  ```

**Proof of completion:**
- `curl localhost/` → frontend response
- `curl localhost/api` → API response
- From inside `frontend` pod: `curl api` → API response
  ```bash
       kubectl exec -it frontend-7d46867bb4-6z4pq -- curl api
  ```
- From inside `frontend` pod: `curl database` → connection refused/timeout
  ```bash
       kubectl exec -it frontend-7d46867bb4-6z4pq -- curl database
  ```
- From inside `api` pod: `curl database` → DB response
  ```bash
      # Use the same labels as the image used by api doesnot have curl
      kubectl run curl-test --image=curlimages/curl -n team-alpha --rm -it --restart=Never --labels="app=api" -- curl http://database
  ```
- Shows your policies
  ```bash
      kubectl get networkpolicies -n team-alpha
  ```
- Shows the cert `READY=True` for your self-signed cert
  ```bash
      kubectl get certificate -n team-alpha
  ```
---

**Next: Task-04-Storage.md**
