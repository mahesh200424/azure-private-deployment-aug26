#!/usr/bin/env bash
# =============================================================================
# install-argocd.sh
# Bootstrap ArgoCD + Argo Rollouts on an AKS cluster for GitOps blue-green
# deployments.
#
# Usage:
#   chmod +x install-argocd.sh
#   ./install-argocd.sh [--context <kubeconfig-context>] [--with-rollouts]
#
# Prerequisites:
#   - kubectl configured and pointing at the target AKS cluster
#   - Helm v3 installed
#   - jq installed (for JSON parsing)
#   - curl installed
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Colour helpers
# -----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'  # No Colour

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()     { error "$*"; exit 1; }

# -----------------------------------------------------------------------------
# Version pinning — update these when upgrading
# -----------------------------------------------------------------------------
ARGOCD_VERSION="v2.11.3"
ARGOCD_ROLLOUTS_VERSION="v1.7.1"
ARGOCD_NAMESPACE="argocd"
ROLLOUTS_NAMESPACE="argo-rollouts"

# Script directory — manifests live alongside this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# -----------------------------------------------------------------------------
# Argument parsing
# -----------------------------------------------------------------------------
KUBE_CONTEXT=""
SKIP_ROLLOUTS=true
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --context)
      KUBE_CONTEXT="$2"
      shift 2
      ;;
    --skip-rollouts)
      SKIP_ROLLOUTS=true
      shift
      ;;
    --with-rollouts)
      SKIP_ROLLOUTS=false
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [--context <ctx>] [--with-rollouts] [--dry-run]"
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

if [[ -n "$KUBE_CONTEXT" ]]; then
  info "Switching kubectl context to: $KUBE_CONTEXT"
  kubectl config use-context "$KUBE_CONTEXT"
fi

# -----------------------------------------------------------------------------
# Pre-flight checks
# -----------------------------------------------------------------------------
info "Running pre-flight checks..."

for cmd in kubectl helm curl jq; do
  if ! command -v "$cmd" &>/dev/null; then
    die "'$cmd' is not installed or not in PATH. Please install it first."
  fi
done

CURRENT_CONTEXT=$(kubectl config current-context)
CURRENT_CLUSTER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
info "Target cluster context : $CURRENT_CONTEXT"
info "Target cluster endpoint: $CURRENT_CLUSTER"

echo ""
warn "This script will install ArgoCD ${ARGOCD_VERSION} and Argo Rollouts ${ARGOCD_ROLLOUTS_VERSION}."
warn "Cluster: $CURRENT_CLUSTER"
echo ""
read -rp "Continue? [y/N] " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { info "Aborted."; exit 0; }

# Dry-run mode prefix
KUBECTL_DRY=""
HELM_DRY=""
if [[ "$DRY_RUN" == "true" ]]; then
  warn "DRY RUN mode — no changes will be applied."
  KUBECTL_DRY="--dry-run=client"
  HELM_DRY="--dry-run"
fi

# =============================================================================
# STEP 1 — Create namespaces
# =============================================================================
info "Step 1/7: Creating namespaces..."

for NS in "$ARGOCD_NAMESPACE" "$ROLLOUTS_NAMESPACE" "myapp"; do
  if kubectl get namespace "$NS" &>/dev/null; then
    info "Namespace '$NS' already exists, skipping."
  else
    kubectl create namespace "$NS" $KUBECTL_DRY
    success "Created namespace: $NS"
  fi
done

# =============================================================================
# STEP 2 — Install ArgoCD
# =============================================================================
info "Step 2/7: Installing ArgoCD ${ARGOCD_VERSION}..."

ARGOCD_INSTALL_URL="https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

# Prefer Helm install for easier upgrades; fall back to plain manifest
if helm repo list 2>/dev/null | grep -q "argo"; then
  info "Using existing 'argo' Helm repo."
else
  helm repo add argo https://argoproj.github.io/argo-helm
  helm repo update argo
fi

if helm status argocd -n "$ARGOCD_NAMESPACE" &>/dev/null; then
  info "ArgoCD Helm release already exists — upgrading..."
  HELM_CMD="upgrade"
else
  info "Installing ArgoCD via Helm..."
  HELM_CMD="install"
fi

