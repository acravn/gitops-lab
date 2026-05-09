# GitOps Multi-Cluster Lab v2

Multi-cluster Argo CD lab with ApplicationSets, Argo Rollouts (blue/green + canary),
environment promotion flow, and sync windows. Supports both kind (local) and EKS (AWS).

## Prerequisites

- Docker Desktop (for kind)
- `kubectl`
- `argocd` CLI
- `helm`
- AWS CLI + credentials (for EKS path only)
- Terraform >= 1.5 (for EKS path only)

## Quick Start — kind (local)

```bash
# 1. Push this repo to GitHub first (git generator needs a real URL)
git init && git add . && git commit -m "initial"
git remote add origin https://github.com/YOUR_USERNAME/gitops-lab-v2.git
git push -u origin main

# 2. Update repo URLs
# Edit appsets/test-app-appset.yaml — replace YOUR_USERNAME in both repoURL fields

# 3. Bootstrap
chmod +x scripts/*.sh
./scripts/bootstrap-kind.sh

# 4. Apply ApplicationSet
kubectl apply -f appsets/
```

## Quick Start — EKS (AWS)

```bash
# Same steps 1-2 as above, then:
./scripts/bootstrap-eks.sh

# IMPORTANT: Tear down when done to avoid AWS charges
./scripts/teardown-eks.sh
```

**EKS cost estimate:** ~$0.20/hr for two t3.medium node groups + $0.10/hr per cluster control plane.
A 4-hour lab session costs roughly $2-3. Always run teardown when finished.

## Repo Structure

```
gitops-lab-v2/
├── clusters/
│   ├── dev/
│   │   ├── cluster.yaml              # cluster metadata for git generator
│   │   └── values/
│   │       └── test-app.yaml         # dev: canary, fast steps, image v1.25
│   └── qa/
│       ├── cluster.yaml
│       └── values/
│           └── test-app.yaml         # qa: blue/green, manual gate, image v1.24
├── charts/
│   └── test-app/                     # nginx helm chart with Argo Rollouts
│       ├── Chart.yaml
│       ├── values/defaults.yaml
│       └── templates/
│           ├── rollout.yaml          # Rollout resource (blueGreen or canary)
│           └── services.yaml        # active/preview or stable/canary services
├── appsets/
│   └── test-app-appset.yaml         # ApplicationSet — deploys to all clusters
├── argocd/
│   ├── appproject.yaml              # platform AppProject with sync windows
│   ├── kind-cluster-dev.yaml
│   └── kind-cluster-qa.yaml
├── terraform/                        # EKS cluster definitions
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
└── scripts/
    ├── bootstrap-kind.sh
    ├── bootstrap-eks.sh
    ├── teardown-kind.sh
    └── teardown-eks.sh
```

## Lab Exercises

### Exercise 1 — Verify multi-cluster deployment

```bash
# Dev should have 1 replica (canary strategy)
kubectl --context kind-cluster-dev get rollouts -n test-app
kubectl --context kind-cluster-dev get pods -n test-app

# QA should have 2 replicas (blue/green strategy)  
kubectl --context kind-cluster-qa get rollouts -n test-app
kubectl --context kind-cluster-qa get pods -n test-app

# Check rollout status with the plugin
kubectl argo rollouts --context kind-cluster-dev \
  get rollout test-app -n test-app --watch
```

---

### Exercise 2 — Trigger drift and watch self-heal

```bash
# Manually scale down dev
kubectl --context kind-cluster-dev scale deployment test-app \
  -n test-app --replicas=0

# Watch Argo CD revert it (within ~3 minutes or force refresh)
argocd app sync test-app-cluster-dev
kubectl --context kind-cluster-dev get pods -n test-app --watch
```

---

### Exercise 3 — Canary rollout on dev

```bash
# Bump the image tag in dev values to trigger a rollout
# Edit clusters/dev/values/test-app.yaml
# Change image.tag from "1.25" to "1.26"
git add . && git commit -m "bump dev to nginx 1.26" && git push

# Watch the canary progress
kubectl argo rollouts --context kind-cluster-dev \
  get rollout test-app -n test-app --watch

# You'll see:
# 20% weight on canary → pause 60s → 100% → complete
```

---

### Exercise 4 — Blue/Green rollout on QA with manual gate

