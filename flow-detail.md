# Project Structure

## `jenkin-argo-gitops/` — Git repo root

- `.gitignore` ✅ COMMIT
  - Prevents secrets from being pushed to Git
  - Blocks: `avp-credentials.yaml`, `vault-setup.sh`, `vault-init-keys.json`, `secrets-prod/`

---

- `vault-setup.sh` ❌ DO NOT COMMIT — run locally once
  - Fill in variables at the top, then run after Vault pod starts
  - Initializes and unseals Vault
  - Stores all prod + dev secrets into Vault:
    - `secret/prod/cloudflare` → token, zoneId
    - `secret/prod/database` → username, password, database
    - `secret/prod/keycloak` → admin-username, admin-password, db-username, db-password
    - `secret/prod/certmanager` → email
    - `secret/dev/*` → same structure as prod
  - Enables Kubernetes auth so ArgoCD can read from Vault

---

- `README.md` ✅ COMMIT
  - Project overview and quick start guide

---

## `argocd/` ✅ COMMIT

- `root-app.yaml` ✅ COMMIT — **THE ONLY FILE YOU APPLY MANUALLY**
  - Tells ArgoCD: watch the `argocd/apps/` folder
  - Once applied, ArgoCD manages everything else automatically

### `argocd/apps/` ✅ COMMIT
> ArgoCD reads this folder automatically because `root-app.yaml` points here

- `vault.yaml`
  - Installs HashiCorp Vault into the `vault` namespace
  - Source: Helm chart from `helm.releases.hashicorp.com`
  - Purpose: stores all secrets (tokens, passwords, credentials)

- `argocd-vault-plugin.yaml`
  - Installs AVP (ArgoCD Vault Plugin)
  - Purpose: reads `<path:...>` placeholders in `values-prod.yaml` / `values-dev.yaml`
  - Replaces them with real values fetched from Vault at sync time

- `fullstack-app-prod.yaml`
  - ArgoCD Application for **PROD** environment
  - Branch: `master`
  - Namespace: `prod`
  - Values: `values.yaml` + `values-prod.yaml`
  - Plugin: `argocd-vault-plugin-helm`

- `fullstack-app-dev.yaml`
  - ArgoCD Application for **DEV** environment
  - Branch: `dev`
  - Namespace: `dev`
  - Values: `values.yaml` + `values-dev.yaml`
  - Plugin: `argocd-vault-plugin-helm`

### `argocd/avp/`

- `argocd-cm-plugin.yaml` ✅ COMMIT
  - Registers AVP as a plugin inside ArgoCD
  - Patches the `argocd-cm` ConfigMap
  - Tells ArgoCD how to run: `helm template | avp generate`
  - No secrets inside — safe to commit

- `avp-credentials.yaml` ❌ DO NOT COMMIT — apply once with kubectl
  - Contains: `VAULT_ADDR`, `AVP_AUTH_TYPE`, `AVP_K8S_ROLE`
  - Tells AVP where Vault is and how to authenticate
  - Never goes to Git — stays on your machine only

---

## `fullstack-app/` ✅ COMMIT — Helm parent chart

- `Chart.yaml`
  - Defines chart name, version, and subchart dependencies
  - Lists: `database`, `keycloak`, `backend`, `frontend`, `admin`
  - Controls subchart install order via dependencies

- `values.yaml` ✅ COMMIT
  - Base values shared by ALL environments
  - All secret fields are **empty strings** `""`
  - No AVP placeholders here
  - Safe to commit — contains no sensitive data

- `values-prod.yaml` ✅ COMMIT
  - PROD overrides layered on top of `values.yaml`
  - All passwords and tokens use AVP placeholders:
    - e.g. `<path:secret/data/prod/cloudflare#token>`
  - AVP replaces these at sync time with real values from Vault
  - Safe to commit — placeholders are not real secrets

- `values-dev.yaml` ✅ COMMIT
  - DEV overrides layered on top of `values.yaml`
  - Same AVP placeholder pattern as `values-prod.yaml`
  - Reads from `secret/dev/*` paths in Vault
  - Lower replicas, staging cert issuer, debug logging enabled

### `fullstack-app/templates/` ✅ COMMIT
> Root chart templates — run before subcharts are deployed

