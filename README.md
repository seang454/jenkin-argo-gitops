# jenkins + argocd
- Architecture
```bash
Developer → GitHub
              ↓
          Jenkins (build + push image)
              ↓
        Update Helm/Manifest repo
              ↓
          Argo CD (detect change)
              ↓
        Deploy to Kubernetes

```

livenessProbe:
  httpGet:
    path: /health/live
    port: 9000
  initialDelaySeconds: 60   # wait 60s before first check (keycloak is slow to start)
  periodSeconds: 30          # check every 30s
  failureThreshold: 3        # restart pod after 3 failures
```
```
- "Is the app still alive?"
Kubernetes calls GET /health/live every 30s
    ↓
200 OK  → pod is alive ✅ do nothing
    ↓
fails 3 times → pod is dead ❌ RESTART the pod


-  "Is the app ready to receive traffic?"
readinessProbe:
  httpGet:
    path: /health/ready
    port: 9000
  initialDelaySeconds: 30   # wait 30s before first check
  periodSeconds: 10          # check every 10s
  failureThreshold: 3        # remove from load balancer after 3 failures
```
```
Kubernetes calls GET /health/ready every 10s
    ↓
200 OK  → pod is ready ✅ send traffic to it
    ↓
fails 3 times → pod not ready ❌ STOP sending traffic (but don't restart)


helm install my-app ./fullstack-app \
  -f ./fullstack-app/values.yaml \
  -f ./fullstack-app/values-prod.yaml \
  --set database.initScript.keycloakPassword="MyStr0ngPass!" \
  --namespace prod \
  --create-namespace