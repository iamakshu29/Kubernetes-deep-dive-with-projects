# Pod Security Admission (PSA) — Notes

## What It Is
- Built into Kubernetes 1.25+ as a native **admission controller** (not a separate resource, no CRD, no controller to deploy)
- Replaced **PodSecurityPolicy (PSP)**, which was removed
- Operates by reading **labels on a Namespace object**
- Every pod create/update request in that namespace is checked against those labels **before** the pod is persisted — reject means the pod never runs

## Two Independent Axes

### 1. Profile — defines WHAT is checked (fixed, not configurable)

| Profile      | Checks                                                                                                                                                                                                                                |
| --------------| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `privileged` | No restrictions                                                                                                                                                                                                                       |
| `baseline`   | Blocks: privileged containers, host namespace sharing (`hostNetwork`, `hostPID`, `hostIPC`), host path volume mounts, dangerous Linux capabilities                                                                                    |
| `restricted` | Everything in `baseline`, **plus**: `runAsNonRoot: true` required, `allowPrivilegeEscalation: false` required, all capabilities dropped (only `NET_BIND_SERVICE` addable), seccomp profile required (`RuntimeDefault` or `Localhost`) |

- `restricted` ⊇ `baseline` ⊇ `privileged` (each is a strict superset of checks)
- No custom/partial profiles exist — for org-specific rules (e.g. "images must come from X registry") you need Kyverno/OPA Gatekeeper on top; PSA cannot do this

### 2. Mode — defines WHAT HAPPENS on violation

| Mode | Behavior |
|---|---|
| `enforce` | Pod is **rejected** — never created |
| `warn` | Pod **is created**; `kubectl` prints a client-side warning |
| `audit` | Pod **is created**; violation is written to the audit log only |

- All three modes can be set simultaneously on one namespace, each pointing at a **different** profile
- Realistic staged-rollout pattern:
  ```
  enforce=baseline    # hard floor — nothing dangerous gets in
  warn=restricted     # tells devs "this would fail once we tighten enforcement"
  audit=restricted    # logs it for compliance reporting
  ```
- Setting `enforce=restricted` + `warn=baseline` (as in a basic exercise) is logically redundant — anything passing `restricted` already satisfies `baseline`

## Namespace Labeling Syntax
```bash
kubectl label namespace team-alpha \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/enforce-version=latest \
  pod-security.kubernetes.io/warn=baseline \
  pod-security.kubernetes.io/warn-version=latest
```
- `-version=latest` pins to the newest profile definition as it evolves across k8s releases

## securityContext — What It Actually Does
- Profiles define fixed, non-configurable requirements
- `securityContext` does **not** define rules — it makes a pod's spec **satisfy** rules that already exist in the enforced profile
- Analogy: profile = the exam questions (fixed); `securityContext` = your pod's answers
- No `securityContext` + `enforce=restricted` → rejected (fails `runAsNonRoot` requirement, etc.)
- `securityContext` with correct fields → passes, because it now answers what the profile demands

Minimum `securityContext` to satisfy `restricted`:
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  allowPrivilegeEscalation: false
  seccompProfile:
    type: RuntimeDefault
  capabilities:
    drop: ["ALL"]
```
Note: `readOnlyRootFilesystem: true` is good hardening practice but is **not** actually a `restricted` profile requirement.

## Why PSP Was Removed (vs PSA)
| Problem with PSP | How PSA fixes it |
|---|---|
| PSP applicability was determined via RBAC bindings to service accounts/users — indirect, hard to trace | PSA applicability is a direct, visible namespace label |
| Ordering of which PSP applied when multiple were authorized was ambiguous | Each namespace has exactly one profile per mode — no ambiguity |
| Couldn't look at a namespace and know its security posture without tracing RBAC | Read 3 labels on the namespace, done |

## Why Some Namespaces Stay `privileged`
- System/infra tools legitimately need host access
- Example: Prometheus `node-exporter` needs `hostNetwork`/`hostPID` to read host-level metrics — `baseline` or `restricted` would block this