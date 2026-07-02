#!/bin/bash
set -e

echo ">>> [Agent] Installing prerequisites..."
apt-get update -qq
apt-get install -y -qq curl

echo ">>> [Agent] Waiting for node token from server..."
until [ -f "${NODE_TOKEN}" ]; do
  echo "    token not yet available, sleeping 5s..."
  sleep 5
done

TOKEN=$(cat "${NODE_TOKEN}")

echo ">>> [Agent] Installing K3s in agent mode..."
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="agent \
  --server=https://${SERVER_IP}:6443 \
  --token=${TOKEN} \
  --node-ip=$(hostname -I | awk '{print $2}') \
  --flannel-iface=eth1" sh -

echo ">>> [Agent] K3s agent started and joined the cluster."
