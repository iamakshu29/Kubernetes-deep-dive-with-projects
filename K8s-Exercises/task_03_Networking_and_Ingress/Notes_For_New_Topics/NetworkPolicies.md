# NetworkPolicies — Working Notes

---

## Core Rule — How policyTypes Controls Default Behavior

A NetworkPolicy only affects pods that its `podSelector` matches.
For each matched pod, the **direction is what matters**:

| What's in policyTypes | Ingress behavior | Egress behavior |
|---|---|---|
| Nothing (policy not matching this pod) | Allow all | Allow all |
| `[Ingress]` | Default deny — only listed rules allowed | Allow all (untouched) |
| `[Egress]` | Allow all (untouched) | Default deny — only listed rules allowed |
| `[Ingress, Egress]` | Default deny | Default deny |

**One-liner to remember:**
> If a direction appears in `policyTypes`, it becomes **deny-all except what you explicitly allow**.
> If a direction is absent, it stays **allow-all**.

---

## The 3 Cases

### Case 1 — Ingress only
```yaml
policyTypes:
- Ingress
ingress:
- from:
  - podSelector:
      matchLabels:
        app: api
```
Applied to `app=database` pods:
- ✅ Ingress from `app=api` → allowed
- ❌ Ingress from anything else → denied
- ✅ Egress to anywhere → still allowed (not listed in policyTypes)

---

### Case 2 — Egress only
```yaml
policyTypes:
- Egress
egress:
- to:
  - podSelector:
      matchLabels:
        app: database
```
- ✅ Egress to `app=database` → allowed
- ❌ Egress to anything else → denied
- ✅ Ingress from anywhere → still allowed

---

### Case 3 — Both (Zero-Trust)
```yaml
policyTypes:
- Ingress
- Egress
# no rules = deny everything in both directions
```
Empty rules = full deny. Add back only what you need.

---

## Mental Model — How to Design NetworkPolicies for Frontend / Backend / DB

**Yes — the correct approach is exactly what you thought:**
> Start with deny-all, allow DNS first, then open specific paths.

### Step-by-step approach

**Step 1 — Default deny-all for the namespace**
```yaml
podSelector: {}          # matches ALL pods in the namespace
policyTypes:
- Ingress
- Egress
# no rules = deny everything
```

**Step 2 — Allow DNS egress (ALWAYS do this first)**
```yaml
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
Without this, `curl db-svc` fails even if the DB is explicitly allowed — because the pod can't resolve the name to an IP.

**Step 3 — Open specific paths**

For a 3-tier app (frontend → api → database):

```
frontend  ---[egress:80]-->  api  ---[egress:80]-->  database
          <--[ingress:80]---       <--[ingress:80]---
```

You need **two policies per connection** — one for egress on the sender, one for ingress on the receiver:

| Policy | podSelector | Direction | Allows |
|---|---|---|---|
| allow-frontend-to-api | `app=frontend` | Egress | to `app=api` port 80 |
| allow-api-ingress | `app=api` | Ingress | from `app=frontend` |
| allow-api-to-db | `app=api` | Egress | to `app=database` port 80 |
| allow-db-ingress | `app=database` | Ingress | from `app=api` |

**Step 4 — Allow Ingress controller to reach frontend/api**
```yaml
# Without this, curl localhost fails even though Ingress rules look correct
podSelector:
  matchLabels:
    app: frontend   # repeat for app=api
policyTypes:
- Ingress
ingress:
- from:
  - namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: ingress-nginx
```

---

## Common Mistakes

| Mistake | Symptom |
|---|---|
| Forget DNS egress before default-deny | `curl svc-name` times out even when the service is allowed |
| Only write ingress policy, forget egress on sender | Receiver allows it, but sender is blocked at egress |
| Use `team: alpha` label on namespaceSelector | Namespace doesn't have that label — policy silently matches nothing. Use `kubernetes.io/metadata.name` |
| Apply default-deny without allowing ingress-nginx | `curl localhost` breaks through Ingress |

---

## AND vs OR in `from:` / `to:`

```yaml
# AND — source must satisfy BOTH conditions (same list item)
- from:
  - namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: team-alpha
    podSelector:
      matchLabels:
        app: api

# OR — source satisfies EITHER condition (separate list items)
- from:
  - namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: team-alpha
  - podSelector:
      matchLabels:
        app: api
```
The indentation determines AND vs OR. Easy to get wrong silently.
