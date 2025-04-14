#!/bin/bash

# Install root CA so that it's trusted by the local system and browsers
mkcert -install

# Create a kubernetes cluster
minikube start --cpus 4 --memory 8192 --addons metallb storage-provisioner default-storageclass

# TODO: configure the ingress addon in the same way as installing ingress-nginx with Helm with:
# --set allowSnippetAnnotations=true
# --set controller.service.externalTrafficPolicy=Local
# TODO: install with Helm instead of the ingress addon

# Install Cert-Manager
helm repo add jetstack https://charts.jetstack.io --force-update
helm install \
  cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.16.1 \
  --set crds.enabled=true

# Wait for Cert-Manager to be ready
kubectl wait --for=condition=available --namespace cert-manager deployment/cert-manager-webhook --timeout=120s

# Generate a secret from the key pair of the root CA. It will be used to create a "CA" ClusterIssuer
kubectl create secret tls cluster-issuer-ca-key-pair \
--key "$(mkcert -CAROOT)"/rootCA-key.pem \
--cert "$(mkcert -CAROOT)"/rootCA.pem -n cert-manager

# Install Nginx ingress
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx --force-update
helm install ingress-nginx ingress-nginx/ingress-nginx -n ingress-nginx \
    --set controller.service.externalTrafficPolicy=Local \
    --set allowSnippetAnnotations=true \
    --create-namespace

# Install Astarte operator
helm repo add astarte https://helm.astarte-platform.org --force-update
helm install astarte-operator astarte/astarte-operator -n astarte-operator --create-namespace

# Use DNS records that resolve to minikube IP
export ASTARTE_API_HOST="api.astarte.$(minikube ip).nip.io"
export ASTARTE_VERNEMQ_HOST="vernemq.astarte.$(minikube ip).nip.io"
export ASTARTE_DASHBOARD_HOST="dashboard.astarte.$(minikube ip).nip.io"

# Run skaffold for local development
skaffold dev
