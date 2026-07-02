#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}[1/5] Docker...${NC}"
command -v docker || curl -fsSL https://get.docker.com | sh
echo -e "${GREEN}✓ Docker${NC}"

echo -e "${YELLOW}[2/5] kubectl...${NC}"
if ! command -v kubectl &> /dev/null; then
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm kubectl
fi
echo -e "${GREEN}✓ kubectl${NC}"

echo -e "${YELLOW}[3/5] k3d...${NC}"
command -v k3d || curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
echo -e "${GREEN}✓ k3d${NC}"

echo -e "${YELLOW}[4/5] Helm...${NC}"
command -v helm || curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
echo -e "${GREEN}✓ Helm${NC}"

echo -e "${YELLOW}[5/5] Git...${NC}"
command -v git || apt-get install -y -qq git
echo -e "${GREEN}✓ Git${NC}"

echo ""
echo "All tools installed!"
