# Ingress — Working Notes

---

## How NGINX Ingress Actually Works (Internal Flow)

```
curl localhost
  → host port 80/443 (via kind extraPortMappings or cloud LB)
    → NGINX Ingress Controller pod (bound to those ports via hostPort)
      → reads Ingress rules from kube-apiserver (watches them live)
        → matches host or path
          → proxies to backend Service ClusterIP
            → kube-proxy forwards to a pod
```

**Key point:** The Ingress Controller is just an NGINX process. It reads your `Ingress` YAML and writes an `nginx.conf` internally. Every time you `kubectl apply` an Ingress resource, the controller reloads its config.

---

## Path Types — When to Use Which

| pathType | Behaviour | Use when |
|---|---|---|
| `Exact` | URL must match exactly — `/api` matches only `/api`, NOT `/api/` or `/api/users` | You want strict matching, rarely used |
| `Prefix` | Matches the prefix — `/api` matches `/api`, `/api/`, `/api/users` | Standard path-based routing, most common |
| `ImplementationSpecific` | Controller-specific matching — for NGINX, enables regex | Required when using `rewrite-target` with capture groups |

**Rule of thumb:** Use `Prefix` by default. Only use `ImplementationSpecific` when you need regex for `rewrite-target`.

---

## rewrite-target — When and Why

**Problem:** Ingress routes `/api/users` to `api-svc`. The pod receives `GET /api/users`. If the backend app only handles `GET /users`, it returns 404.

**Root cause:** Ingress forwards the original path unchanged unless you tell it to rewrite.

**Fix:**
```yaml
annotations:
  nginx.ingress.kubernetes.io/rewrite-target: /$2

# In the rule:
path: /api(/|$)(.*)          # group $2 captures everything after /api
pathType: ImplementationSpecific
```

`/api/users` → group `$2` = `users` → pod receives `/users` ✅  
`/api` → group `$2` = `` (empty) → pod receives `/` ✅

**When NOT needed:** If your backend serves at the same path as your Ingress rule (e.g. Ingress path `/` → pod serves at `/`), no rewrite needed.

---

## TLS — What Happens Under the Hood

```
Browser → https://frontend.local:443
  → NGINX Ingress presents the TLS certificate from the Secret
    → TLS handshake completes
      → NGINX decrypts, matches host rule, proxies HTTP internally to the pod
```

The pod itself never sees HTTPS — NGINX terminates TLS and forwards plain HTTP. This is called **TLS termination at the ingress**.

### SSL Redirect (the gotcha)

When ANY `tls:` block exists in an Ingress, NGINX enables `ssl-redirect: true` by default — all HTTP requests to that Ingress get a **301 redirect to HTTPS**.

- `curl localhost` → 301 → `https://localhost` → if cert doesn't match hostname, SSL error
- Fix for testing: `curl -k -L localhost` (`-k` = skip cert verify, `-L` = follow redirect)
- Fix permanently: add annotation `nginx.ingress.kubernetes.io/ssl-redirect: "false"`

---

## TLS Secret Structure

cert-manager (or manual) creates a Secret with 3 keys:

```
alpha-tls-secret
  ├── tls.crt   — the certificate (public)
  ├── tls.key   — the private key
  └── ca.crt    — the CA that signed it
```

Referenced in the Ingress:
```yaml
tls:
- hosts:
  - frontend.local
  - api.local
  secretName: alpha-tls-secret
```

**Important:** `hosts` here must match the `dnsNames` in the Certificate resource. NGINX uses SNI to pick the right cert when multiple TLS secrets exist.

---

## Important Annotations (Quick Reference)

```yaml
annotations:
  # Path rewriting
  nginx.ingress.kubernetes.io/rewrite-target: /$2

  # Disable HTTP→HTTPS redirect (useful for local testing)
  nginx.ingress.kubernetes.io/ssl-redirect: "false"

  # Rate limiting
  nginx.ingress.kubernetes.io/limit-rps: "10"

  # Enable CORS
  nginx.ingress.kubernetes.io/enable-cors: "true"

  # Custom timeouts
  nginx.ingress.kubernetes.io/proxy-connect-timeout: "30"
  nginx.ingress.kubernetes.io/proxy-read-timeout: "60"

  # Attach cert-manager issuer (auto-provisions TLS cert)
  cert-manager.io/cluster-issuer: "letsencrypt-prod"
```

---

## Common Debugging Commands

```bash
# Is the ingress controller running?
kubectl get pods -n ingress-nginx

# What does the controller see?
kubectl logs -n ingress-nginx <controller-pod>

# Are the Ingress rules registered?
kubectl get ingress -n team-alpha
kubectl describe ingress app-ingress -n team-alpha

# Is the backend service reachable from the controller?
kubectl get endpoints frontend-svc -n team-alpha   # empty = selector mismatch

# Test with explicit Host header (no /etc/hosts edit needed)
curl -H "Host: frontend.local" http://localhost
curl -k -H "Host: frontend.local" https://localhost
```

---

## Things That Silently Break Ingress

| Issue | Symptom | Check |
|---|---|---|
| baremetal manifest on kind | error 52/35 | Use kind manifest |
| TLS secret missing | NGINX uses default self-signed cert | `kubectl get secret -n team-alpha` |
| `hosts:` empty in tls block | TLS applies to all, cert SNI won't match | List hosts explicitly |
| `pathType: Exact` on `/api` | Sub-paths 404 | Use `Prefix` or `ImplementationSpecific` |
| No `rewrite-target` | Backend gets full path including prefix | Add annotation + regex path |
| Wrong IngressClass | Rules ignored by controller | `spec.ingressClassName: nginx` must match |
