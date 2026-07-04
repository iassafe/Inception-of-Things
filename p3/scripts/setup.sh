#!/bin/bash

set -e

echo "=========================================="
echo "   K3d + Argo CD + GitOps Setup (P3)      "
echo "=========================================="

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DROPLET_IP=$(curl -s ifconfig.me)

GITHUB_USER="iassafe"
GITHUB_REPO="iassafe-inception-of-things"
GITHUB_EMAIL="ikrameassafe17@gmail.com"

# Prerequisites
for tool in docker kubectl k3d git; do
    if ! command -v $tool &> /dev/null; then
        print_error "$tool missing. Run install-tools.sh first."
        exit 1
    fi
done
echo -e "${GREEN}✓ All tools present${NC}"

# [1/6] K3d cluster
echo -e "${YELLOW}[1/6] K3d cluster...${NC}"
if k3d cluster list | grep -q "iot-cluster"; then
    k3d cluster delete iot-cluster
fi
k3d cluster create iot-cluster \
    --port "8888:30080@server:0" \
    --wait
sleep 10
echo -e "${GREEN}✓ Cluster ready${NC}"

# [2/6] Namespaces
echo -e "${YELLOW}[2/6] Namespaces...${NC}"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace dev    --dry-run=client -o yaml | kubectl apply -f -
echo -e "${GREEN}✓ Namespaces created${NC}"

# [3/6] Argo CD
echo -e "${YELLOW}[3/6] Argo CD...${NC}"
kubectl apply --server-side -n argocd \
    -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=available --timeout=300s \
    deployment/argocd-server -n argocd
echo -e "${GREEN}✓ Argo CD ready${NC}"

# [4/6] Credentials
echo -e "${YELLOW}[4/6] Retrieving Argo CD admin password...${NC}"
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" | base64 -d)
echo -e "${GREEN}✓ Credentials retrieved${NC}"

# [5/6] Push deployment.yaml to GitHub (public repo, no token needed for ArgoCD)
echo -e "${YELLOW}[5/6] Pushing app files to GitHub...${NC}"

REPO_DIR="${HOME}/${GITHUB_REPO}"

if [ ! -d "$REPO_DIR" ]; then
    print_info "Cloning repo..."
    git clone "git@github.com:${GITHUB_USER}/${GITHUB_REPO}.git" "$REPO_DIR"
fi

cd "$REPO_DIR"
git config user.name "$GITHUB_USER"
git config user.email "$GITHUB_EMAIL"

mkdir -p p3/confs
cp "${SCRIPT_DIR}/../confs/deployment.yaml" p3/confs/deployment.yaml

git checkout -B main 2>/dev/null || true
git add p3/confs/deployment.yaml

if ! git diff --cached --quiet; then
    git commit -m "P3: add deployment manifest"
    print_info "Pushing to GitHub..."
    git push -u origin main
    print_info "Push successful!"
else
    print_info "No changes to push, deployment.yaml already up to date."
fi

cd "${SCRIPT_DIR}"
echo -e "${GREEN}✓ App files pushed to GitHub${NC}"

# [6/6] Apply Argo CD Application
echo -e "${YELLOW}[6/6] Applying Argo CD Application...${NC}"

kubectl apply -f "${SCRIPT_DIR}/../confs/argocd-app.yaml"

echo "Waiting for application deployment..."

until kubectl get deployment playground -n dev >/dev/null 2>&1; do
    sleep 2
done

echo "Waiting for Argo CD server..."

kubectl wait \
    --for=condition=Ready \
    pod \
    -l app.kubernetes.io/name=argocd-server \
    -n argocd \
    --timeout=600s

kubectl get applications -n argocd

echo -e "${GREEN}✓ Argo CD Application applied${NC}"

# Start Argo CD port-forward only if port 8080 is free
if ! ss -ltn | grep -q ":8080 "; then
    print_info "Starting Argo CD on port 8080..."
    nohup kubectl port-forward svc/argocd-server \
        -n argocd \
        8080:443 \
        --address 0.0.0.0 \
        >/tmp/argocd.log 2>&1 &
    sleep 5
else
    print_warning "Port 8080 is already in use. Skipping port-forward."
fi

echo ""
echo "================================================"
echo -e "${GREEN}Setup Complete!${NC}"
echo "================================================"
echo ""

echo "Application:"
echo "  curl http://${DROPLET_IP}:8888/"
echo ""

echo "Argo CD:"
echo "  http://${DROPLET_IP}:8080"
echo ""

echo "Login:"
echo "  Username: admin"
echo "  Password: ${ARGOCD_PASSWORD}"
echo ""

print_info "Waiting for app to be ready..."
for i in {1..30}; do
    if curl -s "http://localhost:8888/" 2>/dev/null | grep -q "v1"; then
        echo -e "${GREEN}✓ App is responding!${NC}"
        curl -s "http://localhost:8888/"
        break
    fi
    if [ $i -eq 30 ]; then
        print_warning "App may still be syncing. Try: kubectl get pods -n dev"
    fi
    echo -n "."
    sleep 5
done

echo ""
echo -e "${GREEN}Done!${NC}"
