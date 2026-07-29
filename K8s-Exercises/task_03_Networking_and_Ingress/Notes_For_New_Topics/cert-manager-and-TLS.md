# cert-manager and TLS in Kubernetes

---

## The Problem cert-manager Solves

Every HTTPS connection needs a TLS certificate. Without automation:
- You generate a cert manually with `openssl`
- You create a Kubernetes Secret manually
- You renew it manually every 90 days
- Someone forgets → cert expires → users see browser errors → 3am incident

cert-manager is a **Kubernetes controller** that automates the entire lifecycle below:
1. Issue a cert (talk to a CA, get it signed)
2. Store it as a TLS Secret in your cluster
3. Watch expiry — renew automatically 30 days before it expires
4. If the Secret is deleted — re-issue immediately

**That is its entire job.** It is not a CA itself. It is the automation layer between your cluster and a CA.

---

## Core Concepts — Before The Flows

### What is a CA?
A Certificate Authority (CA) is an entity that **signs** certificates. When a CA signs your cert, it is saying: "I vouch that this cert belongs to frontend.local." Browsers have a built-in list of trusted CAs. If the CA that signed your cert is in that list → green padlock. If not → "Not Secure" warning.

### What is TLS Termination?
TLS terminates at the **Ingress Controller**, not at the pod.
```
Client  --HTTPS-->  Ingress Controller (decrypts using tls.key from TLS Secret)
                         --HTTP-->  Service  --HTTP-->  Pod
```
The Service and Pod know nothing about TLS. The cert lives only at the Ingress Controller.

### What is inside a TLS Secret?
```
tls.crt  → the certificate for your domain (e.g. frontend.local)
tls.key  → the private key paired with the cert
ca.crt   → the CA certificate that signed tls.crt
```

### ClusterIssuer vs Issuer
| Resource | Scope | Use |
|---|---|---|
| `ClusterIssuer` | Cluster-wide | One issuer for all namespaces (standard choice) |
| `Issuer` | Namespace-scoped | One issuer per namespace (advanced, rare) |

---

## The Three Cert-Manager Flows

---

### Flow 1 — Self-Signed (Local Dev / Internal Tools)

**You are the CA. No external trust. Browsers show "Not Secure."**

```
CertManager Installed
      ↓
ClusterIssuer (selfSigned: {})
      ↓
Certificate resource (you create this)
      ↓  cert-manager sees it, calls the selfSigned issuer
      ↓  generates a key pair locally
      ↓  signs the cert with its own private key (no external call)
      ↓
TLS Secret auto-created: tls.crt + tls.key + ca.crt
      ↓
You reference secretName in your Ingress tls: block
      ↓
Ingress Controller serves HTTPS using that cert
```

**Key fact about self-signed:** `tls.crt` and `ca.crt` are the **same certificate**.
The cert signs itself — it IS its own CA. No chain of trust exists outside your cluster.

**When to use:**
- Local kind/minikube clusters
- Internal tools where you control the trust store
- Learning and exercises

**YAML to create this:**
```yaml
# Step 1 — ClusterIssuer
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}      # ← no external CA, signs locally

---
# Step 2 — Certificate (you create this manually)
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: alpha-tls
  namespace: team-alpha
spec:
  secretName: alpha-tls-secret      # ← cert-manager will create this Secret
  issuerRef:
    name: selfsigned-issuer
    kind: ClusterIssuer
  dnsNames:
  - frontend.local
  - api.local

---
# Step 3 — Reference in Ingress
tls:
- hosts:
  - frontend.local
  - api.local
  secretName: alpha-tls-secret
```

**Commands to verify:**
```bash
kubectl get clusterissuer
kubectl get certificate -n team-alpha          # READY=True means cert issued
kubectl get secret alpha-tls-secret -n team-alpha
kubectl describe secret alpha-tls-secret -n team-alpha   # shows tls.crt, tls.key, ca.crt
```

