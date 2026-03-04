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