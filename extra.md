### Context Pack: User Background

The user is an experienced DevOps learner with approximately 3 years of overall experience (limited real-world DevOps exposure in their current job). Their goal is to move into a **product-based company** as a **DevOps/Platform Engineer** and build a portfolio that stands out.

### Current Skills

#### Strong

* AWS (SAA certified)
* Terraform

  * Built a production-style, highly available, scalable AWS infrastructure.
  * Comfortable with modules, networking, ALB, ASG, RDS, IAM, etc.
* Docker
* Jenkins
* Git/GitHub
* Linux
* Basic Python/Shell scripting

#### Intermediate

* Kubernetes

  * Currently doing hands-on practice and deep-diving into concepts like networking, Ingress, Helm, etc.

#### Basic

* Ansible

  * Learned through tutorials and completed hands-on exercises.

---

### Important Constraint

The user's current company has provided **very little exposure** to modern DevOps tooling, so they are intentionally creating **deep-dive tutorials / mini-projects** to simulate real production experience.

These tutorials are **not beginner projects**; they are intended to replicate production workflows.

---

### Discussion Summary

The user originally planned to shift focus toward AI for DevOps.

However, they realized they have **little hands-on experience with many tools commonly found in production CI/CD pipelines**, including:

* SonarQube
* Vault
* Trivy
* Dependency scanning tools
* Other CI/CD ecosystem tools

Although they understand **what these tools do conceptually**, they have rarely installed, configured, or integrated them.

---

### Recommendation Given

The recommendation was **not** to jump directly into AI.

Instead, the proposed learning order was:

1. Finish Kubernetes.
2. Learn the surrounding DevOps ecosystem tools through hands-on integration:

   * SonarQube
   * Trivy
   * Vault (basic usage)
   * Helm
   * ArgoCD
   * Prometheus
   * Grafana
   * Dependency scanners
3. Build one complete production-style CI/CD pipeline that integrates these tools.
4. Only after understanding these tools, begin adding AI capabilities.

The reasoning:

AI in DevOps is mostly an **augmentation layer**, not a replacement for DevOps tools.

Examples discussed:

* AI summarizes Trivy reports.
* AI explains SonarQube findings.
* AI analyzes Jenkins failures.
* AI explains Kubernetes pod failures.
* AI searches internal documentation (RAG).
* AI generates incident summaries.

Therefore, understanding the underlying tools first provides much more value than learning AI APIs in isolation.

---

### User's Goal

The user wants to:

* Differentiate themselves from typical DevOps candidates.
* Gain practical experience missing from their current job.
* Build GitHub projects that resemble real production systems.
* Eventually learn AI specifically for DevOps automation and platform engineering rather than generic chatbot development.

Future recommendations should continue building toward that objective.