---

### Flow 2 — Let's Encrypt, Manual Certificate (Production — You Control Certificate Timing)

**Let's Encrypt is a real trusted CA. Browsers trust it. You create the Certificate resource yourself.**

```
CertManager Installed
      ↓
ClusterIssuer (ACME / Let's Encrypt URL)
      ↓
Certificate resource (you create this)
      ↓  cert-manager sees it
      ↓  calls Let's Encrypt ACME API: "I need a cert for frontend.company.com"
      ↓  Let's Encrypt says: "Prove you own that domain" → HTTP-01 Challenge
      ↓  cert-manager completes the challenge (see HTTP-01 section below)
      ↓  Let's Encrypt verifies → SIGNS the cert with LE's CA key → sends back
      ↓
TLS Secret auto-created: tls.crt (signed by LE) + tls.key + ca.crt (LE's CA cert)
      ↓
You reference secretName in your Ingress tls: block
      ↓
cert-manager monitors expiry → auto-renews 30 days before → updates Secret
```

**Key fact:** `tls.crt` ≠ `ca.crt` here.
- `tls.crt` = your domain cert, signed by Let's Encrypt
- `ca.crt` = Let's Encrypt's own CA cert (what browsers have in their trust store)

**YAML to create this:**
```yaml
# Step 1 — ClusterIssuer pointing to Let's Encrypt
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory  # ← LE's ACME API endpoint
    email: your-email@company.com
    privateKeySecretRef:
      name: letsencrypt-prod-key  # ← cert-manager stores its auth key here (not your cert)
    solvers:
    - http01:
        ingress:
          class: nginx             # ← which ingress controller handles the challenge

---
# Step 2 — Certificate (you create this manually)
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: frontend-tls
  namespace: team-alpha
spec:
  secretName: frontend-tls-secret
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
  - frontend.company.com
  - api.company.com

---
# Step 3 — Reference in Ingress
tls:
- hosts:
  - frontend.company.com
  - api.company.com
  secretName: frontend-tls-secret
```

---

### Flow 3 — Let's Encrypt, Automatic via Annotation (Production — Recommended for Scale)

**Same as Flow 2, but cert-manager auto-creates the Certificate resource for you. You skip Step 2.**

```
You write Ingress with:
  - tls: block (hosts + secretName)
  - annotation: cert-manager.io/cluster-issuer: "letsencrypt-prod"
      ↓
cert-manager's ingress-shim watches all Ingress resources
      ↓  sees the annotation + the tls: block
      ↓  auto-creates a Certificate resource for the listed hostnames
      ↓  calls LE → HTTP-01 challenge → cert signed
      ↓
TLS Secret created with the secretName from your Ingress tls: block
      ↓
Ingress Controller reads the secret (it was already pointing to that secretName)
      ↓
cert-manager monitors expiry → auto-renews → updates Secret → zero downtime
```

**YAML to create this:**
```yaml
# Step 1 — ClusterIssuer (same as Flow 2, created once for the cluster)
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

---
# Step 2 — Ingress with annotation (NO Certificate resource needed)
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-ingress
  namespace: team-alpha
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"    # ← this triggers auto-issuance
    nginx.ingress.kubernetes.io/rewrite-target: /$2
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - frontend.company.com
    - api.company.com
    secretName: frontend-tls-secret    # ← cert-manager will create this
  rules:
  - host: frontend.company.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: frontend-svc
            port:
              number: 80
  - host: api.company.com
    http:
      paths:
      - path: /api(/|$)(.*)
        pathType: ImplementationSpecific
        backend:
          service:
            name: api-svc
            port:
              number: 80
```

**For 50 services/Ingresses:** just add the annotation to each Ingress. The ClusterIssuer is created once and shared. Use wildcard certs (`*.company.com`) for maximum efficiency — one Certificate covers all subdomains.

