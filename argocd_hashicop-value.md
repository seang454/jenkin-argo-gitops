# GitOps Setup Guide
## ArgoCD + HashiCorp Vault + Fullstack App

---

## Folder Structure

```
jenkin-argo-gitops/                              ← your Git repo root
│
├── .gitignore                                   ← [COMMIT] ignores secret files
│
├── 📁 argocd/
│   ├── root-app.yaml                            ← [COMMIT] bootstrap entry point
│   │
│   ├── 📁 apps/                                 ← [COMMIT] child apps managed by root-app
│   │   ├── vault.yaml                           ← installs HashiCorp Vault
│   │   ├── argocd-vault-plugin.yaml             ← installs AVP plugin
│   │   ├── fullstack-app-prod.yaml              ← prod app (master branch)
│   │   └── fullstack-app-dev.yaml               ← dev app (dev branch)
│   │
│   └── 📁 avp/
│       ├── argocd-cm-plugin.yaml                ← [COMMIT] registers AVP in ArgoCD
│       └── avp-credentials.yaml                 ← [DO NOT COMMIT] apply manually once
│
├── 📁 fullstack-app/                            ← [COMMIT] your Helm chart
│   ├── Chart.yaml
│   ├── values.yaml                              ← base values (empty strings, no secrets)
│   ├── values-prod.yaml                         ← prod overrides + AVP placeholders
│   ├── values-dev.yaml                          ← dev overrides + AVP placeholders
│   ├── 📁 templates/
│   │   ├── cloudflare-dns-job.yaml              ← pre-install hook: creates DNS records
│   │   ├── cloudflare-secret.yaml               ← pre-install hook: creates CF secret
│   │   ├── clusterissuer.yaml                   ← pre-install hook: cert-manager issuer
│   │   ├── HELM_HOOK.md
│   │   └── NOTES.txt
│   └── 📁 charts/
│       ├── admin/
│       ├── backend/
│       ├── frontend/
│       ├── database/
│       │   └── templates/
│       │       └── secret.yaml                  ← creates postgres secret from AVP values
│       └── keycloak/
│           └── templates/
│               └── secret.yaml                  ← creates keycloak admin + db secrets
│
├── vault-setup.sh                               ← [DO NOT COMMIT] run locally once
└── README.md
```

---

## .gitignore

```
# Secrets — never commit
argocd/avp/avp-credentials.yaml
secrets-prod/
secrets-dev/
vault-setup.sh
vault-init-keys.json
*.secret.yaml
*-secret.yaml

# OS / Editor
.DS_Store
.idea/
.vscode/

# Helm
fullstack-app/charts/*.tgz
fullstack-app/Chart.lock
```

---

## What Goes Where

| File | Commit to Git? | Why |
|---|---|---|
| `argocd/root-app.yaml` | ✅ Yes | ArgoCD bootstrap entry point |
| `argocd/apps/*.yaml` | ✅ Yes | Child apps managed by root-app |
| `argocd/avp/argocd-cm-plugin.yaml` | ✅ Yes | Plugin config, no secrets inside |
| `argocd/avp/avp-credentials.yaml` | ❌ No | Vault connection credentials |
| `fullstack-app/**` | ✅ Yes | Helm chart with AVP placeholders only |
| `values.yaml` | ✅ Yes | Empty strings for all secrets |
| `values-prod.yaml` | ✅ Yes | `<path:...>` placeholders, no real secrets |
| `values-dev.yaml` | ✅ Yes | `<path:...>` placeholders, no real secrets |
| `vault-setup.sh` | ❌ No | Contains real secret values |
| `vault-init-keys.json` | ❌ No | Vault unseal keys — highly sensitive |

---

## How Secrets Flow

```
vault-setup.sh (local)          values-prod.yaml (Git)          Kubernetes Cluster
──────────────────────          ──────────────────────          ──────────────────
vault kv put                    AVP placeholder                 Real value injected
secret/prod/cloudflare   ──►    <path:secret/data/         ──►  token: "abc123"
  token="abc123"                prod/cloudflare#token>
  zoneId="xyz456"               <path:secret/data/              zoneId: "xyz456"
                                prod/cloudflare#zoneId>
```

### Vault Paths → values files mapping

| Vault Path | Keys | Used in |
|---|---|---|
| `secret/prod/cloudflare` | `token`, `zoneId` | `cloudflare.apiToken`, `cloudflare.zoneId` |
| `secret/prod/database` | `username`, `password`, `database` | `database.auth.*` |
| `secret/prod/keycloak` | `admin-username`, `admin-password`, `db-username`, `db-password` | `keycloak.keycloak.auth.*`, `keycloak.database.*`, `database.initScript.*` |
| `secret/prod/certmanager` | `email` | `certManager.email`, `global.certManager.email` |
| `secret/dev/cloudflare` | `token`, `zoneId` | same as prod, dev env |
| `secret/dev/database` | `username`, `password`, `database` | same as prod, dev env |
| `secret/dev/keycloak` | `admin-username`, `admin-password`, `db-username`, `db-password` | same as prod, dev env |
| `secret/dev/certmanager` | `email` | same as prod, dev env |

---

## AVP Placeholder Syntax

```
<path:secret/data/prod/cloudflare#token>
  │         │              │          │
  │         │              │          └─ key name inside the secret
  │         │              └─ your path in Vault
  │         └─ KV v2 always requires /data/ between mount and path
  └─ tells AVP to fetch from Vault
```

