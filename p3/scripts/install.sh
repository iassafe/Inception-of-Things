#!/bin/bash

set -e

echo "=========================================="
echo "           Tools Installation             "
echo "=========================================="

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}[1/4] Checking Docker...${NC}"
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
fi
echo -e "${GREEN}✓ Docker${NC}"

echo -e "${YELLOW}[2/4] Checking kubectl...${NC}"
if ! command -v kubectl &> /dev/null; then
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm kubectl
fi
echo -e "${GREEN}✓ kubectl${NC}"

echo -e "${YELLOW}[3/4] Checking k3d...${NC}"
if ! command -v k3d &> /dev/null; then
    curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
fi
echo -e "${GREEN}✓ k3d${NC}"

echo -e "${YELLOW}[4/4] Checking Git...${NC}"
if ! command -v git &> /dev/null; then
    apt-get update -qq
    apt-get install -y -qq git
fi
echo -e "${GREEN}✓ Git${NC}"

echo ""
echo "All tools installed!"
