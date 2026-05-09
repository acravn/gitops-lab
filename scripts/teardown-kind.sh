#!/bin/bash
set -e

GREEN='\033[0;32m'
NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $1"; }

info "Deleting kind clusters..."
kind delete cluster --name cluster-dev 2>/dev/null || true
kind delete cluster --name cluster-qa 2>/dev/null || true

info "Cleaning up kubeconfig contexts..."
kubectl config delete-context kind-cluster-dev 2>/dev/null || true
kubectl config delete-context kind-cluster-qa 2>/dev/null || true

info "Done."