---
## We understand that there are two ways to request a certificate:
  1. Create a Certificate resource.
  2. Add the annotation to an Ingress.
     cert-manager.io/cluster-issuer: "letsencrypt-prod"
   
In the first approach, cert-manager watches the Certificate resource and issues the certificate.
In the second approach, cert-manager's ingress-shim notices the annotation, automatically creates a Certificate resource, and then cert-manager issues the certificate.
In both cases, the end result is the same: cert-manager obtains the certificate from the configured ClusterIssuer and stores it in the specified Kubernetes tls Secret.
---

## HTTP-01 Challenge — How cert-manager Proves Domain Ownership

Let's Encrypt needs to verify that YOU control the domain before signing a cert for it. Otherwise anyone could get a cert for `google.com`. The HTTP-01 challenge is one method for this proof.

### The Challenge — Step by Step

```
1. cert-manager → Let's Encrypt ACME API
   "Please sign a cert for frontend.company.com"

2. Let's Encrypt → cert-manager
   "Place this token at this exact URL:
    http://frontend.company.com/.well-known/acme-challenge/abc123xyz
    The response body must be: abc123xyz.myaccountfingerprint"

3. cert-manager → creates a temporary Ingress rule (or uses existing one)
   that routes /.well-known/acme-challenge/abc123xyz → a temporary pod
   that serves the exact token string

4. Let's Encrypt → makes an HTTP GET request to:
   http://frontend.company.com/.well-known/acme-challenge/abc123xyz
   (from LE's own servers, from the public internet)

5. If the response matches the expected token:
   Let's Encrypt: "You control that domain. Here is your signed certificate."
   cert-manager: receives signed cert → stores as TLS Secret

6. cert-manager cleans up the temporary Ingress rule and pod
```

### Why HTTP-01 Does NOT Work for `.local` or Internal Domains

Let's Encrypt makes a real HTTP request **from the public internet** to your domain.
If `frontend.local` is not reachable from the internet, LE cannot hit that URL → challenge fails → no cert.

Self-signed is the only option for `.local`, private IPs, or internal cluster hostnames.

### Alternative: DNS-01 Challenge

Instead of serving a file, you prove ownership by adding a DNS TXT record to your domain.
Useful for wildcard certs (`*.company.com`) and internal services (no public HTTP needed).
Requires your DNS provider's API to be integrated with cert-manager.

---

## Comparison Table — All Three Flows

| | Self-Signed | LE Manual | LE Automatic |
|---|---|---|---|
| CA | The cert itself | Let's Encrypt | Let's Encrypt |
| Browser trust | ❌ "Not Secure" | ✅ Green padlock | ✅ Green padlock |
| Challenge needed? | No | HTTP-01 | HTTP-01 |
| Works for `.local` / private domains? | ✅ Yes | ❌ No | ❌ No |
| You create Certificate resource? | Yes | Yes | No (annotation does it) |
| You create TLS Secret? | No (cert-manager) | No (cert-manager) | No (cert-manager) |
| You write Ingress tls: block? | Yes | Yes | Yes |
| Auto-renew? | Yes | Yes | Yes |
| tls.crt == ca.crt? | Yes | No | No |
| Use case | Local dev / exercises | Prod (manual control) | Prod (scale, 50+ services) |

> **`.local` / private domains:** Let's Encrypt must make a real HTTP request from the public internet to verify domain ownership. Domains like `frontend.local`, private IPs, or internal hostnames have no public DNS record — LE's servers can never reach them → challenge fails → no cert. Self-signed is the only option for these. For production, your domain must be a real public domain like `frontend.company.com`.

> **Auto-renew:** All three flows auto-renew. Self-signed = cert-manager regenerates locally before expiry. LE = cert-manager re-runs the ACME + HTTP-01 challenge before expiry. Default cert duration is 90 days; cert-manager renews at 30 days before expiry for all three.

---

## What ClusterIssuer Actually Is