helm "$HELM_CMD" argocd argo/argo-cd \
  --namespace "$ARGOCD_NAMESPACE" \
  --version "${ARGOCD_VERSION#v}" \
  --set global.image.tag="$ARGOCD_VERSION" \
  --set server.service.type=ClusterIP \
  --set server.extraArgs[0]="--insecure" \
  --set configs.params."server\.insecure"=true \
  --set server.metrics.enabled=true \
  --set controller.metrics.enabled=true \
  --set repoServer.metrics.enabled=true \
  --set applicationSet.metrics.enabled=true \
  --set notifications.enabled=true \
  --set dex.enabled=false \
  --set redis-ha.enabled=false \
  --set controller.replicas=1 \
  --set server.replicas=1 \
  --set repoServer.replicas=1 \
  --set applicationSet.replicaCount=1 \
  --set configs.cm."application\.resourceTrackingMethod"=annotation \
  --wait \
  --timeout 10m \
  $HELM_DRY

success "ArgoCD ${ARGOCD_VERSION} installed/upgraded."

# =============================================================================
# STEP 3 — Install Argo Rollouts
# =============================================================================
if [[ "$SKIP_ROLLOUTS" == "false" ]]; then
  info "Step 3/7: Installing Argo Rollouts ${ARGOCD_ROLLOUTS_VERSION}..."

  if helm status argo-rollouts -n "$ROLLOUTS_NAMESPACE" &>/dev/null; then
    info "Argo Rollouts Helm release already exists — upgrading..."
    HELM_CMD_R="upgrade"
  else
    HELM_CMD_R="install"
  fi

  helm "$HELM_CMD_R" argo-rollouts argo/argo-rollouts \
    --namespace "$ROLLOUTS_NAMESPACE" \
    --version "${ARGOCD_ROLLOUTS_VERSION#v}" \
    --set installCRDs=true \
    --set dashboard.enabled=true \
    --set dashboard.service.type=ClusterIP \
    --set metrics.enabled=true \
    --set controller.replicas=2 \
    --wait \
    --timeout 5m \
    $HELM_DRY

  success "Argo Rollouts ${ARGOCD_ROLLOUTS_VERSION} installed/upgraded."

  # Install the kubectl argo rollouts plugin if not already present
  if ! kubectl argo rollouts version &>/dev/null 2>&1; then
    info "Installing kubectl-argo-rollouts plugin..."
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    [[ "$ARCH" == "x86_64" ]] && ARCH="amd64"
    [[ "$ARCH" == "aarch64" ]] && ARCH="arm64"

    PLUGIN_URL="https://github.com/argoproj/argo-rollouts/releases/download/${ARGOCD_ROLLOUTS_VERSION}/kubectl-argo-rollouts-${OS}-${ARCH}"
    curl -sL "$PLUGIN_URL" -o /tmp/kubectl-argo-rollouts
    chmod +x /tmp/kubectl-argo-rollouts
    sudo mv /tmp/kubectl-argo-rollouts /usr/local/bin/kubectl-argo-rollouts
    success "kubectl-argo-rollouts plugin installed."
  else
    info "kubectl-argo-rollouts plugin already installed."
  fi
else
  info "Step 3/7: Skipping Argo Rollouts installation (--skip-rollouts)."
fi

# =============================================================================
# STEP 4 — Wait for ArgoCD pods to be ready
# =============================================================================
info "Step 4/7: Waiting for ArgoCD pods to become ready..."

kubectl rollout status deployment/argocd-server \
  -n "$ARGOCD_NAMESPACE" \
  --timeout=5m

kubectl rollout status deployment/argocd-repo-server \
  -n "$ARGOCD_NAMESPACE" \
  --timeout=5m

kubectl rollout status deployment/argocd-applicationset-controller \
  -n "$ARGOCD_NAMESPACE" \
  --timeout=5m || true  # Non-fatal if applicationset is not deployed

success "ArgoCD pods are ready."

# =============================================================================
# STEP 5 — Patch argocd-server Service
# Expose via LoadBalancer for direct access (use Ingress in production)
# =============================================================================
info "Step 5/7: Patching argocd-server service..."

CURRENT_SVC_TYPE=$(kubectl get svc argocd-server -n "$ARGOCD_NAMESPACE" \
  -o jsonpath='{.spec.type}')

if [[ "$CURRENT_SVC_TYPE" == "LoadBalancer" ]]; then
  info "argocd-server service is already of type LoadBalancer."