> **Why `/data/`?** Vault KV v2 stores secrets internally under `/data/`.
> You write with `vault kv put secret/prod/...` but AVP must read from `secret/data/prod/...`

---

## Helm Hook Execution Order

```
helm install (via ArgoCD sync)
      │
      ├── pre-install (weight  0) → cloudflare-secret.yaml   ← CF credentials ready
      ├── pre-install (weight  5) → cloudflare-dns-job.yaml  ← DNS records created
      ├── pre-install (weight 10) → clusterissuer.yaml       ← cert-manager ready
      │
      └── install → subcharts deployed:
                      database     ← secret.yaml creates postgres secret from AVP values
                      keycloak     ← secret.yaml creates admin + db secrets from AVP values
                      backend      ← Ingress applied (DNS already exists ✅)
                      frontend     ← Ingress applied (DNS already exists ✅)
                      admin        ← Ingress applied (DNS already exists ✅)
```

---

## Run Order

### Phase 1 — One Time Setup (fresh cluster)

```bash
# 0. Clone repo
git clone https://github.com/seang454/jenkin-argo-gitops
cd jenkin-argo-gitops

# 1. Install ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait until ready
kubectl wait --for=condition=available \
  deployment/argocd-server -n argocd --timeout=180s

# 2. Apply AVP plugin config (safe — no secrets)
kubectl apply -f argocd/avp/argocd-cm-plugin.yaml

# 3. Apply AVP credentials (NEVER commit this file)
kubectl apply -f argocd/avp/avp-credentials.yaml

# 4. Bootstrap root app — ArgoCD takes over from here
kubectl apply -f argocd/root-app.yaml
```

### Phase 2 — Setup Vault (after Vault pod starts)

```bash
# Watch until vault-0 is Running
kubectl get pods -n vault -w
# NAME      READY   STATUS
# vault-0   1/1     Running   ← ready ✅

# Fill in variables at top of script then run
nano vault-setup.sh
chmod +x vault-setup.sh
./vault-setup.sh

# vault-setup.sh does:
#   - vault operator init     → creates vault-init-keys.json
#   - vault operator unseal   → unseals Vault (3 of 5 keys)
#   - vault secrets enable    → enables KV v2
#   - vault kv put            → stores all prod + dev secrets
#   - vault auth enable       → enables Kubernetes auth
#   - vault policy write      → grants ArgoCD read access
#   - vault write role        → binds argocd-repo-server ServiceAccount
```

### Phase 3 — Verify Everything

```bash
# All apps should show Synced + Healthy
kubectl get applications -n argocd
# NAME                    SYNC     HEALTH
# root-app                Synced   Healthy
# vault                   Synced   Healthy
# argocd-vault-plugin     Synced   Healthy
# fullstack-app-prod      Synced   Healthy
# fullstack-app-dev       Synced   Healthy

# Check prod
kubectl get all     -n prod
kubectl get ingress -n prod
kubectl get jobs    -n prod

# Check dev
kubectl get all     -n dev
kubectl get ingress -n dev
```

---

## How It All Flows

```
kubectl apply -f argocd/root-app.yaml        ← you run this ONCE
        │
        ▼
ArgoCD syncs argocd/apps/
        │
        ├── vault.yaml                        ← Vault installed in vault namespace
        │         │
        │         ▼
        │   ./vault-setup.sh                  ← you run this ONCE
        │   Stores secrets:
        │     secret/prod/cloudflare
        │     secret/prod/database
        │     secret/prod/keycloak
        │     secret/prod/certmanager
        │     secret/dev/cloudflare
        │     secret/dev/database
        │     secret/dev/keycloak
        │     secret/dev/certmanager
        │
        ├── argocd-vault-plugin.yaml           ← AVP installed
        │
        ├── fullstack-app-prod.yaml            ← prod sync starts
        │         │
        │         ▼
        │   AVP fetches from Vault
        │   replaces all <path:...> placeholders
        │   with real values
        │         │
        │         ▼
        │   Helm renders chart
        │         │
        │         ▼
        │   pre-install hooks run (weight 0 → 5 → 10)
        │   DNS records created ✅
        │   cert-manager ready ✅
        │         │
        │         ▼
        │   Subcharts deployed ✅
        │
        └── fullstack-app-dev.yaml             ← same flow for dev ✅
```

---

## After Setup — Daily Operations

### Deploy a new image
```bash
# Update image tag in values-prod.yaml
git add fullstack-app/values-prod.yaml
git commit -m "bump frontend image to abc1234"
git push origin master
# ArgoCD auto-syncs within 3 minutes ✅
```

### Update a secret in Vault
```bash
kubectl exec -n vault vault-0 -- \
  vault kv put secret/prod/database \
    username="appuser" \
    password="NewPassword!" \
    database="appdb_prod"

# Trigger ArgoCD re-sync to pick up new values
kubectl annotate application fullstack-app-prod \
  argocd.argoproj.io/refresh=normal -n argocd
```

### Force re-sync
```bash
kubectl annotate application fullstack-app-prod \
  argocd.argoproj.io/refresh=normal -n argocd
```

### Access ArgoCD UI
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Open: https://localhost:8080
# User: admin
# Pass:
kubectl get secret argocd-initial-admin-secret \
  -n argocd -o jsonpath="{.data.password}" | base64 -d
```

### Access Vault UI
```bash
kubectl port-forward svc/vault -n vault 8200:8200
# Open: http://localhost:8200
# Token: from vault-init-keys.json → root_token
```