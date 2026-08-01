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

### securityContext Fields — What Each One Does

These fields can appear at **pod level** (`spec.securityContext`) or **container level** (`spec.containers[].securityContext`). Pod-level applies to all containers; container-level overrides it for that specific container.

| Field | Level | What it does |
|---|---|---|
| `runAsUser: 1000` | pod or container | Process runs as Linux UID 1000. Prevents running as root (UID 0). |
| `runAsGroup: 3000` | pod or container | Process's primary group is GID 3000. Affects file permission checks. |
| `fsGroup: 2000` | pod only | All volumes mounted into the pod have their files' group ownership changed to 2000. Useful so the process can read/write volume data. |
| `runAsNonRoot: true` | pod or container | K8s checks the resolved UID at admission — if it would be 0, the pod is **rejected**. Does not set a UID itself; use with `runAsUser`. |
| `readOnlyRootFilesystem: true` | container only | Mounts the container's root filesystem as read-only. The process cannot write anywhere on disk unless an explicit `emptyDir` or `volume` is mounted over writable paths. |
| `allowPrivilegeEscalation: false` | container only | Blocks the container from gaining more privileges than its parent process (disables `setuid`/`setgid` bits and `no_new_privs` Linux flag). Prevents exploits that use `sudo` or SUID binaries inside the container. |
| `capabilities.drop: ["ALL"]` | container only | Removes all Linux capabilities from the container. By default containers get a subset like `NET_BIND_SERVICE`, `CHOWN`, `DAC_OVERRIDE`, etc. Dropping ALL removes every one. |
| `capabilities.add: ["NET_BIND_SERVICE"]` | container only | Adds back specific capabilities after dropping. `NET_BIND_SERVICE` lets the process bind to ports < 1024 (like port 80) without root. |
| `seccompProfile.type: RuntimeDefault` | pod or container | Enables the container runtime's default seccomp filter. Seccomp restricts which Linux system calls the process can make — the runtime default blocks the most dangerous ones. |
| `privileged: true` | container only | Gives the container full root-equivalent access to the host kernel. **Never use in production** — equivalent to running directly on the node. |

**Critical distinction — ownership vs read-only:**
- `readOnlyRootFilesystem: true` prevents writes but does NOT change file ownership
- `runAsUser: 1000` changes WHO the process runs as but does NOT make root-owned dirs writable
- If a dir is owned by root and you run as UID 1000, you cannot write to it **regardless** of `readOnlyRootFilesystem` setting
- This is why nginx fails with `runAsUser: 1000` — `/var/cache/nginx/` is root-owned, UID 1000 has no write access

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