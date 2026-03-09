#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
# bootstrap.sh — Full cluster bootstrap + teardown
# Usage:
#   ./bootstrap.sh          → install everything
#   ./bootstrap.sh teardown → remove everything
#
# ⚠ MUST be run from repo root:
#   cd ~/argocd-work/jenkin-argo-gitops
#   ./bootstrap.sh
# ══════════════════════════════════════════════════════════════════════════════

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# ── Safety check — must run from repo root ────────────────────────────────────
if [ ! -f "argocd/root-app.yaml" ]; then
  echo -e "${RED}❌ Wrong directory!${NC}"
  echo ""
  echo "  Run this script from the repo root:"
  echo "  cd ~/argocd-work/jenkin-argo-gitops"
  echo "  ./bootstrap.sh"
  exit 1
fi

if [ ! -f "vault-setup.sh" ]; then
  echo -e "${RED}❌ vault-setup.sh not found!${NC}"
  echo ""
  echo "  Make sure vault-setup.sh is in the same directory:"
  echo "  ~/argocd-work/jenkin-argo-gitops/vault-setup.sh"
  exit 1
fi

# ══════════════════════════════════════════════════════
# TEARDOWN — remove everything
# ══════════════════════════════════════════════════════
if [ "$1" == "teardown" ]; then
  echo "========================================="
  echo -e "${RED} Teardown — removing everything${NC}"
  echo "========================================="

  # ── Remove ArgoCD Applications ──────────────────────
  echo ""
  echo "=== Removing ArgoCD Applications ==="
  kubectl delete application \
    root-app fullstack-app-prod fullstack-app-dev argocd-vault-plugin vault \
    -n argocd --ignore-not-found
  echo -e "${GREEN}✓ ArgoCD applications deleted${NC}"

  # ── Remove AVP credentials ───────────────────────────
  echo ""
  echo "=== Removing AVP credentials ==="
  kubectl delete secret argocd-vault-plugin-credentials -n argocd --ignore-not-found
  echo -e "${GREEN}✓ AVP secret deleted${NC}"

  # ── Remove cmp-plugin ConfigMap ──────────────────────
  echo ""
  echo "=== Removing cmp-plugin ConfigMap ==="
  kubectl delete configmap cmp-plugin -n argocd --ignore-not-found
  echo -e "${GREEN}✓ cmp-plugin ConfigMap deleted${NC}"

  # ── Reset argocd-cm to EMPTY (NEVER delete it) ───────
  echo ""
  echo "=== Resetting argocd-cm to empty (keeping it alive) ==="
  kubectl apply -f - <<HEREDOC
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
  labels:
    app.kubernetes.io/name: argocd-cm
    app.kubernetes.io/part-of: argocd
data: {}
HEREDOC
  echo -e "${GREEN}✓ argocd-cm reset to empty — ArgoCD stays healthy${NC}"

  # ── Remove Vault namespace + PVCs ───────────────────
  echo ""
  echo "=== Removing Vault PVCs and namespace ==="
  kubectl delete pvc --all -n vault --ignore-not-found
  kubectl delete namespace vault --ignore-not-found
  echo -e "${GREEN}✓ Vault namespace deleted${NC}"

  # ── Remove prod and dev namespaces ──────────────────
  echo ""
  echo "=== Removing prod and dev namespaces ==="
  kubectl delete namespace prod dev --ignore-not-found
  echo -e "${GREEN}✓ prod + dev namespaces deleted${NC}"

  # ── Remove StorageClass ─────────────────────────────
  echo ""
  echo "=== Removing local-path StorageClass ==="
  if kubectl get storageclass local-path &>/dev/null; then
    kubectl delete -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml --ignore-not-found
    echo -e "${GREEN}✓ StorageClass deleted${NC}"
  else
    echo -e "${YELLOW}⚠ StorageClass not found — skipping${NC}"
  fi

  # ── Restart ArgoCD cleanly ───────────────────────────
  echo ""
  echo "=== Restarting ArgoCD ==="
  kubectl rollout restart deployment argocd-server -n argocd
  kubectl rollout restart deployment argocd-repo-server -n argocd
  kubectl rollout status deployment argocd-server -n argocd
  kubectl rollout status deployment argocd-repo-server -n argocd
  echo -e "${GREEN}✓ ArgoCD restarted and healthy${NC}"

  echo ""
  echo "========================================="
  echo -e "${GREEN} ✓ Teardown complete!${NC}"
  echo "========================================="
  echo ""
  echo "  ArgoCD itself is still installed."
  echo "  To fully remove ArgoCD run:"
  echo "  kubectl delete namespace argocd"
  exit 0
fi

# ══════════════════════════════════════════════════════
# BOOTSTRAP — install everything
# ══════════════════════════════════════════════════════
set -e

echo "========================================="
echo " Bootstrap — seang.shop"
echo "========================================="
echo ""
echo "  Running from: $(pwd)"

# ── Pre-requisite: Wait for ArgoCD ──────────────────
echo ""
echo "=== Pre-requisite: Waiting for ArgoCD to be ready ==="
echo -e "${YELLOW}⏳ Waiting for ArgoCD deployments...${NC}"
until kubectl rollout status deployment argocd-server -n argocd &>/dev/null && \
      kubectl rollout status deployment argocd-repo-server -n argocd &>/dev/null; do
  echo "  Waiting for ArgoCD..."
  sleep 5
