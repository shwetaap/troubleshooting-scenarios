# Scenario 02 — Alert Storm

You are an SRE investigating a cascade of alerts in the `payments` namespace on an OpenShift cluster. Multiple services are degraded and several alerts are firing simultaneously. Your goal is to identify the root cause and restore service health.

## Architecture

Five microservices in the `payments` namespace:

```
                    ┌── checkout-service ──── (verifies payments)
                    │
payments-api ───────┼── order-processor ───── (processes orders)
                    │
                    ├── refund-service ────── (validates refunds)
                    │
                    └── notification-service ─ (sends notifications)
```

All four downstream services depend on `payments-api` via HTTP. There is no database.

### Services

| Service | Port | Role |
|---------|------|------|
| **payments-api** | 8080 | Processes payments, serves `/api/v1/process-payment`. Loads config from a mounted ConfigMap. |
| **checkout-service** | 8080 | Polls payments-api every 2s. Degrades after 3 consecutive failures. |
| **order-processor** | 8080 | Generates orders every 1s, calls payments-api. Queues failed orders for retry. |
| **refund-service** | 8080 | Validates refund eligibility via payments-api every 2s. Queues pending refunds. |
| **notification-service** | 8080 | Polls payments-api every 3s to deliver payment notifications. |

### Prometheus Monitoring

Each service exposes `/metrics` on port 8080 and has a ServiceMonitor (scrape interval 15s).

## Available Alerts

| Alert | Service | Severity | Condition |
|-------|---------|----------|-----------|
| PaymentsAPIMemoryHigh | payments-api | warning | Container memory > 80% of limit |
| PaymentProcessingLatencyHigh | payments-api | warning | p99 latency > 1s |
| CheckoutHighErrorRate | checkout-service | critical | payments-api unreachable for 1m |
| OrderProcessingBacklog | order-processor | warning | Queue depth > 30 |
| OrderProcessorMemoryHigh | order-processor | warning | Container memory > 80% of limit |
| RefundProcessingFailureRate | refund-service | warning | Failure rate > 50% |
| RefundBacklogHigh | refund-service | warning | Pending refunds > 20 |
| NotificationDeliveryStalled | notification-service | warning | No deliveries for 2 minutes |
| KubePodCrashLooping | any | warning | Pod in CrashLoopBackOff |
| KubePodNotReady | any | warning | Pod not ready for 1 minute |

## Investigation Tips

- Start by checking which pods are unhealthy: `oc get pods -n payments`
- Check firing alerts: query the Thanos API or use `oc get prometheusrule -n payments -o yaml`
- Look at pod events: `oc describe pod <pod> -n payments`
- Check logs: `oc logs deployment/<service> -n payments`
- Examine the ConfigMap: `oc get configmap payments-api-config -n payments -o yaml`
- Check resource usage: `oc adm top pods -n payments`

## Key Metrics

- `payments_cache_entries` / `payments_cache_bytes` — payments-api cache size
- `checkout_dependency_up{service="payments-api"}` — checkout-service health check
- `orders_queue_depth` / `orders_queue_memory_bytes` — order-processor backlog
- `refund_pending_count` — refund-service pending queue
- `notification_last_delivery_timestamp` — notification-service staleness
