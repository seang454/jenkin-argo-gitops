# fullstack-app Helm Chart

A parent Helm chart that composes three independent subcharts:

| Subchart   | Path                        | Description                    |
|------------|-----------------------------|--------------------------------|
| `frontend` | `charts/frontend`           | React / static web frontend    |
| `backend`  | `charts/backend`            | Node.js / API backend          |
| `database` | `charts/database`           | PostgreSQL database            |

---

## Directory Structure

```
fullstack-app/
├── Chart.yaml               # Parent chart + dependency list
├── values.yaml              # Default values for all subcharts
├── values-dev.yaml          # Dev environment overrides
├── values-prod.yaml         # Production environment overrides
├── templates/
│   └── NOTES.txt
└── charts/
    ├── frontend/
    │   ├── Chart.yaml
    │   └── templates/
    │       ├── _helpers.tpl
    │       ├── deployment.yaml
    │       ├── service.yaml
    │       ├── ingress.yaml
    │       └── hpa.yaml
    ├── backend/
    │   ├── Chart.yaml
    │   └── templates/
    │       ├── _helpers.tpl
    │       ├── deployment.yaml
    │       ├── service.yaml
    │       ├── ingress.yaml
    │       └── hpa.yaml
    └── database/
        ├── Chart.yaml
        └── templates/
            ├── _helpers.tpl
            ├── deployment.yaml
            ├── service.yaml
            ├── secret.yaml
            └── pvc.yaml
```

---

## Usage

### Build dependencies
- It reads your Chart.yaml dependencies and packages all subcharts into the charts/ folder so Helm can use them.
```bash
helm dependency build ./fullstack-app

Before running it:
fullstack-app/
├── Chart.yaml          ← lists dependencies
├── charts/             ← EMPTY or missing subchart packages
│   ├── frontend/
│   ├── backend/
│   ├── database/
│   └── keycloak/

After running it:
fullstack-app/
├── Chart.yaml
├── Chart.lock          ← created automatically (locks versions)
├── charts/
│   ├── frontend-1.0.0.tgz    ← packaged ✅
│   ├── backend-1.0.0.tgz     ← packaged ✅
│   ├── database-1.0.0.tgz    ← packaged ✅
│   └── keycloak-1.0.0.tgz    ← packaged ✅
```

### Install (dev)
```bash
helm install my-app ./fullstack-app \
  -f ./fullstack-app/values-dev.yaml \
  --namespace dev --create-namespace
```

### Install (prod)
```bash
helm install my-app ./fullstack-app \
  -f ./fullstack-app/values-prod.yaml \
  --namespace prod --create-namespace
```

### Upgrade
```bash
helm upgrade my-app ./fullstack-app \
  -f ./fullstack-app/values-prod.yaml \
  --namespace prod
```

### Lint
```bash
helm lint ./fullstack-app -f ./fullstack-app/values-dev.yaml
```

### Dry run / template preview
```bash
helm template my-app ./fullstack-app \
  -f ./fullstack-app/values-dev.yaml
```

---

## Enabling / Disabling Subcharts

Each subchart can be toggled independently in `values.yaml`:

```yaml
frontend:
  enabled: true

backend:
  enabled: true

database:
  enabled: false   # Use an external DB instead
```

---

## Database Credentials

By default the database secret is created from `values.yaml`.  
In production, supply a pre-existing secret:

```yaml
database:
  auth:
    existingSecret: "my-postgres-secret"
```

The secret must contain keys: `postgres-username`, `postgres-password`, `postgres-database`.

---

## Global Values

`global` values are automatically passed down to all subcharts:

```yaml
global:
  database:
    host: "my-app-database"
    port: 5432
    name: "appdb"
  imagePullSecrets:
    - name: my-registry-secret
  storageClass: "premium-rwo"
```
