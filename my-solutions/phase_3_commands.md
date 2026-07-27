### Task 3.1 — Ingress and TLS

```bash
      # cli for each services deployment
      kubectl create deploy users-api --image=hashicorp/http-echo --replicas=3 --dry-run=client -o yaml > users_deploy.yml
      kubectl create deploy orders-api --image=hashicorp/http-echo --replicas=3 --dry-run=client -o yaml > orders_deploy.yml
      kubectl create deploy main-api --image=hashicorp/http-echo --replicas=3 --dry-run=client -o yaml > main_deploy.yml
      
      # Edit to add args in them for response text
      
      kubectl apply -f .
```

```bash
      # Create Individual Services
      kubectl expose deployment users-api --name=users-api-svc --port=80 --target-port=5678
      kubectl expose deployment orders-api --name=orders-api-svc --port=80 --target-port=5678
      kubectl expose deployment main-api --name=main-api-svc --port=80 --target-port=5678

      # Creating Ingress Rules
      kubectl create ingress app-ingress --class=nginx --rule="/api/users=users-api-svc:80" --rule="/api/orders=orders-api-svc:80" --rule="/=main-api-svc:80" --dry-run=client -o yaml > api-ingress.yml
      # It will work without port-forward as port 80 as Port 80 is present in extraPortMappings.containerPort in kind-2node.yml
```

```bash
      main -> http://localhost/
      users -> http://localhost/api/users
      orders -> http://localhost/api/orders
```

### Task 3.2 — RBAC for Teams

```bash
      # create ServiceAccounts
      ## kubectl create sa <serviceAccount-name> -n <namespace>
      kubectl create sa developer -n team-alpha
      kubectl create sa ci-cd-pipeline -n team-alpha

      # Create Roles
      ## kubectl create role <role-name> --verb=<verbs-to-add / "*"> --resource=<resources-name.api_groups-name> --dry-run=client -o yaml > pod-reader.yml
      kubectl create role pod-reader --verb=get,list,watch --resource=pods --dry-run=client -o yaml > pod-reader.yml
      # Update the manifest for pods/log too as we can't create different rules with different verbs in single CLI command
      kubectl create role pod-creator --verb=create,update --resource=deployments.apps,services --dry-run=client -o yaml > pod-creator.yml
      # No need to update manifest cli is enough as verbs are same for boths
      
      # Create Role-Bindings
      ## kubectl create rolebinding <role_binding-name> --role=<role-name> --serviceaccount=<namespace-name:serviceAccount-name>
      kubectl create rolebinding dev-binding --role=pod-reader --serviceaccount=team-alpha:developer
      kubectl create rolebinding cicd-binding --role=pod-creator --serviceaccount=team-alpha:ci-cd-pipeline
```

```bash
      kubectl auth can-i get pods --as=system:serviceaccount:team-alpha:developer -n team-alpha # yes
      kubectl auth can-i get pods --as=system:serviceaccount:team-alpha:ci-cd-pipeline -n team-alpha # no
      kubectl auth can-i create deployments --as=system:serviceaccount:team-alpha:developer -n team-alpha # no
      kubectl auth can-i create deployments --as=system:serviceaccount:team-alpha:ci-cd-pipeline -n team-alpha # yes
```

```bash
      kubectl delete deploy main-api --as=system:serviceaccount:team-alpha:developer -n team-alpha
      # Output
      Error from server (Forbidden): deployments.apps "main-api" is forbidden: User "system:serviceaccount:team-alpha:developer" cannot delete resource "deployments" in API group "apps" in the namespace "team-alpha"
```

### Task 3.3 — Persistent Storage

### Task 3.4 — Horizontal Pod Autoscaler

### Task 3.5 — Build a Helm Chart from Scratch