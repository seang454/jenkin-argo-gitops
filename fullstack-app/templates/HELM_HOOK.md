# Helm Cloudflare DNS Hook

A guide to automatically creating Cloudflare subdomains using Helm Hooks during chart installation and upgrades.

---

## Overview

This approach uses a Kubernetes `Job` triggered by Helm Hook annotations to call the Cloudflare API and create a DNS record automatically — no external tools like `external-dns` required.

---

## Chart Structure

Store everything within your existing chart:

```
my-chart/
├── Chart.yaml
├── values.yaml
├── templates/
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   ├── _helpers.tpl
│   ├── cloudflare-secret.yaml      # Stores Cloudflare credentials
│   └── cloudflare-dns-job.yaml     # The hook job
```

> **Why not a subchart?**  
> A subchart is best for reusable, decoupled components. Since this DNS job is tightly coupled to your deployment (it needs your IP, subdomain, and zone), keeping it in the same chart gives it direct access to `values.yaml` and keeps things simple.

---

## Configuration

### `values.yaml`

Add the following Cloudflare section to your `values.yaml`:

```yaml
cloudflare:
  zoneId: "your-zone-id"
  subdomain: "myapp"        # Creates myapp.yourdomain.com
  recordType: "A"
  targetIP: "1.2.3.4"       # Your ingress/LoadBalancer IP
  ttl: 1                    # 1 = auto TTL in Cloudflare
  proxied: true
  secretName: "cloudflare-api-secret"
```

> ⚠️ **Never hardcode `apiToken` in `values.yaml`** — always pass it at deploy time (see [Installation](#installation)).

---

## Template Files

### `templates/cloudflare-secret.yaml`

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: {{ .Values.cloudflare.secretName }}
  annotations:
    "helm.sh/hook": pre-install
    "helm.sh/hook-weight": "-5"
type: Opaque
stringData:
  token: {{ required "Cloudflare API token required" .Values.cloudflare.apiToken | quote }}
  zoneId: {{ required "Cloudflare Zone ID required" .Values.cloudflare.zoneId | quote }}
```

### `templates/cloudflare-dns-job.yaml`

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "my-chart.fullname" . }}-cf-dns
  annotations:
    "helm.sh/hook": post-install,post-upgrade
    "helm.sh/hook-weight": "0"
    "helm.sh/hook-delete-policy": hook-succeeded
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: cloudflare-dns
          image: curlimages/curl:latest
          env:
            - name: CF_TOKEN
              valueFrom:
                secretKeyRef:
                  name: {{ .Values.cloudflare.secretName }}
                  key: token
            - name: ZONE_ID
              valueFrom:
                secretKeyRef:
                  name: {{ .Values.cloudflare.secretName }}
                  key: zoneId
          command:
            - sh
            - -c
            - |
              curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
                -H "Authorization: Bearer $CF_TOKEN" \
                -H "Content-Type: application/json" \
                --data '{
                  "type": "{{ .Values.cloudflare.recordType }}",
                  "name": "{{ .Values.cloudflare.subdomain }}",
                  "content": "{{ .Values.cloudflare.targetIP }}",
                  "ttl": {{ .Values.cloudflare.ttl }},
                  "proxied": {{ .Values.cloudflare.proxied }}
                }'
```

---

## Hook Annotations Explained

### `helm.sh/hook`

Tells Helm **when** to run the resource. Without this annotation, Kubernetes treats the Job as a regular resource deployed alongside everything else — which means the `targetIP` may not exist yet.

| Hook | When It Runs |
|---|---|
| `pre-install` | Before any resources are created |
| `post-install` | After all resources are created |
| `pre-upgrade` | Before upgrade starts |
| `post-upgrade` | After upgrade completes |
| `pre-delete` | Before a release is deleted |
| `post-delete` | After a release is deleted |

We use `post-install,post-upgrade` so the DNS record is created after deployment **and** updated whenever you run `helm upgrade`.

---

### `helm.sh/hook-weight`

Controls the **order** when multiple hooks run at the same stage. Lower numbers run first.

```
pre-install  →  cloudflare-secret.yaml   (weight: -5)  ← secret created first
post-install →  cloudflare-dns-job.yaml  (weight:  0)  ← job runs after
```

If both had the same weight, the secret might not exist when the job tries to read it.

---

### `helm.sh/hook-delete-policy`

Tells Helm what to do with the Job after it finishes. Without this, completed Jobs pile up in your cluster forever.

| Policy | Behavior |
|---|---|
| `hook-succeeded` | Delete Job only if it **succeeded** ✅ |
| `hook-failed` | Delete Job only if it **failed** |
| `before-hook-creation` | Delete previous Job before running a new one |

We use `hook-succeeded` so:
- On **success** → Job is deleted, cluster stays clean
- On **failure** → Job is kept so you can inspect the logs to debug

---

## Helm Template Functions

### `required`

```yaml
token: {{ required "Cloudflare API token required" .Values.cloudflare.apiToken | quote }}
```

`required` forces a value to be provided. If it is missing or empty, Helm **aborts immediately** with your custom error message instead of silently deploying with an empty value.

```
Error: execution error at (my-chart/templates/cloudflare-secret.yaml):
  Cloudflare API token required
```

---

### `quote`

```yaml
token: {{ .Values.cloudflare.apiToken | quote }}
```

`quote` wraps a value in double quotes so YAML does not misinterpret it. Without quotes, values like `true`, `null`, `123`, or `@token` can be parsed as booleans, nil, integers, or cause YAML errors.

The `|` pipe operator passes the value on the left into the function on the right. Functions can be chained:

```yaml
{{ .Values.someValue | trim | lower | quote }}
```

---

### `stringData` vs `data`

| | `data` | `stringData` |
|---|---|---|
| Format | Base64 encoded | Plain text |
| Who encodes | You manually | Kubernetes automatically |
| Use in Helm | Needs `\| b64enc` filter | Works with `\| quote` directly |

We use `stringData` in Helm templates because it is simpler — no manual base64 encoding required.

> ⚠️ `stringData` is write-only. When you run `kubectl get secret -o yaml`, Kubernetes always returns values under `data` (base64 encoded), never `stringData`.

---

## Hook Execution Order Summary

```
helm install
      │
      ├── pre-install  → cloudflare-secret.yaml  (weight: -5) → secret created
      ├── install      → deployment, service, ingress deployed
      └── post-install → cloudflare-dns-job.yaml (weight:  0)
                              ├── succeeds → Job deleted (clean) ✅
                              └── fails    → Job kept (check logs) ✅

helm upgrade (e.g. subdomain changed in values.yaml)
      │
      └── post-upgrade → cloudflare-dns-job.yaml runs again → DNS updated ✅
```

---

## Installation

Pass the API token securely at deploy time — never commit it to `values.yaml`:

```bash
# Pass token directly
helm install my-release ./my-chart \
  --set cloudflare.apiToken="your-secret-token"

# Or use a gitignored secrets file
helm install my-release ./my-chart -f secret-values.yaml
```

**`secret-values.yaml`** (add to `.gitignore`):
```yaml
cloudflare:
  apiToken: "your-secret-token"
```

---

## Getting Your Cloudflare Credentials

| Value | Where to find it |
|---|---|
| `apiToken` | Cloudflare Dashboard → My Profile → API Tokens → Create Token |
| `zoneId` | Cloudflare Dashboard → Your Domain → Overview → Zone ID (right sidebar) |

> The API token needs the **Zone DNS Edit** permission for the target domain.