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
GITLAB_PORT=8181
ARGOCD_PORT=8080

echo "======================================"
echo "   Bonus — GitLab + Argo CD + GitOps"
echo "======================================"

# Prerequisites
for tool in docker kubectl k3d helm git; do
    command -v $tool &>/dev/null || err "$tool not found. Run install.sh first."
done
ok "All tools present"

# [1/7] K3d cluster
info "Creating K3d cluster..."
k3d cluster list | grep -q "iot-cluster" && k3d cluster delete iot-cluster
k3d cluster create iot-cluster \
    --port "8888:30080@server:0" \
    --port "30022:30022@server:0" \
    --wait
sleep 10
ok "Cluster ready"

# [2/7] Namespaces
info "Creating namespaces..."
for ns in argocd gitlab dev; do
    kubectl create namespace $ns --dry-run=client -o yaml | kubectl apply -f -
done
ok "Namespaces ready"

# [3/7] Argo CD
info "Installing Argo CD..."
kubectl apply -n argocd \
    -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml || true
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" | base64 -d)
ok "Argo CD ready"

# [4/7] GitLab
info "Installing GitLab (10-15 min)..."
helm repo add gitlab https://charts.gitlab.io/ 2>/dev/null || true
helm repo update
if ! helm list -n gitlab 2>/dev/null | grep -q "gitlab"; then
    helm install gitlab gitlab/gitlab \
        --version 9.11.7 \
        --namespace gitlab \
        --timeout 900s \
        --set global.hosts.externalIP=$DROPLET_IP \
        --set certmanager-issuer.email=ikrameassafe17@gmail.com \
        --set gitlab.webservice.puma.workers=0 \
        -f "${SCRIPT_DIR}/../confs/gitlab-values.yaml"
fi
info "Waiting for GitLab webservice..."
kubectl wait --for=condition=ready pod -l app=webservice \
    -n gitlab --timeout=900s 2>/dev/null || info "Still starting, continuing..."
ok "GitLab installed"

# [5/7] Port-forwards
info "Starting port-forwards..."
pkill -f "kubectl port-forward" 2>/dev/null || true
sleep 2
kubectl port-forward -n gitlab svc/gitlab-webservice-default \
    $GITLAB_PORT:8181 --address 0.0.0.0 >/tmp/gitlab-pf.log 2>&1 &
kubectl port-forward svc/argocd-server -n argocd \
    $ARGOCD_PORT:80 --address 0.0.0.0 >/tmp/argocd-pf.log 2>&1 &
sleep 5
ok "Port-forwards started"

# [6/7] GitLab project setup
info "Waiting for GitLab to be ready..."
for i in {1..60}; do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
        "http://localhost:${GITLAB_PORT}/users/sign_in" 2>/dev/null)
    [ "$STATUS" = "200" ] && info "GitLab is ready!" && break
    [ $i -eq 60 ] && info "GitLab taking longer than expected, continuing anyway..."
    echo -n "."
    sleep 10
done
echo ""

GITLAB_PASSWORD=$(kubectl get secret gitlab-gitlab-initial-root-password \
    -n gitlab -o jsonpath='{.data.password}' | base64 --decode)

info "Waiting for Rails to be ready..."
for i in $(seq 1 20); do
    kubectl exec -n gitlab deploy/gitlab-toolbox -- \
        gitlab-rails runner "puts 'ok'" &>/dev/null && break
    echo -n "."
    sleep 15
done
echo ""

info "Creating GitLab API token..."
GITLAB_TOKEN=$(kubectl exec -n gitlab deploy/gitlab-toolbox -- \
    gitlab-rails runner "
    begin
      user = User.find_by_username('root')
      existing = user.personal_access_tokens.active.find_by_name('argocd-token')
      if existing
        puts existing.token
      else
        token = user.personal_access_tokens.create!(
          name: 'argocd-token',
          scopes: [:api, :read_repository, :write_repository],
          expires_at: 1.year.from_now
        )
        puts token.token
      end
    rescue => e
      STDERR.puts 'ERROR: ' + e.message
      exit 1
    end
" 2>/dev/null | tail -1)
info "Token: ${GITLAB_TOKEN:0:10}..."

info "Creating GitLab project 'iassafe'..."
curl -s -X POST "http://localhost:${GITLAB_PORT}/api/v4/projects" \
    --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
    --header "Content-Type: application/json" \
    --data '{"name": "iassafe", "visibility": "public"}' >/dev/null || true

info "Pushing app to GitLab..."
REPO_DIR="${HOME}/iassafe-app"
mkdir -p "${REPO_DIR}/app"

cat > "${REPO_DIR}/app/deployment.yaml" << 'APPEOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: playground
  namespace: dev
  labels:
    app: playground
spec:
  replicas: 1
  selector:
    matchLabels:
      app: playground
  template:
    metadata:
      labels:
        app: playground
    spec:
      containers:
      - name: playground
        image: wil42/playground:v1
        ports:
        - containerPort: 8888
---
apiVersion: v1
kind: Service
metadata:
  name: playground-svc
  namespace: dev
spec:
  type: NodePort
  selector:
    app: playground
  ports:
  - port: 8888
    targetPort: 8888
    nodePort: 30080
APPEOF

cd "${REPO_DIR}"
git init 2>/dev/null || true
git config user.name "root"
git config user.email "ikrameassafe17@gmail.com"
git remote remove gitlab 2>/dev/null || true
git remote add gitlab \
    "http://root:${GITLAB_TOKEN}@localhost:${GITLAB_PORT}/root/iassafe.git"
git checkout -B main 2>/dev/null || true
git add .
git commit -m "Initial commit: playground app" 2>/dev/null || true

for attempt in {1..5}; do
    git push gitlab main --force && break || {
        info "Push failed (attempt $attempt/5), retrying in 30s..."
        sleep 30
    }
done
cd "${SCRIPT_DIR}"
ok "GitLab project ready"

# [7/7] Argo CD Application
info "Applying Argo CD Application..."
kubectl apply -f "${SCRIPT_DIR}/../confs/argocd.yaml"
sleep 15
kubectl get applications -n argocd
ok "Argo CD Application applied"

# Verify app
info "Waiting for app to respond..."
for i in {1..30}; do
    if curl -s "http://localhost:8888/" 2>/dev/null | grep -q "v1"; then
        ok "App is responding!"
        curl -s "http://localhost:8888/"
        echo ""
        break
    fi
    [ $i -eq 30 ] && echo -e "${YELLOW}⚠ App still syncing. Check: kubectl get pods -n dev${NC}"
    echo -n "."
    sleep 5
done

echo ""
echo "======================================"
ok "Setup Complete!"
echo "======================================"
echo ""
echo "  GitLab : http://${DROPLET_IP}:${GITLAB_PORT}  (root / ${GITLAB_PASSWORD})"
echo "  ArgoCD : http://${DROPLET_IP}:${ARGOCD_PORT}  (admin / ${ARGOCD_PASSWORD})"
echo "  App    : curl http://${DROPLET_IP}:8888/"
echo ""
