#!/bin/bash
#
# troubleshoot.sh - Diagnostic script for n8n deployment
# Usage: ./troubleshoot.sh YOUR_PROJECT_ID

set -e

if [ -z "$1" ]; then
  echo "Usage: $0 PROJECT_ID"
  echo "Example: $0 my-gcp-project"
  exit 1
fi

PROJECT_ID="$1"
INSTANCE_NAME="n8n-postgres"
CLUSTER_NAME="n8n-gke"
ZONE="europe-north1-a"

echo "=== n8n Deployment Troubleshooting ==="
echo ""

# Check if secrets exist in Secret Manager
echo "1. Checking GCP Secret Manager..."
if gcloud secrets describe n8n-encryption-key --project=$PROJECT_ID &>/dev/null; then
  echo "   ✓ n8n-encryption-key exists"
else
  echo "   ✗ n8n-encryption-key NOT FOUND"
  echo "     Create it: echo -n \"\$(openssl rand -hex 32)\" | gcloud secrets create n8n-encryption-key --data-file=- --project=$PROJECT_ID"
fi

if gcloud secrets describe n8n-db-password --project=$PROJECT_ID &>/dev/null; then
  echo "   ✓ n8n-db-password exists"
else
  echo "   ✗ n8n-db-password NOT FOUND"
  echo "     Create it: echo -n \"your-secure-password\" | gcloud secrets create n8n-db-password --data-file=- --project=$PROJECT_ID"
fi
echo ""

# Check if database user exists
echo "2. Checking Cloud SQL database user..."
if gcloud sql users list --instance=$INSTANCE_NAME --project=$PROJECT_ID 2>/dev/null | grep -q "^n8n"; then
  echo "   ✓ Database user 'n8n' exists"
else
  echo "   ✗ Database user 'n8n' NOT FOUND"
  echo "     This is the MOST COMMON issue!"
  echo "     Create it: gcloud sql users create n8n --instance=$INSTANCE_NAME --password=\"your-secure-password\" --project=$PROJECT_ID"
fi
echo ""

# Check if gke-gcloud-auth-plugin is installed
echo "3. Checking gke-gcloud-auth-plugin..."
if command -v gke-gcloud-auth-plugin &>/dev/null; then
  echo "   ✓ gke-gcloud-auth-plugin is installed"
else
  echo "   ✗ gke-gcloud-auth-plugin NOT FOUND"
  echo "     Install it: gcloud components install gke-gcloud-auth-plugin"
fi
echo ""

# Get cluster credentials
echo "4. Getting cluster credentials..."
if gcloud container clusters get-credentials $CLUSTER_NAME --zone $ZONE --project $PROJECT_ID &>/dev/null; then
  echo "   ✓ Cluster credentials retrieved"
else
  echo "   ✗ Could not get cluster credentials"
  echo "     Check if cluster exists: gcloud container clusters list --project=$PROJECT_ID"
fi
echo ""

# Check pod status
echo "5. Checking n8n pod status..."
export USE_GKE_GCLOUD_AUTH_PLUGIN=True
POD_STATUS=$(kubectl get pods -n n8n -l app.kubernetes.io/name=n8n -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Not found")
if [ "$POD_STATUS" = "Running" ]; then
  echo "   ✓ n8n pod is Running"
elif [ "$POD_STATUS" = "Not found" ]; then
  echo "   ✗ n8n pod not found"
  echo "     Check if Helm release was created: kubectl get all -n n8n"
else
  echo "   ✗ n8n pod status: $POD_STATUS"
  echo "     Check logs: kubectl logs -n n8n -l app.kubernetes.io/name=n8n --tail=50"
fi
echo ""

# Check ExternalSecrets
echo "6. Checking ExternalSecrets..."
if kubectl get externalsecret n8n-keys -n n8n &>/dev/null; then
  SECRET_STATUS=$(kubectl get externalsecret n8n-keys -n n8n -o jsonpath='{.status.conditions[0].status}' 2>/dev/null)
  if [ "$SECRET_STATUS" = "True" ]; then
    echo "   ✓ ExternalSecret n8n-keys is synced"
  else
    echo "   ✗ ExternalSecret n8n-keys is not synced"
    echo "     Check status: kubectl describe externalsecret n8n-keys -n n8n"
  fi
else
  echo "   ✗ ExternalSecret n8n-keys not found"
fi

if kubectl get externalsecret n8n-db -n n8n &>/dev/null; then
  SECRET_STATUS=$(kubectl get externalsecret n8n-db -n n8n -o jsonpath='{.status.conditions[0].status}' 2>/dev/null)
  if [ "$SECRET_STATUS" = "True" ]; then
    echo "   ✓ ExternalSecret n8n-db is synced"
  else
    echo "   ✗ ExternalSecret n8n-db is not synced"
    echo "     Check status: kubectl describe externalsecret n8n-db -n n8n"
  fi
else
  echo "   ✗ ExternalSecret n8n-db not found"
fi
echo ""

# Check LoadBalancer service
echo "7. Checking LoadBalancer service..."
EXTERNAL_IP=$(kubectl get svc n8n -n n8n -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
if [ -n "$EXTERNAL_IP" ]; then
  echo "   ✓ LoadBalancer IP: $EXTERNAL_IP"
  echo "   Access n8n at: http://$EXTERNAL_IP:5678"
else
  echo "   ✗ LoadBalancer IP not assigned yet"
  echo "     Wait a few minutes and check: kubectl get svc -n n8n"
fi
echo ""

echo "=== Troubleshooting Summary ==="
echo "If n8n is not working, the most common issues are:"
echo "  1. Database user 'n8n' doesn't exist (see step 2)"
echo "  2. Secrets not created in Secret Manager (see step 1)"
echo "  3. gke-gcloud-auth-plugin not installed (see step 3)"
echo ""
echo "For more help, see: n8n/README.md#troubleshooting"
