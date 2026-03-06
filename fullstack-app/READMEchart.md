# Keycloak Helm Chart

A production-ready Helm chart for deploying [Keycloak](https://www.keycloak.org/) — an open-source Identity and Access Management solution.

## Prerequisites

- Kubernetes 1.23+
- Helm 3.8+
- A PostgreSQL (or other supported) database

## Chart Structure

```
keycloak/
├── Chart.yaml
├── values.yaml
├── templates/
│   ├── _helpers.tpl
│   ├── NOTES.txt
│   ├── configmap.yaml
│   ├── deployment.yaml
│   ├── hpa.yaml
│   ├── ingress.yaml
│   ├── networkpolicy.yaml
│   ├── pdb.yaml
│   ├── pvc.yaml
│   ├── secret.yaml
│   ├── service.yaml
│   └── servicemonitor.yaml
└── charts/
```

## Quick Start

```bash
# Install with defaults (uses H2 embedded DB - dev only)
helm install keycloak ./keycloak \
  --set database.vendor=dev-file

# Install with external PostgreSQL
helm install keycloak ./keycloak \
  --set database.host=my-postgres \
  --set database.password=secret \
  --set keycloak.auth.adminPassword=admin-secret

# Install with production values
helm install keycloak ./keycloak -f values-production.yaml
```

## Configuration

### Admin Credentials

| Parameter | Description | Default |
|-----------|-------------|---------|
| `keycloak.auth.adminUser` | Admin username | `admin` |
| `keycloak.auth.adminPassword` | Admin password (use existingSecret in prod) | `changeme` |
| `keycloak.auth.existingSecret` | Secret name for admin password | `""` |

### Database

| Parameter | Description | Default |
|-----------|-------------|---------|
| `database.vendor` | DB type: postgres/mysql/mariadb/dev-file | `postgres` |
| `database.host` | Database host | `""` |
| `database.port` | Database port | `5432` |
| `database.name` | Database name | `keycloak` |
| `database.username` | Database user | `keycloak` |
| `database.password` | Database password | `changeme` |
| `database.existingSecret` | Existing secret for DB password | `""` |

### Ingress

| Parameter | Description | Default |
|-----------|-------------|---------|
| `ingress.enabled` | Enable ingress | `false` |
| `ingress.className` | IngressClass name | `""` |
| `ingress.hosts` | Ingress hosts | see values.yaml |
| `ingress.tls` | TLS configuration | `[]` |

## Production Checklist

- [ ] Use `existingSecret` for admin and database passwords
- [ ] Set `keycloak.production=true`
- [ ] Configure external PostgreSQL (`database.vendor=postgres`)
- [ ] Enable TLS via Ingress
- [ ] Set `replicaCount >= 3` for HA
- [ ] Enable `podDisruptionBudget`
- [ ] Configure pod anti-affinity
- [ ] Enable autoscaling
- [ ] Set proper resource limits

## High Availability

For HA deployments, Keycloak uses Infinispan for distributed caching. This chart supports `jdbc-ping` for cluster discovery (recommended when using PostgreSQL).

```yaml
cache:
  stack: jdbc-ping
replicaCount: 3
```

## Metrics

Enable Prometheus metrics:

```yaml
metrics:
  enabled: true
  serviceMonitor:
    enabled: true  # Requires Prometheus Operator
```

## Upgrading

```bash
helm upgrade keycloak ./keycloak -f values-production.yaml
```


# we secrete

```bash
Dev:
values.yaml
database.auth.existingSecret = ""  (empty)
       ↓
database.createSecret = true
       ↓
secret.yaml template RUNS
       ↓
Secret auto-created from password: "changeme" ✅

```

```bash
production
values-prod.yaml
database.auth.existingSecret = "postgres-prod-secret"  (not empty)
       ↓
database.createSecret = false
       ↓
secret.yaml template SKIPPED
       ↓
No secret created by Helm ✅
You must create it manually before deploying

```

