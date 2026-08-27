# HPA — Skipped Services

## redis-cart
Stateful workload. Horizontal scaling Redis requires Redis Cluster mode (data sharding across nodes).
Adding more replicas without clustering causes split-brain — each pod gets its own in-memory state,
so cart data becomes inconsistent across replicas.

## paymentservice
In production, payment processors (Stripe, PayPal, etc.) enforce API rate limits per account.
Scaling horizontally multiplies concurrent requests to the provider, risking HTTP 429s and failed transactions.
Scaling strategy here is vertical (larger pod) or queue-based, not horizontal.

## emailservice
Email providers (SendGrid, SES, etc.) apply per-account sending rate limits.
Multiple replicas processing the same email queue can cause duplicate sends.
Requires a message-deduplication layer (e.g. SQS FIFO) before HPA makes sense.

## loadgenerator
Test/load generation tool — not a service that receives traffic.
Liveness/readiness probes and autoscaling are not applicable.
Replica count is intentionally fixed at 1.
