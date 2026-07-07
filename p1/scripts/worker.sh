#!/bin/bash

# worker IP, server IP, and location of the shared join token
IP="192.168.56.111"
SERVER_IP="192.168.56.110"
TOKEN_FILE="/vagrant/confs/node-token"

# update package lists and install curl
apt-get update -y
apt-get install -y curl

# wait until the server creates the join token before attempting to join
while [ ! -f "$TOKEN_FILE" ]
do
    sleep 2
done

# read the join token
TOKEN=$(cat "$TOKEN_FILE")

# install the K3s agent and join the cluster using the server's IP and the join token
curl -sfL https://get.k3s.io | \
K3S_URL="https://$SERVER_IP:6443" \
K3S_TOKEN="$TOKEN" \
sh -s - agent \
    --node-ip="$IP" 

echo "------------------------------------------------------------------------------------------------------------"
echo "K3s worker node successfully joined the cluster"
echo "------------------------------------------------------------------------------------------------------------"