else
  # Option A: Azure Internal Load Balancer (recommended for private AKS clusters)
  kubectl patch svc argocd-server \
    -n "$ARGOCD_NAMESPACE" \
    --type='json' \
    -p='[
      {
        "op": "replace",
        "path": "/spec/type",
        "value": "LoadBalancer"
      },
      {
        "op": "add",
        "path": "/metadata/annotations/service.beta.kubernetes.io~1azure-load-balancer-internal",
        "value": "true"
      }
    ]' $KUBECTL_DRY

  success "argocd-server service patched to internal LoadBalancer."

  info "Waiting for LoadBalancer IP assignment (up to 3 minutes)..."
  for i in $(seq 1 36); do
    LB_IP=$(kubectl get svc argocd-server -n "$ARGOCD_NAMESPACE" \
      -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
    if [[ -n "$LB_IP" ]]; then
      success "ArgoCD server LoadBalancer IP: $LB_IP"
      break
    fi
    sleep 5
  done

  if [[ -z "${LB_IP:-}" ]]; then
    warn "LoadBalancer IP not yet assigned. Check later with:"
    warn "  kubectl get svc argocd-server -n $ARGOCD_NAMESPACE"
  fi
fi

# =============================================================================
# STEP 6 — Apply ArgoCD Project and Application manifests
# =============================================================================
info "Step 6/7: Applying ArgoCD manifests..."

# Apply AppProject first (Application references it)
if [[ -f "$SCRIPT_DIR/project.yaml" ]]; then
  info "Applying AppProject..."
  kubectl apply -f "$SCRIPT_DIR/project.yaml" \
    -n "$ARGOCD_NAMESPACE" $KUBECTL_DRY
  success "AppProject applied."
else
  warn "project.yaml not found at $SCRIPT_DIR/project.yaml — skipping."
fi

# Apply the Application manifest
if [[ -f "$SCRIPT_DIR/application.yaml" ]]; then
  info "Applying Application..."
  kubectl apply -f "$SCRIPT_DIR/application.yaml" \
    -n "$ARGOCD_NAMESPACE" $KUBECTL_DRY
  success "Application applied."
else
  warn "application.yaml not found at $SCRIPT_DIR/application.yaml — skipping."
fi

# The Helm chart is the single owner of myapp workloads. Do not apply the
# legacy Rollout manifests here: they define the same Services and would cause
# ArgoCD to report shared-resource conflicts.
info "Skipping legacy Argo Rollouts manifests; Helm chart owns the workload."

# =============================================================================
# STEP 7 — Retrieve initial admin password
# =============================================================================
info "Step 7/7: Retrieving ArgoCD initial admin password..."

if [[ "$DRY_RUN" == "false" ]]; then
  # Wait a moment for the secret to be created
  sleep 3

  ADMIN_PASSWORD=$(kubectl -n "$ARGOCD_NAMESPACE" \
    get secret argocd-initial-admin-secret \
    -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo "")

  if [[ -n "$ADMIN_PASSWORD" ]]; then
    echo ""
    echo "================================================================="
    echo "  ArgoCD Initial Admin Credentials"
    echo "================================================================="
    echo "  Username : admin"
    echo "  Password : $ADMIN_PASSWORD"
    echo ""
    echo "  IMPORTANT: Change this password immediately after first login!"
    echo "  Run: argocd account update-password"
    echo ""
    if [[ -n "${LB_IP:-}" ]]; then
      echo "  UI URL   : https://$LB_IP"
      echo "  Login    : argocd login $LB_IP --username admin --password '$ADMIN_PASSWORD' --insecure"
    fi
    echo "================================================================="
    echo ""
    warn "Store the password securely. Delete the secret after changing:"
    warn "  kubectl delete secret argocd-initial-admin-secret -n $ARGOCD_NAMESPACE"
  else
    warn "Could not retrieve initial admin password."
    warn "Check manually: kubectl -n $ARGOCD_NAMESPACE get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
  fi
else
  info "[DRY RUN] Would retrieve password from secret argocd-initial-admin-secret"
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
success "Bootstrap complete!"
echo ""
echo "  ArgoCD version        : $ARGOCD_VERSION"
echo "  Argo Rollouts version : $ARGOCD_ROLLOUTS_VERSION"
echo "  ArgoCD namespace      : $ARGOCD_NAMESPACE"
echo "  Rollouts namespace    : $ROLLOUTS_NAMESPACE"
echo "  App namespace         : myapp"
echo ""
echo "  Useful commands:"
echo "  ─────────────────────────────────────────────────────────────────"
echo "  # Port-forward ArgoCD UI locally"
echo "  kubectl port-forward svc/argocd-server -n $ARGOCD_NAMESPACE 8080:443"
echo ""
echo "  # Port-forward Argo Rollouts dashboard"
echo "  kubectl argo rollouts dashboard -n myapp"
echo ""
echo "  # Watch rollout status"
echo "  kubectl argo rollouts get rollout myapp -n myapp --watch"
echo ""
echo "  # Manually promote blue-green after pre-promotion analysis passes"
echo "  kubectl argo rollouts promote myapp -n myapp"
echo ""
echo "  # Abort a rollout and roll back"
echo "  kubectl argo rollouts abort myapp -n myapp"
echo "  kubectl argo rollouts undo myapp -n myapp"
echo "  ─────────────────────────────────────────────────────────────────"
