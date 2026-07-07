#!/bin/bash

# server configuration variables
# ----------------------------------------------------------------------------------------------------------------
IP="$1"

# Update package lists and install curl
apt-get update -y
apt-get install -y curl

# Install K3s server
curl -sfL https://get.k3s.io | sh -s - server --node-ip="$IP" --write-kubeconfig-mode=644

# Wait until the server node reaches the Ready state
kubectl wait --for=condition=Ready node --all --timeout=180s

echo "-------------------------------------------------------------------------------------------------------------"
echo "K3s server is ready"
echo "-------------------------------------------------------------------------------------------------------------"
