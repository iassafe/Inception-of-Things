#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✓ $1${NC}"; }
info() { echo -e "${YELLOW}► $1${NC}"; }
err()  { echo -e "${RED}✗ $1${NC}"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DROPLET_IP=$(curl -s ifconfig.me)
GITHUB_USER="iassafe"
GITHUB_REPO="iassafe-inception-of-things"
GITHUB_EMAIL="ikrameassafe17@gmail.com"

echo "======================================"
echo "   P3 — K3d + Argo CD + GitOps"
echo "======================================"

# Prerequisites
for tool in docker kubectl k3d git; do
    command -v $tool &>/dev/null || err "$tool not found. Run install.sh first."
done
ok "All tools present"

# [1/5] K3d cluster
info "Creating K3d cluster..."
k3d cluster list | grep -q "iot-cluster" && k3d cluster delete iot-cluster
k3d cluster create iot-cluster \
    --port "8888:30080@server:0" \
    --wait
ok "Cluster ready"

# [2/5] Namespaces
info "Creating namespaces..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace dev    --dry-run=client -o yaml | kubectl apply -f -
ok "Namespaces ready"

# [3/5] Argo CD
info "Installing Argo CD..."
kubectl apply --server-side -n argocd \
    -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" | base64 -d)
ok "Argo CD ready"

# [4/5] Push manifests to GitHub
info "Syncing manifests to GitHub..."
REPO_DIR="${HOME}/${GITHUB_REPO}"
[ ! -d "$REPO_DIR" ] && git clone "git@github.com:${GITHUB_USER}/${GITHUB_REPO}.git" "$REPO_DIR"

cd "$REPO_DIR"
git config user.name "$GITHUB_USER"
git config user.email "$GITHUB_EMAIL"
mkdir -p p3/confs
cp "${SCRIPT_DIR}/../confs/deployment.yaml" p3/confs/deployment.yaml
git add p3/confs/deployment.yaml
if ! git diff --cached --quiet; then
    git commit -m "P3: update deployment manifest"
    git push -u origin main
fi
cd "${SCRIPT_DIR}"
ok "Manifests pushed to GitHub"

# [5/5] Apply Argo CD Application
info "Applying Argo CD Application..."
kubectl apply -f "${SCRIPT_DIR}/../confs/argocd-app.yaml"

# Wait for deployment to appear
until kubectl get deployment playground -n dev &>/dev/null; do sleep 2; done

# Argo CD UI via port-forward
pkill -f "kubectl port-forward.*argocd" 2>/dev/null || true
nohup kubectl port-forward svc/argocd-server -n argocd 8080:443 \
    --address 0.0.0.0 >/tmp/argocd.log 2>&1 &
ok "Argo CD Application applied"

# Wait for app to respond
info "Waiting for app..."
for i in {1..30}; do
    if curl -s "http://localhost:8888/" 2>/dev/null | grep -q "v1"; then
        ok "App is responding!"
        curl -s "http://localhost:8888/"
        echo ""
        break
    fi
    [ $i -eq 30 ] && echo -e "${YELLOW}App still syncing. Check: kubectl get pods -n dev${NC}"
    echo -n "."
    sleep 5
done

echo ""
echo "======================================"
ok "Setup Complete!"
echo "======================================"
echo ""
echo "  App    : http://${DROPLET_IP}:8888/"
echo "  ArgoCD : http://${DROPLET_IP}:8080"
echo "  Login  : admin / ${ARGOCD_PASSWORD}"
echo ""
