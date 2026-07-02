#!/bin/bash
set -e

echo ">>> Installing prerequisites..."
command -v curl >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y -qq curl; }

echo ">>> Installing K3s in controller mode..."
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
  --bind-address=${SERVER_IP} \
  --advertise-address=${SERVER_IP} \
  --node-ip=${SERVER_IP} \
  --flannel-iface=eth1" sh -

echo ">>> Waiting for K3s to be ready..."
until kubectl get nodes 2>/dev/null | grep -q "Ready"; do
  sleep 3
done

echo ">>> Making kubeconfig accessible to vagrant user..."
mkdir -p /home/vagrant/.kube
cp /etc/rancher/k3s/k3s.yaml /home/vagrant/.kube/config
sed -i "s/127.0.0.1/${SERVER_IP}/g" /home/vagrant/.kube/config
chown -R vagrant:vagrant /home/vagrant/.kube

echo ">>> Waiting for Traefik (built-in ingress) to be ready..."
until kubectl get pods -n kube-system 2>/dev/null | grep traefik | grep -q "Running"; do
  sleep 3
done

echo ">>> Applying app manifests..."
kubectl apply -f /vagrant/confs/

echo ">>> Done. Current state:"
kubectl get nodes -o wide
kubectl get pods -o wide
kubectl get ingress