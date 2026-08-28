# ConfigMap

```bash
kubectl create configmap adservice-config \
--from-literal=ADSERVICE_PORT="9555" \
-n google-microservice --dry-run=client -o yaml > adservice-configmap.yml

kubectl create configmap cartservice-config \
--from-literal=REDIS_ADDR="redis-cart:6379" \
-n google-microservice --dry-run=client -o yaml > cartservice-configmap.yml

$ kubectl create configmap checkoutservice-config \
--from-literal=CHECKOUTSERVICE_PORT="5050" \
--from-literal=PRODUCT_CATALOG_SERVICE_ADDR="productcatalogservice:3550" \
--from-literal=SHIPPING_SERVICE_ADDR="shippingservice:50051" \
--from-literal=PAYMENT_SERVICE_ADDR="paymentservice:50051" \
--from-literal=EMAIL_SERVICE_ADDR="emailservice:5000" \
--from-literal=CURRENCY_SERVICE_ADDR="currencyservice:7000" \
--from-literal=CART_SERVICE_ADDR="cartservice:7070" \
-n google-microservice --dry-run=client -o yaml > checkoutservice-configmap.yml

kubectl create configmap currencyservice-config \
--from-literal=CURRENCYSERVICE_PORT="7000" \
--from-literal=DISABLE_PROFILER="1" \
-n google-microservice --dry-run=client -o yaml > currencyservice-configmap.yml

kubectl create configmap emailservice-config \
--from-literal=EMAILSERVICE_PORT="8080" \
--from-literal=DISABLE_PROFILER="1" \
-n google-microservice --dry-run=client -o yaml > emailservice-configmap.yml

kubectl create configmap frontend-config \
--from-literal=FRONTEND_PORT="8080" \
--from-literal=PRODUCT_CATALOG_SERVICE_ADDR="productcatalogservice:3550" \
--from-literal=CURRENCY_SERVICE_ADDR="currencyservice:7000" \
--from-literal=CART_SERVICE_ADDR="cartservice:7070" \
--from-literal=RECOMMENDATION_SERVICE_ADDR="recommendationservice:8080" \
--from-literal=SHIPPING_SERVICE_ADDR="shippingservice:50051" \
--from-literal=CHECKOUT_SERVICE_ADDR="checkoutservice:5050" \
--from-literal=AD_SERVICE_ADDR="adservice:9555" \
--from-literal=SHOPPING_ASSISTANT_SERVICE_ADDR="shoppingassistantservice:80" \
--from-literal=ENABLE_PROFILER="0" \
-n google-microservice --dry-run=client -o yaml > frontend-configmap.yml

kubectl create configmap paymentservice-config \
--from-literal=PAYMENTSERVICE_PORT="50051" \
--from-literal=DISABLE_PROFILER="1" \
-n google-microservice --dry-run=client -o yaml > paymentservice-configmap.yml

kubectl create configmap productcatalogservice-config \
--from-literal=PRODUCTCATALOGSERVICE_PORT="3550" \
--from-literal=DISABLE_PROFILER="1" \
-n google-microservice --dry-run=client -o yaml > productcatalogservice-configmap.yml

kubectl create configmap recommendationservice-config \
--from-literal=RECOMMENDATIONSERVICE_PORT="8080" \
--from-literal=PRODUCT_CATALOG_SERVICE_ADDR="productcatalogservice:3550" \
--from-literal=DISABLE_PROFILER="1" \
-n google-microservice --dry-run=client -o yaml > recommendationservice-configmap.yml

kubectl create configmap shippingservice-config \
--from-literal=SHIPPINGSERVICE_PORT="50051" \
--from-literal=DISABLE_PROFILER="1" \
-n google-microservice --dry-run=client -o yaml > shippingservice-configmap.yml
```
