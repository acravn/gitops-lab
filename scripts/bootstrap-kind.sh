#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ── Check prerequisites ────────────────────────────────────────────────────────
info "Checking prerequisites..."
command -v docker &>/dev/null || error "Docker not found. Install Docker Desktop first."
command -v kubectl &>/dev/null || error "kubectl not found."
command -v argocd &>/dev/null || error "argocd CLI not found."
command -v helm &>/dev/null || error "helm not found."

# Install kind if missing
if ! command -v kind &>/dev/null; then
  error "kind not found. Please install kind CLI: https://kind.sigs.k8s.io/docs/user/quick-start/#installation"
else
  info "kind found: $(kind version)"
fi

# Install kubectl argo rollouts plugin if missing
if ! kubectl argo rollouts version &>/dev/null 2>&1; then
  error "kubectl argo rollouts plugin not found. Please install the plugin: https://argoproj.github.io/argo-rollouts/installation/"
else
  info "kubectl argo rollouts plugin found: $(kubectl argo rollouts version --short)"
fi


LAB_DIR="$(dirname "$0")/.."

# ── Create clusters ────────────────────────────────────────────────────────────
info "Creating kind clusters..."

for cluster in cluster-dev cluster-qa; do
  if kind get clusters 2>/dev/null | grep -q "^${cluster}$"; then
    warn "Cluster '${cluster}' already exists. Deleting and recreating..."
    kind delete cluster --name "$cluster"
  fi
done

kind create cluster --name cluster-dev --config "${LAB_DIR}/argocd/kind-cluster-dev.yaml"
info "cluster-dev created."

kind create cluster --name cluster-qa --config "${LAB_DIR}/argocd/kind-cluster-qa.yaml"
info "cluster-qa created."

# ── Install Argo CD on cluster-dev ─────────────────────────────────────────────
info "Installing Argo CD on cluster-dev..."
kubectl config use-context kind-cluster-dev

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd --server-side=true -f \
  https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

info "Waiting for Argo CD to be ready (~2 minutes)..."
kubectl wait --for=condition=available deployment/argocd-server \
  -n argocd --timeout=180s

# ── Install Argo Rollouts on both clusters ─────────────────────────────────────
info "Installing Argo Rollouts on cluster-dev..."
kubectl config use-context kind-cluster-dev
kubectl create namespace argo-rollouts --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argo-rollouts --server-side=true \
  -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml

info "Installing Argo Rollouts on cluster-qa..."
kubectl config use-context kind-cluster-qa
kubectl create namespace argo-rollouts --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argo-rollouts \
  -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml

# ── Back to cluster-dev for Argo CD setup ─────────────────────────────────────
kubectl config use-context kind-cluster-dev

# ── Get initial admin password ─────────────────────────────────────────────────
ARGO_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)

# # ── Port-forward and login ─────────────────────────────────────────────────────
# info "Starting port-forward for Argo CD UI on https://localhost:8080..."
# kubectl port-forward svc/argocd-server -n argocd 8080:443 &
# PF_PID=$!
# sleep 4

# argocd login localhost:8080 \
#   --username admin \
#   --password "$ARGO_PASSWORD" \
#   --insecure

# # Create a modified kubeconfig with the internal IP
# kubectl config view --raw > /tmp/kubeconfig-qa.yaml

# # Edit it to replace the localhost address with Docker internal IP
# sed -i '' "s|127.0.0.1:.*|${QA_IP}:6443|g" /tmp/kubeconfig-qa.yaml

# # Register using the modified kubeconfig
# KUBECONFIG=/tmp/kubeconfig-qa.yaml \
#   argocd cluster add kind-cluster-qa --yes

# # ── Apply AppProject ───────────────────────────────────────────────────────────
# info "Applying AppProject..."
# kubectl apply -f "${LAB_DIR}/argocd/appproject.yaml"

# # ── Done ───────────────────────────────────────────────────────────────────────
# echo ""
# echo -e "${GREEN}════════════════════════════════════════════════════${NC}"
# echo -e "${GREEN}  Lab environment ready!${NC}"
# echo -e "${GREEN}════════════════════════════════════════════════════${NC}"
# echo ""
# echo -e "  Argo CD UI:  https://localhost:8080"
# echo -e "  Username:    admin"
# echo -e "  Password:    ${ARGO_PASSWORD}"
# echo ""
# echo -e "  Port-forward PID: ${PF_PID}"
# echo -e "  To stop:  kill ${PF_PID}"
# echo ""
# echo -e "  Registered clusters:"
# argocd cluster list
# echo ""
# echo -e "${YELLOW}Next steps:${NC}"
# echo -e "  1. Push this repo to GitHub"
# echo -e "  2. Update appsets/ with your repo URL"
# echo -e "  3. kubectl apply -f appsets/"
# echo -e "  4. See README.md for lab exercises"
