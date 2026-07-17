# Task 03 — Networking, Services & Ingress

> Real-world relevance: Networking is where most K8s problems surface.
> "Why can't my pod reach the database?", "Why is traffic not reaching my app?" —
> you will be the person who debugs and fixes these. This task builds that muscle.

> **Cluster needed:** 2-node kind cluster with **Calico CNI** (required for NetworkPolicies to actually be enforced).
> - **Important:** Default kind/minikube CNI (kindnet/flannel) does NOT enforce NetworkPolicies. You must use Calico.
> - **Kind + Calico setup:** Disable default CNI in kind config, then install Calico manually (see 00-Setup.md).
> - **Easiest option for NetworkPolicy exercises:** Killercoda — it runs Calico by default.
> - **Ingress exercises:** kind cluster with `extraPortMappings` for port 80/443 (see 00-Setup.md kind config).
> - Multipass cluster (from 00-Setup.md) already has Calico installed — fully compatible.

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

## Completion Checklist

- [ ] Explain all service types and choose the right one for a scenario
- [ ] Resolve services by DNS name from inside a pod
- [ ] Set up Ingress with path and host-based routing
- [ ] Write NetworkPolicies that allow specific cross-pod traffic
- [ ] Debug service connectivity issues using endpoints, logs, and exec

---

## Interview Questions This Task Prepares You For

- "How does DNS work inside a Kubernetes cluster?"
- "Walk me through how you expose an application to the internet in K8s."
- "We had a security incident where one compromised pod could reach all databases. How do you prevent that?"
- "How would you debug a pod that can't connect to a service?"
- "What is the difference between Ingress and a LoadBalancer Service?"

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