| Mode | What it is | What cert-manager does when it sees it |
|---|---|---|
| `selfSigned: {}` | "Sign locally, no external CA" | Generates key pair, signs cert with itself |
| `acme: server: <LE URL>` | "Connection config to LE's ACME API" | Calls LE, does HTTP-01 challenge, gets LE to sign cert |

The ClusterIssuer is **not** the CA in the LE case. It just tells cert-manager the address and credentials to reach the CA (Let's Encrypt).

The signing always happens at the CA (LE's servers). cert-manager receives the signed cert and stores it.

---

## What Happens if You Hit HTTPS Without Any Cert

The NGINX Ingress Controller never hard-fails on missing certs. It ships with a **built-in default fake certificate** (literally named "Kubernetes Ingress Controller Fake Certificate"). If no TLS Secret is configured for a host, NGINX serves this fake cert.

```bash
curl https://localhost
# error 60: SSL certificate verify failed: unable to get local issuer certificate
# The fake cert is signed by nobody trusted and hostname doesn't match

curl -k https://localhost
# Works — -k skips cert verification (insecure, testing only)

# Browser: "Your connection is not private" / NET::ERR_CERT_AUTHORITY_INVALID
```

| State | HTTP (`curl localhost`) | HTTPS (`curl -k https://localhost`) |
|---|---|---|
| No `tls:` block in Ingress | Works normally | Fake default cert — SSL warning |
| `tls:` block + Secret not yet created | 301 redirect to HTTPS | Fake cert (Secret missing) |
| `tls:` block + self-signed Secret | 301 redirect (ssl-redirect on) | Works — browser self-signed warning |
| `tls:` block + Let's Encrypt Secret | 301 redirect | Works — green padlock |

The fake cert is NGINX's safety net so HTTPS doesn't crash. But it provides zero security and every browser will warn the user.

---

## ssl-redirect Behavior After Adding TLS

Once a `tls:` block exists in an Ingress, NGINX Ingress Controller enables `ssl-redirect: true` by default.

```
curl http://frontend.local      →  301 redirect to https://frontend.local
curl https://frontend.local     →  cert warning (self-signed) or works (LE)
```

**To allow HTTP alongside HTTPS:**
```yaml
annotations:
  nginx.ingress.kubernetes.io/ssl-redirect: "false"
```

**Or follow the redirect:**
```bash
curl -k -L http://frontend.local    # -k = ignore cert warning, -L = follow redirect
```

---

## Debugging Commands

```bash
# Check cert-manager pods are running
kubectl get pods -n cert-manager

# Check ClusterIssuer status
kubectl get clusterissuer
kubectl describe clusterissuer letsencrypt-prod   # check READY=True

# Check Certificate status
kubectl get certificate -n team-alpha             # READY column should be True
kubectl describe certificate alpha-tls -n team-alpha   # shows events and reason if stuck

# Check the TLS Secret was created
kubectl get secret alpha-tls-secret -n team-alpha
kubectl describe secret alpha-tls-secret -n team-alpha   # shows tls.crt, tls.key, ca.crt

# Watch cert-manager logs for issuance activity
kubectl logs -n cert-manager -l app=cert-manager --follow

# Simulate deletion and watch re-issue
kubectl delete secret alpha-tls-secret -n team-alpha
kubectl get secret -n team-alpha -w    # watch it reappear in seconds
```

---

## Common Mistakes

| Mistake | Symptom |
|---|---|
| Using `selfSigned` issuer for a public domain | Browser "Not Secure" in production |
| HTTP-01 challenge on a `.local` domain | Certificate stays `READY=False`, LE can't reach the domain |
| Forgetting `tls:` block in Ingress | Secret exists but HTTPS is not served |
| Wrong `secretName` in Ingress `tls:` | Ingress uses default self-signed cert, not your cert |
| Ingress `tls: hosts:` missing hostnames | TLS does not apply to your host rules |
| No annotation + no Certificate resource | cert-manager never issues anything |
