# ServiceAccount

```bash
kubectl create pdb frontend-pdb --selector=app=frontend --min-available=1 --dry-run=client -o yaml > frontend-pdb.yml
kubectl create pdb checkoutservice-pdb --selector=app=checkoutservice --min-available=1 --dry-run=client -o yaml > checkoutservice-pdb.yml
kubectl create pdb productcatalogservice-pdb --selector=app=productcatalogservice --min-available=1 --dry-run=client -o yaml > productcatalogservice-pdb.yml
kubectl create pdb recommendationservice-pdb --selector=app=recommendationservice --min-available=1 --dry-run=client -o yaml > recommendationservice-pdb.yml
kubectl create pdb currencyservice-pdb --selector=app=currencyservice --min-available=1 --dry-run=client -o yaml > currencyservice-pdb.yml
kubectl create pdb cartservice-pdb --selector=app=cartservice --min-available=1 --dry-run=client -o yaml > cartservice-pdb.yml
kubectl create pdb adservice-pdb --selector=app=adservice --min-available=1 --dry-run=client -o yaml > adservice-pdb.yml
kubectl create pdb shippingservice-pdb --selector=app=shippingservice --min-available=1 --dry-run=client -o yaml > shippingservice-pdb.yml
```
