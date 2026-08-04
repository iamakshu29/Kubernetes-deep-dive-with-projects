Chart structure – understand what files exist and why.
Values – learn how configuration flows from values.yaml, -f, and --set.
Templates – variables, if, range, helper functions, and indentation.
Releases – install, upgrade, rollback, history, uninstall.
Chart dependencies – reuse existing charts and manage them.
Hooks – lifecycle actions for migrations, cleanup, and testing.
OCI registries – publishing and consuming charts in modern registries.
Advanced topics – subcharts, library charts, helper templates, chart testing, signing, and provenance.

                        Helm Workflow
                              │
          ┌───────────────────┴───────────────────┐
          │                                       │
  Public/Internet Chart                   Custom/Local Chart
          │                                       │
          ▼                                       ▼

## A. Public (Internet) Charts

1. Add Helm Repository
   helm repo add <repo_name> <repo_url>

2. Update Repository Index
   helm repo update

3. Search Available Charts (Optional)
   helm search repo <chart_name>

4. Inspect Chart (Optional)
   helm show values <repo_name>/<chart_name>
   helm show chart <repo_name>/<chart_name>

5. Choose Installation Method

   Option A: Download Chart
   helm pull <repo_name>/<chart_name> --untar

   Then:
   cd <chart_name>

   Optional:
   helm dependency update

   Install:
   helm install <release_name> . \
     -f values.yaml \
     -n <namespace> \
     --create-namespace

   ------------------------------------------------

### Option B: Direct Install from Repository

   helm install <release_name> <repo_name>/<chart_name> \
     -f values.yaml \
     -n <namespace> \
     --create-namespace

6. Verify Deployment
   helm list -n <namespace>
   kubectl get pods -n <namespace>
   kubectl get svc -n <namespace>

7. Upgrade (if required)
   helm upgrade <release_name> <repo_name>/<chart_name> \
     -f values.yaml \
     -n <namespace>

8. Rollback (if required)
   helm history <release_name> -n <namespace>
   helm rollback <release_name> <revision> -n <namespace>

9. Uninstall
   helm uninstall <release_name> -n <namespace>



## B. Custom (Local) Helm Chart Flow

1. Create Chart Skeleton
   helm create <chart_name>

2. Modify Chart
   ls <chart_path>
   - templates/
   - values.yaml
   - Chart.yaml

3. Validate Chart

   Lint:
   helm lint <chart_path>

   Render Templates:
   helm template <release_name> <chart_path> 
   helm template <release_name> <chart_path> -f <values_file.yml> > <file_name>

4. Update Dependencies (if any)
   helm dependency update <chart_path>

5. Install Chart

   helm install <release_name> <chart_path> \
     -f <values_file.yml> \
     -n <namespace> \
     --create-namespace

6. Verify Deployment
   helm list -n <namespace>
   kubectl get pods -n <namespace>

7. Upgrade

   helm upgrade <release_name> <chart_path> \
     -f <new_values_file.yml> or --set image.tag="0.2.4" \
     -n <namespace>

8. Check Rollout History

   helm history <release_name> -n <namespace>

9. Rollback

   helm rollback <release_name> <revision> -n <namespace>

10. Uninstall

   helm uninstall <release_name> -n <namespace>

---

## Useful Helm Commands

Repository
-----------
helm repo list
helm repo remove <repo_name>
helm repo update

Search
------
helm search repo <chart_name>
helm search hub <chart_name>

Chart Information
-----------------
helm show values <chart>
helm show chart <chart>
helm show readme <chart>

Validation
----------
helm lint <chart>
helm template <release> <chart>

Release Management
------------------
helm list
helm history <release>
helm status <release>

Dependencies
------------
helm dependency update
helm dependency build

Package Chart
-------------
helm package <chart_path>

Cleanup
-------
helm uninstall <release> -n <namespace>

---

## FLOW
Start
  │
  ├── Is the chart from a public Helm repository?
  │
  ├── Yes
  │     │
  │     ├── helm repo add
  │     ├── helm repo update
  │     ├── helm search repo (optional)
  │     ├── helm show values (optional)
  │     ├── Download chart?
  │     │      │
  │     │      ├── Yes → helm pull --untar
  │     │      │            ├── Modify values
  │     │      │            └── helm install .
  │     │      │
  │     │      └── No → helm install repo/chart
  │     │
  │     ├── Verify deployment
  │     ├── Upgrade if needed
  │     ├── Rollback if needed
  │     └── Uninstall
  │
  └── No (Custom Chart)
        │
        ├── helm create
        ├── Modify templates
        ├── helm lint
        ├── helm template
        ├── helm dependency update
        ├── helm install
        ├── Verify deployment
        ├── Upgrade
        ├── Rollback
        └── Uninstall