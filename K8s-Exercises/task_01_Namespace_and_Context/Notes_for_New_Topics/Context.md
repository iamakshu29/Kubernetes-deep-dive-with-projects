# Kubernetes Context - Complete Notes

## What is a kubeconfig?

A **kubeconfig** is a configuration file used by `kubectl` to determine:

* Which Kubernetes cluster to connect to.
* Which user credentials to use.
* Which namespace to use by default.

Default location:
```bash
~/.kube/config
```

A kubeconfig consists of three main objects:
```
kubeconfig
│
├── Clusters
├── Users
└── Contexts
```

---

# 1. Cluster

A **cluster** defines **where Kubernetes is running**.
It stores the connection details required to communicate with the Kubernetes API Server.

Example:
```yaml
clusters:
- name: production
  cluster:
    server: https://api.prod.company.com
    certificate-authority-data: LS0tLS1...
```

### Cluster stores
* API Server URL
* CA Certificate
* TLS information

### It does NOT store
* Username
* Token
* Namespace

Think of a cluster as:
> "Which Kubernetes API Server should kubectl talk to?"

---

# 2. User

A **user** defines **how kubectl authenticates** with the cluster.

Example:
```yaml
users:
- name: developer
  user:
    token: eyJhbGc...
```

A user may authenticate using:
* Bearer Token
* Client Certificate
* Username & Password (rare)
* AWS IAM
* Azure AD
* GCP
* OIDC
* Exec Plugins

Think of a user as:
> "Who am I?"

---

# 3. Context

A **context** combines

```
Cluster
+
User
+
Default Namespace
```

Example:
```yaml
contexts:
- name: dev
  context:
    cluster: dev-cluster
    user: developer
    namespace: payments
```

Think of a context as
> "Connect to this cluster as this user and start in this namespace."

---

# Relationship
```
Context
│
├── Cluster
├── User
└── Namespace
```

---

# Why do we need Context?

Without contexts, every command would look like this:
```bash
kubectl \
--server=https://api.company.com \
--token=xxxxx \
--namespace=payments \
get pods
```

Instead
```bash
kubectl config use-context prod
kubectl get pods
```

The context already knows
* cluster
* credentials
* namespace

---

# Real-world Analogy

Imagine logging into cloud servers.
Instead of remembering

```
Server IP
Username
SSH Key
Working Directory
```

you simply use
```
ssh production
```

A Kubernetes context works exactly like an SSH configuration alias.

---

# Viewing Contexts

Show all contexts

```bash
kubectl config get-contexts
```

Example
```
CURRENT   NAME
*         dev
          qa
          prod
```

Current context
```bash
kubectl config current-context
```

Output
```
dev
```

---

# Switching Contexts
```bash
kubectl config use-context prod
```

Now every kubectl command talks to the production cluster (or uses the production configuration).

---

# Creating a Context
```bash
kubectl config set-context dev \
  --cluster=dev-cluster \
  --user=developer \
  --namespace=payments
```

---

# Deleting a Context
```bash
kubectl config delete-context dev
```

---

# Can Multiple Contexts Use the Same Cluster?

Yes.

Example
```
Cluster
│
├── payments namespace
├── orders namespace
├── monitoring namespace
```

Contexts
```
payments-context
    cluster = prod
    namespace = payments

orders-context
    cluster = prod
    namespace = orders

monitor-context
    cluster = prod
    namespace = monitoring
```

All three contexts point to the same cluster.
Only the namespace changes.

---

# Can Multiple Contexts Use Different Users?

Yes.

```
Context 1

Cluster = prod
User = developer

-------------------

Context 2

Cluster = prod
User = admin
```

Same cluster.
Different permissions.

---

# Can Multiple Contexts Use Different Clusters?

Yes.

```
dev-context

Cluster = Dev

-------------------

qa-context

Cluster = QA

-------------------

prod-context

Cluster = Production
```

This is the most common setup in enterprise environments.

---

# Do We Switch Clusters Frequently?

It depends on the organization.

