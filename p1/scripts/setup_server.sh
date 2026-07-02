#!/bin/bash
set -e

echo ">>> [Server] Installing prerequisites..."
apt-get update -qq
apt-get install -y -qq curl

echo ">>> [Server] Installing K3s in controller mode..."
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
  --bind-address=${SERVER_IP} \
  --advertise-address=${SERVER_IP} \
  --node-ip=${SERVER_IP} \
  --flannel-iface=eth1" sh -

echo ">>> [Server] Waiting for K3s to be ready..."
until kubectl get nodes 2>/dev/null | grep -q "Ready"; do
  sleep 3
done

echo ">>> [Server] Sharing node token for the agent..."
mkdir -p "$(dirname "${NODE_TOKEN}")"
cp /var/lib/rancher/k3s/server/node-token "${NODE_TOKEN}"
chmod 644 "${NODE_TOKEN}"

echo ">>> [Server] Making kubeconfig accessible to vagrant user..."
mkdir -p /home/vagrant/.kube
cp /etc/rancher/k3s/k3s.yaml /home/vagrant/.kube/config
sed -i "s/127.0.0.1/${SERVER_IP}/g" /home/vagrant/.kube/config
chown -R vagrant:vagrant /home/vagrant/.kube

echo ">>> [Server] Done. Nodes:"
kubectl get nodes -o wide
