# Kubernetes Notes: Graceful Shutdown & Zero-Downtime Rolling Updates

# Why Graceful Shutdown?

During a rolling update, Kubernetes replaces old Pods with new ones.

Without graceful shutdown, requests can fail during the transition, resulting in **5xx errors**.

Goal:

* No dropped requests
* No interrupted users
* Zero-downtime deployments

---

# The Problem

Suppose:

```text
Service
   │
   ├── Pod A
   ├── Pod B
   └── Pod C
```

A rolling update starts.

Kubernetes decides to terminate **Pod A**.

If Pod A exits immediately:

```text
Client
   │
Load Balancer
   │
Pod A (already exited)
```

The client receives:

* 500
* 502
* 503
* Connection reset

because the load balancer may still be routing traffic to Pod A.

---

# Graceful Shutdown Components

A graceful shutdown consists of three important pieces:

1. `preStop`
2. `SIGTERM`
3. `terminationGracePeriodSeconds`

Each solves a different problem.

---

# 1. preStop Lifecycle Hook

Example:

```yaml
lifecycle:
  preStop:
    exec:
      command:
      - /bin/sh
      - -c
      - sleep 5
```

Purpose:

> Delay application shutdown.

It **does not** remove the Pod from the Service.

Kubernetes already starts removing the Pod from the Service endpoints.

The delay simply gives:

* kube-proxy
* Ingress
* Cloud Load Balancer
* Service Mesh

time to notice that the Pod is being removed.

---

## Why is preStop needed?

Without it:

```text
0s  Remove Pod from Service endpoints
0s  SIGTERM
1s  Application exits
3s  Load Balancer stops routing traffic
```

Between 1–3 seconds:

* Load Balancer still sends requests.
* Application is already gone.
* Requests fail.

---

With preStop:

```text
0s  Remove Pod from Service endpoints
0-5s preStop (sleep)
3s  Load Balancer stops routing traffic
5s  SIGTERM
6s  Application exits
```

No dropped requests.

---

## Important

`preStop` **does not tell the Load Balancer to stop sending traffic.**

It simply waits while Kubernetes' endpoint removal propagates through the networking components.

---

## If 5 seconds isn't enough

Example:

```text
Load Balancer needs 8 seconds.
```

Increase:

```yaml
preStop:
  exec:
    command: ["/bin/sh", "-c", "sleep 10"]
```

Rule:

Choose a delay long enough for your networking stack to stop routing traffic.

---

# 2. SIGTERM

`SIGTERM` is a **Linux signal**.

It is **not** implemented by Kubernetes.

Kubernetes simply sends the signal.

The application is responsible for handling it.

---

## What should the application do?

A well-designed application should:

```text
Receive SIGTERM

↓

Stop accepting NEW requests

↓

Finish CURRENT requests

↓

Close database connections

↓

Flush logs

↓

Exit
```

---

## What if the application ignores SIGTERM?

Example:

```text
Receive SIGTERM

↓

Exit immediately
```

All in-flight requests fail.

Graceful shutdown requires application support.

---

# 3. terminationGracePeriodSeconds

Example:

```yaml
terminationGracePeriodSeconds: 60
```

Purpose:

Maximum amount of time Kubernetes waits after sending SIGTERM.

---

## Example

Application needs:

```text
45 seconds
```

Grace period:

```text
60 seconds
```

Result:

```text
SIGTERM

↓

Application finishes requests

↓

Application exits normally
```

---

If the application takes:

```text
90 seconds
```

Grace period:

```text
60 seconds
```

Timeline:

```text
0s  SIGTERM
60s SIGKILL
```

The application is forcefully terminated.

Remaining requests fail.

---

## If the grace period is too short

Increase:

```yaml
terminationGracePeriodSeconds: 120
```

so the application has enough time to finish existing requests.

---

# SIGKILL

`SIGKILL` is another Linux signal.

Unlike SIGTERM:

* Cannot be ignored
* Cannot be handled
* Immediately terminates the process

Kubernetes sends SIGKILL only when:

```text
terminationGracePeriodSeconds expires
```

---

# Complete Termination Sequence

```text
Pod deletion requested
        │
        ▼
Pod marked Terminating
        │
        ▼
Kubernetes removes Pod from Service endpoints
        │
        ▼
preStop executes
        │
        ▼
Kubernetes sends SIGTERM
        │
        ▼
Application stops accepting NEW requests
        │
        ▼
Application finishes CURRENT requests
        │
        ▼
Application exits
        │
        ▼
Pod deleted
```

If the application is still running after the grace period:

```text
SIGKILL

↓

Immediate termination

↓

Pod deleted
```

---

# Timeline Example

```text
0s  Delete Pod

0s  Remove Pod from Service endpoints

0-5s preStop

3s  Load Balancer stops routing traffic

5s  SIGTERM

5s  App stops accepting new requests

5-12s App finishes existing requests

12s App exits

12s Pod deleted
```

---

# Responsibilities

| Component                     | Responsibility                                                  |
| ----------------------------- | --------------------------------------------------------------- |
| Kubernetes                    | Remove Pod from Service endpoints                               |
| preStop                       | Delay shutdown while endpoint removal propagates                |
| Load Balancer / Ingress       | Stop routing new traffic                                        |
| SIGTERM                       | Tell the application to shut down gracefully                    |
| Application                   | Finish in-flight requests and exit                              |
| terminationGracePeriodSeconds | Maximum time Kubernetes waits                                   |
| SIGKILL                       | Forcefully terminate the process if it exceeds the grace period |

---

# Common Failure Scenarios

## Scenario 1

Problem:

New requests still arrive after the application exits.

Solution:

Increase:

```yaml
preStop:
  exec:
    command: ["/bin/sh", "-c", "sleep X"]
```

Reason:

The load balancer needs more time to stop routing traffic.

---

## Scenario 2

Problem:

Existing requests are interrupted.

Solution:

Increase:

```yaml
terminationGracePeriodSeconds
```

Reason:

The application needs more time to finish in-flight requests.

---

# Interview Questions

### Why is preStop needed?

To give the networking components enough time to stop routing new traffic before the application begins shutting down.

---

### Does preStop remove the Pod from the Service?

No.

Kubernetes removes the Pod from the Service endpoints.

`preStop` only delays shutdown.

---

### What is SIGTERM?

A Linux signal sent by Kubernetes to request a graceful application shutdown.

---

### What is terminationGracePeriodSeconds?

The maximum amount of time Kubernetes waits after sending SIGTERM before forcefully terminating the application with SIGKILL.

---

### What happens if the application doesn't exit before the grace period?

Kubernetes sends SIGKILL, immediately terminating the process. Any unfinished requests are aborted.

---

# Quick Revision

* `preStop` delays application shutdown.
* Kubernetes removes the Pod from Service endpoints.
* During `preStop`, the application is still running and can handle any requests that arrive while endpoint updates propagate.
* After `preStop`, Kubernetes sends SIGTERM.
* The application should stop accepting new requests and finish existing ones.
* `terminationGracePeriodSeconds` is the maximum time Kubernetes waits for a graceful shutdown.
* If the timer expires, Kubernetes sends SIGKILL.
* Increase `preStop` if new requests still reach the Pod during termination.
* Increase `terminationGracePeriodSeconds` if existing requests need more time to finish.
* Together, `preStop` + `SIGTERM` handling + `terminationGracePeriodSeconds` enable graceful shutdown and help achieve zero-downtime rolling updates.
