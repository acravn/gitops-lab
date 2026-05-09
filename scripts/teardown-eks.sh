#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

warn "This will destroy all EKS clusters and associated AWS resources."
read -p "Are you sure? Type 'destroy' to confirm: " confirm
[[ "$confirm" == "destroy" ]] || { info "Aborted."; exit 0; }

LAB_DIR="$(dirname "$0")/.."
TF_DIR="${LAB_DIR}/terraform"

# Remove load balancers created by Kubernetes services
# (Terraform can't destroy these if they were created by K8s)
info "Cleaning up Kubernetes-managed AWS resources..."
for ctx in eks-dev eks-qa; do
  if kubectl config get-contexts "$ctx" &>/dev/null; then
    kubectl config use-context "$ctx"
    kubectl delete svc -n argocd argocd-server 2>/dev/null || true
    info "Cleaned up $ctx services"
  fi
done

sleep 10

info "Destroying Terraform resources..."
cd "${TF_DIR}"
terraform destroy -auto-approve

info "Cleaning up kubeconfig contexts..."
kubectl config delete-context eks-dev 2>/dev/null || true
kubectl config delete-context eks-qa 2>/dev/null || true

info "Done. All EKS resources destroyed."