done
echo -e "${GREEN}✓ ArgoCD is ready${NC}"

# ── Step 0: StorageClass ─────────────────────────────
echo ""
echo "=== Step 0: Installing local-path StorageClass ==="
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
kubectl patch storageclass local-path \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
echo -e "${GREEN}✓ StorageClass local-path set as default${NC}"

# ── Step 1: AVP credentials + cmp-plugin ConfigMap ──
echo ""
echo "=== Step 1: Applying AVP credentials and cmp-plugin ConfigMap ==="
kubectl apply -f argocd/avp/avp-credentials.yaml
echo -e "${GREEN}✓ AVP credentials applied${NC}"

kubectl apply -f argocd/avp/argocd-cm-plugin.yaml
echo -e "${GREEN}✓ cmp-plugin ConfigMap applied${NC}"

# ── Step 2: Patch repo-server with AVP sidecar ──────
echo ""
echo ""
echo "=== Step 2: Patching repo-server with AVP sidecar ==="
# NOTE: repo-server-patch.yaml lives in repo ROOT, not argocd/avp/
# ArgoCD would try to apply it as a full Deployment which fails without selector
if [ ! -f "repo-server-patch.yaml" ]; then
  echo -e "${RED}❌ repo-server-patch.yaml not found in repo root!${NC}"
  exit 1
fi
kubectl patch deployment argocd-repo-server -n argocd \
  --patch-file repo-server-patch.yaml
echo -e "${GREEN}✓ repo-server patched with AVP sidecar${NC}"

echo ""
echo "=== Waiting for repo-server to restart with AVP sidecar ==="
kubectl rollout status deployment argocd-repo-server -n argocd
echo -e "${GREEN}✓ repo-server restarted${NC}"

# ── Verify sidecar is present ────────────────────────
echo ""
echo "=== Verifying AVP sidecar ==="
echo -e "${YELLOW}⏳ Waiting for new repo-server pod to be Ready...${NC}"
kubectl wait pod -n argocd \
  -l app.kubernetes.io/name=argocd-repo-server \
  --for=condition=Ready \
  --timeout=120s

CONTAINERS=$(kubectl get pod -n argocd -l app.kubernetes.io/name=argocd-repo-server \
  --field-selector=status.phase=Running \
  -o jsonpath='{.items[0].spec.containers[*].name}')
echo ""
echo "  Containers in repo-server: $CONTAINERS"
if echo "$CONTAINERS" | grep -q "avp-helm"; then
  echo -e "${GREEN}✓ AVP sidecar confirmed${NC}"
else
  echo -e "${RED}❌ AVP sidecar NOT found — check repo-server logs${NC}"
  kubectl describe pod -n argocd -l app.kubernetes.io/name=argocd-repo-server | tail -20
  exit 1
fi

# ── Step 3: Root app ─────────────────────────────────
echo ""
echo "=== Step 3: Applying root-app ==="
kubectl apply -f argocd/root-app.yaml
echo -e "${GREEN}✓ root-app created${NC}"
echo ""
echo "  ArgoCD will now automatically deploy:"
echo "  wave 0 → Vault"
echo "  wave 1 → argocd-vault-plugin"
echo "  wave 2 → fullstack-app-prod + fullstack-app-dev"

# ── Step 4: Wait for Vault ───────────────────────────
echo ""
echo "=== Step 4: Waiting for Vault pod to be Running ==="
echo -e "${YELLOW}⏳ This may take a few minutes...${NC}"
until kubectl get pod vault-0 -n vault 2>/dev/null | grep -q "Running"; do
  echo "  Waiting for vault-0..."
  sleep 10
done
echo -e "${GREEN}✓ Vault pod is Running${NC}"

# ── Step 5: Vault setup ──────────────────────────────
echo ""
echo "=== Step 5: Running Vault setup ==="
chmod +x vault-setup.sh
./vault-setup.sh
echo -e "${GREEN}✓ Vault setup complete${NC}"

# ── Step 6: Verify ───────────────────────────────────
echo ""
echo "=== Step 6: Verifying all applications ==="
sleep 10
kubectl get applications -n argocd

echo ""
echo "========================================="
echo -e "${GREEN} ✓ Bootstrap complete!${NC}"
echo "========================================="
echo ""
echo -e "${YELLOW}⚠ Don't forget:${NC}"
echo "  1. Store vault-init-keys.json in a password manager"
echo "  2. Delete it:          rm vault-init-keys.json"
echo "  3. Delete bootstrap:   rm bootstrap.sh"
echo "  4. Delete vault setup: rm vault-setup.sh"
echo ""
echo "=== Verifying Vault paths have data ==="
for path in \
  secret/prod/cloudflare \
  secret/prod/database \
  secret/prod/keycloak \
  secret/prod/certmanager \
  secret/dev/cloudflare \
  secret/dev/database \
  secret/dev/keycloak \
  secret/dev/certmanager; do
  echo ""
  echo "══════════════════════════"
  echo " $path"
  echo "══════════════════════════"
  kubectl exec -n vault vault-0 -- vault kv get $path
done