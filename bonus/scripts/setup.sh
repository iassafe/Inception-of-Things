#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DROPLET_IP=$(curl -s ifconfig.me)

echo "=========================================="
echo "   K3d + GitLab + Argo CD Setup"
echo "=========================================="

# Prerequisites check
for tool in docker kubectl k3d helm git; do
    if ! command -v $tool &> /dev/null; then
        echo -e "${RED}✗ $tool missing. Run install-tools.sh first.${NC}"
        exit 1
    fi
done
echo -e "${GREEN}✓ All tools present${NC}"

# [1/8] K3d cluster
echo -e "${YELLOW}[1/8] K3d cluster...${NC}"
if k3d cluster list | grep -q "iot-cluster"; then
    k3d cluster delete iot-cluster
fi
k3d cluster create iot-cluster \
    --port "8888:30080@server:0" \
    --port "30080:30080@server:0" \
    --port "30022:30022@server:0" \
    --wait
sleep 10
echo -e "${GREEN}✓ Cluster ready${NC}"

# [2/8] Namespaces
echo -e "${YELLOW}[2/8] Namespaces...${NC}"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace gitlab  --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace dev     --dry-run=client -o yaml | kubectl apply -f -
echo -e "${GREEN}✓ Namespaces created${NC}"

# [3/8] Argo CD
echo -e "${YELLOW}[3/8] Argo CD...${NC}"
kubectl apply -n argocd \
    -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml || true
kubectl wait --for=condition=available --timeout=300s \
    deployment/argocd-server -n argocd
echo -e "${GREEN}✓ Argo CD ready${NC}"

# [4/8] GitLab
echo -e "${YELLOW}[4/8] GitLab (10-15 min)...${NC}"
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
else
    print_warning "GitLab already installed, skipping..."
fi
print_info "Waiting for GitLab webservice..."
kubectl wait --for=condition=ready pod \
    -l app=webservice -n gitlab --timeout=900s 2>/dev/null || \
    print_warning "Still starting, continuing anyway..."
echo -e "${GREEN}✓ GitLab installed${NC}"

# [5/8] Port-forwards
echo -e "${YELLOW}[5/8] Port-forwards...${NC}"
pkill -f "kubectl port-forward.*gitlab"  2>/dev/null || true
pkill -f "kubectl port-forward.*argocd"  2>/dev/null || true
sleep 2
GITLAB_LOCAL_PORT=8181
ARGOCD_LOCAL_PORT=8080
kubectl port-forward -n gitlab svc/gitlab-webservice-default \
    $GITLAB_LOCAL_PORT:8181 --address 0.0.0.0 \
    > /tmp/gitlab-pf.log 2>&1 &
GITLAB_PF_PID=$!
kubectl port-forward svc/argocd-server -n argocd \
    $ARGOCD_LOCAL_PORT:80 --address 0.0.0.0 \
    > /tmp/argocd-pf.log 2>&1 &
ARGOCD_PF_PID=$!
sleep 5
echo -e "${GREEN}✓ Port-forwards started${NC}"

# [6/8] Credentials
echo -e "${YELLOW}[6/8] Credentials...${NC}"
sleep 5
GITLAB_PASSWORD=$(kubectl get secret gitlab-gitlab-initial-root-password \
    -n gitlab -o jsonpath='{.data.password}' | base64 --decode)
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" | base64 -d)
echo -e "${GREEN}✓ Credentials retrieved${NC}"

# [7/8] GitLab project + push
echo -e "${YELLOW}[7/8] GitLab project setup...${NC}"
print_info "Waiting for GitLab to accept requests..."
for i in {1..30}; do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
        "http://localhost:${GITLAB_LOCAL_PORT}/users/sign_in")
    [ "$STATUS" = "200" ] && print_info "GitLab ready!" && break
    echo -n "."
    sleep 10
done
echo ""

print_info "Waiting for toolbox Rails to be ready..."
for i in $(seq 1 20); do
    kubectl exec -n gitlab deploy/gitlab-toolbox -- gitlab-rails runner "puts 'ok'" &>/dev/null && break
    echo -n "."
    sleep 15
done
echo ""
print_info "Creating API token via Rails runner..."
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
      STDERR.puts \"ERROR: #{e.message}\"
      exit 1
    end
" 2>/dev/null | tail -1)
print_info "Token: ${GITLAB_TOKEN:0:10}..."

print_info "Creating project 'iassafe'..."
curl -s -X POST "http://localhost:${GITLAB_LOCAL_PORT}/api/v4/projects" \
    --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
    --header "Content-Type: application/json" \
    --data '{"name": "iassafe", "visibility": "public"}' > /dev/null || \
    print_warning "Project may already exist"

print_info "Preparing app repository..."
IOT_REPO_DIR="${HOME}/iassafe-app"
mkdir -p "${IOT_REPO_DIR}/app"

cat > "${IOT_REPO_DIR}/app/deployment.yaml" << 'APPEOF'
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

cd "${IOT_REPO_DIR}"
git init 2>/dev/null || true
git config user.name "root"
git config user.email "ikrameassafe17@gmail.com"
if git remote | grep -q "gitlab"; then
    git remote set-url gitlab \
        "http://root:${GITLAB_TOKEN}@localhost:${GITLAB_LOCAL_PORT}/root/iassafe.git"
else
    git remote add gitlab \
        "http://root:${GITLAB_TOKEN}@localhost:${GITLAB_LOCAL_PORT}/root/iassafe.git"
fi
git checkout -B main 2>/dev/null || true
git add .
git commit -m "Initial commit: playground app" 2>/dev/null || true
print_info "Pushing to GitLab..."
git push gitlab main --force
print_info "Push successful!"
cd "${SCRIPT_DIR}"
echo -e "${GREEN}✓ GitLab project ready${NC}"

# [8/8] Argo CD Application
echo -e "${YELLOW}[8/8] Applying Argo CD Application...${NC}"
kubectl apply -f "${SCRIPT_DIR}/../confs/argocd.yaml"
sleep 15
kubectl get applications -n argocd
echo -e "${GREEN}✓ Argo CD Application applied${NC}"

# Summary
echo ""
echo "================================================"
echo -e "${GREEN}Setup Complete!${NC}"
echo "================================================"
echo ""
echo "GitLab  : http://${DROPLET_IP}:${GITLAB_LOCAL_PORT}  (root / ${GITLAB_PASSWORD})"
echo "ArgoCD  : http://${DROPLET_IP}:${ARGOCD_LOCAL_PORT}  (admin / ${ARGOCD_PASSWORD})"
echo "App     : curl http://${DROPLET_IP}:8888/"
echo ""

sleep 5
if curl -s "http://localhost:8888/" 2>/dev/null | grep -q "v1"; then
    echo -e "${GREEN}✓ App is responding!${NC}"
    curl -s "http://localhost:8888/"
else
    echo -e "${YELLOW}⚠ App may need more time. Check: kubectl get pods -n dev${NC}"
fi
echo ""
echo -e "${GREEN}Done!${NC}"
