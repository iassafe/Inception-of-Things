#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✓ $1${NC}"; }
info() { echo -e "${YELLOW}► $1${NC}"; }

echo "======================================"
echo "   Bonus — Tools Installation"
echo "======================================"

info "Docker..."
command -v docker &>/dev/null || curl -fsSL https://get.docker.com | sh
ok "Docker"

info "kubectl..."
if ! command -v kubectl &>/dev/null; then
    curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm kubectl
fi
ok "kubectl"

info "k3d..."
command -v k3d &>/dev/null || curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
ok "k3d"

info "Helm..."
command -v helm &>/dev/null || curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
ok "Helm"

info "Git..."
command -v git &>/dev/null || apt-get install -y -qq git
ok "Git"

echo ""
ok "All tools installed!"
