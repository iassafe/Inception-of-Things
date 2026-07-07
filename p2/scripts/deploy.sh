#!/bin/bash

# Deploy the application manifests
kubectl apply -f /vagrant/confs/app1.yaml
kubectl apply -f /vagrant/confs/app2.yaml
kubectl apply -f /vagrant/confs/app3.yaml
kubectl apply -f /vagrant/confs/ingress.yaml

# Wait until all application Pods are Ready
echo "Waiting for all Pods to become Ready..."
kubectl wait --for=condition=Ready pods --all --timeout=180s

# Display the current state of the cluster
echo
echo "-------------------------------------------------------------------------------------------------------------"
echo "Current cluster status"
echo "-------------------------------------------------------------------------------------------------------------"
echo
echo "Nodes"
kubectl get nodes -o wide
echo "Pods"
kubectl get pods -o wide
echo
echo "Services"
kubectl get services -o wide
echo
echo "Ingress"
kubectl get ingress -o wide

# Display example commands to test the applications
echo
echo "-------------------------------------------------------------------------------------------------------------"
echo "Deployment completed successfully"
echo "-------------------------------------------------------------------------------------------------------------"
echo "Test the applications with:"
echo
echo 'curl -H "Host: app1.com" http://192.168.56.110'
echo 'curl -H "Host: app2.com" http://192.168.56.110'
echo 'curl http://192.168.56.110'
echo "-------------------------------------------------------------------------------------------------------------"