- `cloudflare-secret.yaml` — **Helm pre-install hook (weight: 0) — runs FIRST**
  - Creates Kubernetes Secret: `cloudflare-api-secret`
  - Contains: `token` + `zoneId` (filled by AVP from Vault)
  - Used by: `cloudflare-dns-job` and `clusterissuer`

- `cloudflare-dns-job.yaml` — **Helm pre-install hook (weight: 5) — runs SECOND**
  - Kubernetes Job that calls the Cloudflare API
  - Creates or updates A records for all subdomains:
    - `frontend.seang.shop` → `34.22.93.174`
    - `admin.seang.shop` → `34.22.93.174`
    - `backend.seang.shop` → `34.22.93.174`
    - `keycloak.seang.shop` → `34.22.93.174`
  - Waits for DNS propagation before continuing
  - Ensures DNS exists **before** Ingress resources are applied

- `clusterissuer.yaml` — **Helm pre-install hook (weight: 10) — runs THIRD**
  - Creates cert-manager `ClusterIssuer` resource
  - Uses Cloudflare DNS01 challenge for TLS certificate issuance
  - Runs after DNS exists (weight 10 > weight 5)
  - Enables automatic HTTPS for all Ingresses

- `HELM_HOOK.md`
  - Documentation explaining hook weights and execution order

- `NOTES.txt`
  - Printed after `helm install` / `helm upgrade`
  - Shows application URLs and useful kubectl commands

### `fullstack-app/charts/` ✅ COMMIT
> Subcharts — each is an independent Helm chart

- **`admin/`** — Admin Next.js frontend
  - `deployment.yaml` — runs `seang454/jenkins-admin-nextjs`, waits for backend via initContainer
  - `service.yaml` — ClusterIP on port 80
  - `ingress.yaml` — host: `admin.seang.shop`
  - `hpa.yaml` — auto-scales 2–10 pods at 70% CPU
  - `_helpers.tpl` — shared template functions

- **`backend/`** — Spring Boot API
  - `deployment.yaml` — runs `seang454/jenkins-itp-spring`, waits for database + keycloak via initContainers
  - `service.yaml` — ClusterIP on port 8080
  - `ingress.yaml` — host: `backend.seang.shop/api`
  - `hpa.yaml` — auto-scales 2–10 pods at 70% CPU
  - `_helpers.tpl`

- **`frontend/`** — User-facing Next.js frontend
  - `deployment.yaml` — runs `seang454/jenkins-itp-nextjs`, waits for backend via initContainer
  - `service.yaml` — ClusterIP on port 80
  - `ingress.yaml` — host: `frontend.seang.shop`
  - `hpa.yaml` — auto-scales 2–10 pods at 70% CPU
  - `_helpers.tpl`

- **`database/`** — PostgreSQL
  - `deployment.yaml` — runs `postgres:15-alpine`
  - `service.yaml` — ClusterIP on port 5432
  - `secret.yaml` — creates postgres Secret from AVP-injected values
    - Keys: `postgres-username`, `postgres-password`, `postgres-database`
    - Only renders when `auth.existingSecret` is empty
  - `configmap.yaml` — init SQL script: creates keycloak database and user
  - `pvc.yaml` — PersistentVolumeClaim for postgres data storage
  - `_helpers.tpl`

- **`keycloak/`** — Keycloak identity provider
  - `values.yaml` — keycloak-specific default values
  - `deployment.yaml` — runs `quay.io/keycloak/keycloak:26.5.5`, waits for database via initContainer
  - `service.yaml` — ClusterIP on port 80, management port on 9000
  - `ingress.yaml` — host: `keycloak.seang.shop` (prod only)
  - `secret.yaml` — creates **two** secrets from AVP-injected values:
    - `keycloak-admin-secret` → `admin-password`
    - `keycloak-db-secret` → `db-password`
    - Only renders when `existingSecret` is empty
  - `configmap.yaml` — Keycloak server configuration
  - `hpa.yaml` — auto-scaling (disabled by default)
  - `pvc.yaml` — PersistentVolumeClaim for Keycloak data
  - `pdb.yaml` — PodDisruptionBudget (keeps minimum pods available)
  - `networkpolicy.yaml` — controls pod-to-pod traffic rules
  - `serviceaccount.yaml` — Keycloak ServiceAccount
  - `servicemonitor.yaml` — Prometheus metrics scraping config
  - `NOTES.txt` — post-install instructions
  - `_helpers.tpl`