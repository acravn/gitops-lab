#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ── Prerequisites ──────────────────────────────────────────────────────────────
info "Checking prerequisites..."
command -v aws &>/dev/null || error "AWS CLI not found."
command -v terraform &>/dev/null || error "Terraform not found."
command -v kubectl &>/dev/null || error "kubectl not found."
command -v argocd &>/dev/null || error "argocd CLI not found."
command -v helm &>/dev/null || error "helm not found."

# Verify AWS credentials
aws sts get-caller-identity &>/dev/null || error "AWS credentials not configured. Run 'aws configure' first."
info "AWS credentials valid: $(aws sts get-caller-identity --query Arn --output text)"

LAB_DIR="$(dirname "$0")/.."
TF_DIR="${LAB_DIR}/terraform"

# ── Terraform init and apply ───────────────────────────────────────────────────
info "Initializing Terraform..."
cd "${TF_DIR}"
terraform init

info "Planning EKS clusters (review before applying)..."
terraform plan -out=tfplan

read -p "Apply Terraform plan? This will create EKS clusters (~15 mins, costs ~$0.20/hr per cluster). [y/N] " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || { info "Aborted."; exit 0; }

info "Applying Terraform (this takes ~15 minutes)..."
terraform apply tfplan

# ── Update kubeconfig ──────────────────────────────────────────────────────────
info "Updating kubeconfig..."
DEV_CLUSTER=$(terraform output -raw dev_cluster_name)
QA_CLUSTER=$(terraform output -raw qa_cluster_name)
REGION=$(terraform output -raw region)

aws eks update-kubeconfig \
  --name "$DEV_CLUSTER" \
  --region "$REGION" \
  --alias eks-dev

aws eks update-kubeconfig \
  --name "$QA_CLUSTER" \
  --region "$REGION" \
  --alias eks-qa

# ── Install Argo CD on dev cluster ────────────────────────────────────────────
info "Installing Argo CD on eks-dev..."
kubectl config use-context eks-dev

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

info "Waiting for Argo CD (~3 minutes on EKS)..."
kubectl wait --for=condition=available deployment/argocd-server \
  -n argocd --timeout=300s

# ── Install Argo Rollouts on both clusters ─────────────────────────────────────
for ctx in eks-dev eks-qa; do
  info "Installing Argo Rollouts on ${ctx}..."
  kubectl config use-context "$ctx"
  kubectl create namespace argo-rollouts --dry-run=client -o yaml | kubectl apply -f -
  kubectl apply -n argo-rollouts \
    -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
done

kubectl config use-context eks-dev

# ── Argo CD login ──────────────────────────────────────────────────────────────
ARGO_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)

# Get the Argo CD load balancer URL
info "Waiting for Argo CD LoadBalancer..."
sleep 30
ARGO_URL=$(kubectl get svc argocd-server -n argocd \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

info "Logging into Argo CD at ${ARGO_URL}..."
argocd login "$ARGO_URL" \
  --username admin \
  --password "$ARGO_PASSWORD" \
  --insecure

# ── Register eks-qa ────────────────────────────────────────────────────────────
info "Registering eks-qa with Argo CD..."
argocd cluster add eks-qa --yes

# ── Apply AppProject ───────────────────────────────────────────────────────────
kubectl config use-context eks-dev
kubectl apply -f "${LAB_DIR}/argocd/appproject.yaml"

# ── Output summary ─────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  EKS Lab environment ready!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  Argo CD UI:  https://${ARGO_URL}"
echo -e "  Username:    admin"
echo -e "  Password:    ${ARGO_PASSWORD}"
echo ""
echo -e "  Dev cluster:  ${DEV_CLUSTER}"
echo -e "  QA cluster:   ${QA_CLUSTER}"
echo ""
echo -e "${YELLOW}IMPORTANT: Remember to run teardown-eks.sh when done${NC}"
echo -e "${YELLOW}EKS clusters cost ~$0.10/hr each + node costs${NC}"
echo ""
echo -e "Next steps:"
echo -e "  1. Update appsets/ with your repo URL"
echo -e "  2. kubectl apply -f appsets/"
echo -e "  3. See README.md for lab exercises"
