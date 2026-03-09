# GitOps Setup Guide
## ArgoCD + HashiCorp Vault + Fullstack App

---

## Folder Structure

```
jenkin-argo-gitops/                         ← your Git repo root
│
├── 📁 argocd/
│   ├── root-app.yaml                       ← [COMMIT] bootstrap entry point
│   │
│   ├── 📁 apps/                            ← [COMMIT] child apps managed by root-app
│   │   ├── vault.yaml                      ← installs HashiCorp Vault
│   │   ├── argocd-vault-plugin.yaml        ← installs AVP plugin
│   │   ├── fullstack-app-prod.yaml         ← prod app (master branch)
│   │   └── fullstack-app-dev.yaml          ← dev app (dev branch)
│   │
│   └── 📁 avp/                             
│       ├── argocd-cm-plugin.yaml           ← [COMMIT] registers AVP in ArgoCD
│       └── avp-credentials.yaml            ← [DO NOT COMMIT] apply manually once
│
├── 📁 fullstack-app/                       ← [COMMIT] your Helm chart
│   ├── Chart.yaml
│   ├── values.yaml                         ← base values (no secrets)
│   ├── values-prod.yaml                    ← prod overrides + AVP placeholders
│   ├── values-dev.yaml                     ← dev overrides + AVP placeholders
│   └── 📁 templates/
│       ├── cloudflare-dns-job.yaml
│       ├── cloudflare-secret.yaml
│       ├── clusterissuer.yaml
│       ├── presync-secrets.yaml
│       ├── presync-rbac.yaml
│       └── NOTES.txt
│
├── 📁 secrets-prod/                        ← [DO NOT COMMIT] local only
│   └── secret-prod.yaml                    
│
├── vault-setup.sh                          ← [DO NOT COMMIT] run locally once
├── .gitignore                              ← ignores secrets files
└── README.md
```

---

## .gitignore

```
# Never commit these
argocd/avp/avp-credentials.yaml
secrets-prod/
secrets-dev/
vault-setup.sh
vault-init-keys.json
*.secret.yaml
```

---

## What Goes Where

| File | Commit to Git? | Why |
|---|---|---|
| `argocd/root-app.yaml` | ✅ Yes | ArgoCD needs to read it |
| `argocd/apps/*.yaml` | ✅ Yes | Managed by root-app |
| `argocd/avp/argocd-cm-plugin.yaml` | ✅ Yes | Plugin config, no secrets |
| `argocd/avp/avp-credentials.yaml` | ❌ No | Contains Vault connection info |
| `fullstack-app/**` | ✅ Yes | Helm chart, AVP placeholders only |
| `values-prod.yaml` | ✅ Yes | Has `<path:...>` placeholders, not real secrets |
| `values-dev.yaml` | ✅ Yes | Same as above |
| `secrets-prod/secret-prod.yaml` | ❌ No | Contains real secrets |
| `vault-setup.sh` | ❌ No | Contains real secret values |
| `vault-init-keys.json` | ❌ No | Vault unseal keys — highly sensitive |

---

## Run Order

### Phase 1 — One Time Setup (do this once on a fresh cluster)

```bash
# ── 0. Clone your repo ────────────────────────────────────────────────────
git clone https://github.com/seang454/jenkin-argo-gitops
cd jenkin-argo-gitops

# ── 1. Install ArgoCD into cluster ───────────────────────────────────────
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD to be ready
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=120s

# ── 2. Apply AVP credentials (NEVER commit this file) ────────────────────
kubectl apply -f argocd/avp/avp-credentials.yaml

# ── 3. Apply AVP plugin config ────────────────────────────────────────────
kubectl apply -f argocd/avp/argocd-cm-plugin.yaml

# ── 4. Bootstrap root app — ArgoCD takes over from here ──────────────────
kubectl apply -f argocd/root-app.yaml
```

### Phase 2 — Wait for Vault to Start

```bash
# Watch until vault-0 pod is Running
kubectl get pods -n vault -w

# Once Running, run Vault setup
chmod +x vault-setup.sh
./vault-setup.sh
```

### Phase 3 — Verify Everything is Running

```bash
# Check all ArgoCD apps are Synced + Healthy
kubectl get applications -n argocd

# Check prod namespace
kubectl get all -n prod

# Check dev namespace
kubectl get all -n dev

# Check DNS jobs ran successfully
kubectl get jobs -n prod
kubectl get jobs -n dev

# Check ingress has IP addresses
kubectl get ingress -n prod
kubectl get ingress -n dev
```

---

## How It All Flows

```
kubectl apply -f argocd/root-app.yaml       ← you run this ONCE
        │
        ▼
ArgoCD root-app syncs argocd/apps/
        │
        ├── apps/vault.yaml                 ← ArgoCD installs Vault
        │         │
        │         ▼
        │   ./vault-setup.sh                ← you run this ONCE
        │   stores secrets at:
        │     secret/prod/cloudflare
        │     secret/prod/database
        │     secret/prod/keycloak
        │     secret/dev/cloudflare
        │     secret/dev/database
        │     secret/dev/keycloak
        │
        ├── apps/argocd-vault-plugin.yaml   ← ArgoCD installs AVP
        │
        ├── apps/fullstack-app-prod.yaml    ← ArgoCD syncs prod
        │         │
        │         ▼
        │   AVP reads values-prod.yaml
        │   replaces <path:secret/data/prod/cloudflare#token>
        │   with real value from Vault
        │         │
        │         ▼
        │   Helm renders chart with real secrets
        │         │
        │         ▼
        │   pre-install hook → cloudflare-dns-job runs
        │   Ingress + TLS applied ✅
        │
        └── apps/fullstack-app-dev.yaml     ← same flow for dev ✅
```

---

## After Setup — How to Update Secrets

```bash
# Update a secret in Vault directly (no Git commit needed)
kubectl exec -n vault vault-0 -- vault kv put secret/prod/cloudflare \
  token="new-token" \
  zoneId="your-zone-id"

# Then trigger ArgoCD re-sync
kubectl annotate application fullstack-app-prod \
  argocd.argoproj.io/refresh=normal -n argocd
```

## After Setup — How to Deploy a New Image

```bash
# Just update the image tag in values-prod.yaml and push to Git
git add fullstack-app/values-prod.yaml
git commit -m "bump frontend image to abc1234"
git push

# ArgoCD detects the change and auto-syncs ✅
# No kubectl, no helm commands needed
```