```bash
# Promote dev image tag to QA values
# Edit clusters/qa/values/test-app.yaml
# Change image.tag from "1.24" to "1.25" (simulating a dev→qa promotion)
git add . && git commit -m "promote nginx 1.25 to qa" && git push

# Watch blue/green deploy — green stack comes up alongside blue
kubectl argo rollouts --context kind-cluster-qa \
  get rollout test-app -n test-app --watch

# Green is deployed but NOT promoted yet (autoPromotionEnabled: false)
# Manually inspect the preview service
kubectl --context kind-cluster-qa port-forward \
  svc/test-app-preview 8081:81 -n test-app &
curl http://localhost:8081  # hitting green stack

# Promote manually
kubectl argo rollouts --context kind-cluster-qa \
  promote test-app -n test-app

# Watch traffic switch to green, blue scales down after 120s
kubectl argo rollouts --context kind-cluster-qa \
  get rollout test-app -n test-app --watch
```

---

### Exercise 5 — Abort a bad rollout

```bash
# Deploy a deliberately bad image tag to dev
# Edit clusters/dev/values/test-app.yaml
# Change image.tag to "doesnotexist"
git add . && git commit -m "bad deploy" && git push

# Watch the rollout get stuck (ImagePullBackOff)
kubectl argo rollouts --context kind-cluster-dev \
  get rollout test-app -n test-app --watch

# Abort — traffic stays on stable
kubectl argo rollouts --context kind-cluster-dev \
  abort test-app -n test-app

# Rollback by reverting the values file
# Edit image.tag back to "1.26"
git add . && git commit -m "revert bad deploy" && git push
```

---

### Exercise 6 — Sync waves (multi-cluster ordered rollout)

```bash
# Update image tag in BOTH cluster values files simultaneously
# clusters/dev/values/test-app.yaml  → image.tag: "1.27"
# clusters/qa/values/test-app.yaml   → image.tag: "1.27"
git add . && git commit -m "roll 1.27 to all clusters" && git push

# Watch sync waves — dev (wave 1) syncs first, qa (wave 2) follows
# In Argo CD UI you'll see dev sync, complete, then qa sync begin
argocd app list --watch
```

---

### Exercise 7 — Sync window (simulated market hours block)

```bash
# The AppProject has a sync window blocking prod namespace
# during market hours (9:30am-4pm ET weekdays)
# Since we don't have a prod cluster, test it manually:

# Check current sync windows
argocd proj windows list platform

# Create a test app pointing at prod namespace to see it blocked
# Or temporarily edit appproject.yaml to use a current time window
# and observe the sync being queued
```

---

### Exercise 8 — Add a third cluster (stretch goal)

```bash
# kind
kind create cluster --name cluster-prod

# Register with Argo CD
argocd cluster add kind-cluster-prod --yes

# Add cluster directory
mkdir -p clusters/prod/values
cat > clusters/prod/cluster.yaml <<EOF
cluster:
  name: cluster-prod
  server: https://cluster-prod-control-plane:6443
  environment: prod
  region: us-east-1
  wave: "3"
  features:
    test-app: true
    rollouts: true
EOF

cat > clusters/prod/values/test-app.yaml <<EOF
replicaCount: 3
image:
  tag: "1.24"    # prod is behind — simulate controlled promotion
podLabels:
  tier: prod
rollout:
  strategy: blueGreen
  autoPromotionEnabled: false
  scaleDownDelaySeconds: 300    # keep blue warm 5 minutes in prod
EOF

git add . && git commit -m "add prod cluster" && git push

# ApplicationSet automatically creates test-app-cluster-prod
# No Argo CD config changes needed
argocd app list
```

---

## Useful Commands Reference

```bash
# Argo CD
argocd app list
argocd app sync <app-name>
argocd app diff <app-name>
argocd cluster list
argocd proj windows list platform

# Argo Rollouts
kubectl argo rollouts get rollout <name> -n <ns> --watch
kubectl argo rollouts promote <name> -n <ns>
kubectl argo rollouts abort <name> -n <ns>
kubectl argo rollouts undo <name> -n <ns>
kubectl argo rollouts set image <name> nginx=nginx:1.27 -n <ns>

# Switch contexts
kubectl config use-context kind-cluster-dev
kubectl config use-context kind-cluster-qa
kubectl config get-contexts

# Get Argo CD password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Restart port-forward
kubectl port-forward svc/argocd-server -n argocd 8080:443 &
```

## Teardown

```bash
# kind
./scripts/teardown-kind.sh

# EKS (important — avoids ongoing AWS charges)
./scripts/teardown-eks.sh
```