### Small Company
```
One Cluster

Namespaces

dev
qa
prod
```

Usually:
* One cluster
* Multiple namespaces

Developers mostly switch namespaces.

---

### Large Company
```
Dev Cluster

QA Cluster

Stage Cluster

Production Cluster
```

Developers often switch contexts because each environment has a separate cluster.

---

# Why Separate Clusters?

Reasons include:
* Better security
* Isolation
* Independent upgrades
* Separate RBAC policies
* Resource isolation
* Avoid production impact
* Disaster recovery

Example:
```
Dev Cluster

32 GB RAM

-----------------

Production Cluster

512 GB RAM
```

Production and development should not compete for the same resources.

---

# Namespace vs Context
Many beginners confuse these.

| Namespace                                | Context                                             |
| ---------------------------------------- | --------------------------------------------------- |
| Logical partition inside a cluster       | Configuration profile                               |
| Organizes resources                      | Selects cluster, user, and namespace                |
| Multiple namespaces exist in one cluster | Multiple contexts can point to one or many clusters |
| Changes where resources are searched     | Changes how kubectl connects                        |

---

# Namespace Switching

Instead of creating many contexts, you can change only the namespace.
```bash
kubectl config set-context --current --namespace=payments
```

Current context remains the same.
Only the namespace changes.

---

# Common Interview Question

**Q:** What does a context contain?
**Answer:**
A Kubernetes context contains:
* Cluster
* User
* Default Namespace

**Q:** Why do we use contexts?
**Answer:**
Contexts provide a convenient way to switch between different Kubernetes configurations. Instead of specifying the cluster, user credentials, and namespace with every `kubectl` command, a context stores these settings under a single name, making it easy to work with multiple environments.

**Q:** Can two contexts point to the same cluster?
**Answer:**
Yes. Multiple contexts can reference the same cluster while using different users, different namespaces, or both. This is useful for role-based access (developer vs. admin) or for quickly switching between namespaces.

---

# Real-world kubeconfig Example

```yaml
clusters:
- name: dev-cluster
- name: prod-cluster

users:
- name: developer
- name: admin

contexts:
- name: dev
  cluster: dev-cluster
  user: developer
  namespace: backend

- name: prod
  cluster: prod-cluster
  user: admin
  namespace: payments
```

Using:
```bash
kubectl config use-context dev
```

means:
```
Cluster   : dev-cluster
User      : developer
Namespace : backend
```

---

# Quick Revision

```
Cluster
↓
Where is Kubernetes?

User
↓
Who am I?

Namespace
↓
Which logical area inside the cluster?

Context
↓
Cluster + User + Namespace

kubeconfig
↓
Stores Clusters + Users + Contexts
```

---

# Commands Cheat Sheet

| Command                                                                                | Purpose                                             |
| ----------------------------------------------------------------------------------------| -----------------------------------------------------|
| `kubectl config view`                                                                  | View kubeconfig                                     |
| `kubectl config get-contexts`                                                          | List all contexts                                   |
| `kubectl config current-context`                                                       | Show active context                                 |
| `kubectl config use-context <name>`                                                    | Switch context                                      |
| `kubectl config set-context <name> --cluster=<cluster> --user=<user> --namespace=<ns>` | Create or modify a context                          |
| `kubectl config set-context --current --namespace=<ns>`                                | Change the default namespace of the current context |
| `kubectl config delete-context <name>`                                                 | Delete a context                                    |
| `kubectl config rename-context <current_name> <updated_name>`                          | Rename the Context name                             |

---

# Key Takeaways

* **Cluster** = *Where to connect?*
* **User** = *Who is connecting?*
* **Namespace** = *Which logical area inside the cluster?*
* **Context** = *A named combination of Cluster + User + Default Namespace.*
* **kubeconfig** = *A file that stores all clusters, users, and contexts so `kubectl` knows how to communicate with Kubernetes.*

This level of understanding is sufficient for most Kubernetes certifications (CKA/CKAD) and DevOps interviews, and it also reflects how contexts are used in production environments.
