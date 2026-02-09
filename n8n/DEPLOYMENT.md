# Multi-Environment Deployment Guide

This guide walks through deploying n8n infrastructure across multiple environments (dev, staging, production) using Terraform with GCS backend.

## Architecture Overview

```
GCP Organization
├── development (project)
│   ├── State: gs://myorg-tfstate-dev/n8n/
│   ├── Network: 10.10.0.0/16
│   └── Resources: myorg-n8n-dev-*
├── staging (project)
│   ├── State: gs://myorg-tfstate-staging/n8n/
│   ├── Network: 10.20.0.0/16
│   └── Resources: myorg-n8n-staging-*
└── production (project)
    ├── State: gs://myorg-tfstate-production/n8n/
    ├── Network: 10.30.0.0/16
    └── Resources: myorg-n8n-production-*
```

## Prerequisites

### 1. GCP Setup

Authenticate and install required components:

```sh
gcloud auth application-default login
gcloud components install gke-gcloud-auth-plugin
```

### 2. Per-Environment Setup

Repeat these steps for each environment (dev, staging, production):

#### Create GCS Backend Bucket

```sh
# Development
gcloud storage buckets create gs://myorg-tfstate-dev \
  --project=development \
  --location=europe-north1 \
  --uniform-bucket-level-access

gcloud storage buckets update gs://myorg-tfstate-dev --versioning

# Staging
gcloud storage buckets create gs://myorg-tfstate-staging \
  --project=staging \
  --location=europe-north1 \
  --uniform-bucket-level-access

gcloud storage buckets update gs://myorg-tfstate-staging --versioning

# Production
gcloud storage buckets create gs://myorg-tfstate-production \
  --project=production \
  --location=europe-north1 \
  --uniform-bucket-level-access

gcloud storage buckets update gs://myorg-tfstate-production --versioning
```

#### Create Secrets in Secret Manager

```sh
# Development
echo -n "$(openssl rand -hex 32)" | gcloud secrets create n8n-dev-encryption-key \
  --data-file=- --project=development

echo -n "your-secure-password" | gcloud secrets create n8n-dev-db-password \
  --data-file=- --project=development

# Staging
echo -n "$(openssl rand -hex 32)" | gcloud secrets create n8n-staging-encryption-key \
  --data-file=- --project=staging

echo -n "your-secure-password" | gcloud secrets create n8n-staging-db-password \
  --data-file=- --project=staging

# Production
echo -n "$(openssl rand -hex 32)" | gcloud secrets create n8n-production-encryption-key \
  --data-file=- --project=production

echo -n "your-secure-password" | gcloud secrets create n8n-production-db-password \
  --data-file=- --project=production

echo -n "your-license-key" | gcloud secrets create n8n-production-license \
  --data-file=- --project=production
```

## Deployment Steps

### Deploy Development Environment

```sh
cd n8n/

# Create workspace
terraform workspace new dev

# Initialize with dev backend
terraform init -backend-config="bucket=myorg-tfstate-dev"

# Plan
terraform plan -var-file=environments/dev.tfvars -out=tfplan-dev

# Apply
terraform apply tfplan-dev

# Get cluster credentials
gcloud container clusters get-credentials $(terraform output -raw cluster_name) \
  --zone $(terraform output -raw zone) \
  --project $(terraform output -raw project_id)

# Verify deployment
kubectl get pods -n $(terraform output -raw namespace)
kubectl get svc -n $(terraform output -raw namespace)
```

### Deploy Staging Environment

```sh
# Switch workspace
terraform workspace new staging

# Reconfigure backend for staging
terraform init -backend-config="bucket=myorg-tfstate-staging" -reconfigure

# Plan
terraform plan -var-file=environments/staging.tfvars -out=tfplan-staging

# Apply
terraform apply tfplan-staging

# Get cluster credentials
gcloud container clusters get-credentials $(terraform output -raw cluster_name) \
  --zone $(terraform output -raw zone) \
  --project $(terraform output -raw project_id)

# Verify deployment
kubectl get pods -n $(terraform output -raw namespace)
```

### Deploy Production Environment

```sh
# Switch workspace
terraform workspace new production

# Reconfigure backend for production
terraform init -backend-config="bucket=myorg-tfstate-production" -reconfigure

# Plan
terraform plan -var-file=environments/production.tfvars -out=tfplan-production

# Review plan carefully!
# Apply
terraform apply tfplan-production

# Get cluster credentials
gcloud container clusters get-credentials $(terraform output -raw cluster_name) \
  --zone $(terraform output -raw zone) \
  --project $(terraform output -raw project_id)

# Verify deployment
kubectl get pods -n $(terraform output -raw namespace)
```

## Switching Between Environments

```sh
# List workspaces
terraform workspace list

# Switch to a different environment
terraform workspace select dev

# Reconfigure backend (if needed)
terraform init -backend-config="bucket=myorg-tfstate-dev" -reconfigure

# Now you can run commands against the dev environment
terraform plan -var-file=environments/dev.tfvars
```

## Verification

### Check Terraform Outputs

```sh
terraform output environment  # Should show: dev/staging/production
terraform output workspace    # Should match environment
terraform output namespace    # Should show: n8n-{environment}
terraform output cluster_name # Should show: {org}-n8n-{env}-gke
```

### Check Kubernetes Resources

```sh
# Get namespace
NAMESPACE=$(terraform output -raw namespace)

# Check pods
kubectl get pods -n $NAMESPACE

# Check services
kubectl get svc -n $NAMESPACE

# Check External Secrets
kubectl get externalsecret -n $NAMESPACE
kubectl get secretstore -n $NAMESPACE

# Check logs
kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=n8n --tail=50
```

### Check n8n Access

```sh
# For LoadBalancer (dev environment)
kubectl get svc -n $NAMESPACE n8n

# Wait for EXTERNAL-IP to be assigned, then access:
# http://<EXTERNAL-IP>:5678

# For Ingress (staging/production)
kubectl get ingress -n $NAMESPACE
```

## Common Operations

### Update an Environment

```sh
# Select workspace
terraform workspace select dev

# Make changes to environments/dev.tfvars or Terraform files

# Plan and apply
terraform plan -var-file=environments/dev.tfvars -out=tfplan-dev
terraform apply tfplan-dev
```

### View State

```sh
# List resources
terraform state list

# Show specific resource
terraform state show google_container_cluster.gke
```

### Destroy an Environment

```sh
# CAUTION: This will delete all resources!

terraform workspace select dev
terraform destroy -var-file=environments/dev.tfvars
```

## Troubleshooting

### n8n Pod CrashLoopBackOff

Check database connection:

```sh
NAMESPACE=$(terraform output -raw namespace)
kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=n8n --tail=50
kubectl describe pod -n $NAMESPACE -l app.kubernetes.io/name=n8n
```

### External Secrets Not Syncing

```sh
NAMESPACE=$(terraform output -raw namespace)

# Check SecretStore
kubectl get secretstore -n $NAMESPACE -o yaml

# Check ExternalSecret
kubectl describe externalsecret n8n-keys -n $NAMESPACE

# Check ESO logs
kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=external-secrets
```

### Wrong Environment

If you accidentally deployed to the wrong environment:

```sh
# Check current workspace
terraform workspace show

# Check outputs
terraform output environment
terraform output project_id

# If wrong, switch workspace and reconfigure
terraform workspace select <correct-env>
terraform init -backend-config="bucket=myorg-tfstate-<correct-env>" -reconfigure
```

## Best Practices

1. **Always use workspaces** - Each environment gets its own workspace
2. **Always use -var-file** - Never hardcode environment values
3. **Always run plan first** - Review changes before applying
4. **Use plan output files** - Ensures what you reviewed is what gets applied
5. **Name plan files by environment** - `tfplan-dev`, `tfplan-staging`, etc.
6. **Verify workspace before applying** - Run `terraform workspace show`
7. **Keep state in GCS** - Never commit state files to git
8. **Version your backend buckets** - Enables rollback if needed
9. **Separate GCP projects** - Isolates environments completely
10. **Use different CIDR ranges** - Enables VPC peering if needed later

## Security Notes

- **Never commit** `.tfstate` files or `.auto.tfvars` files
- **Secrets live in Secret Manager** - Never in Terraform state or code
- **Use Workload Identity** - No service account keys needed
- **Enable deletion protection** - On staging and production Cloud SQL
- **Review plans carefully** - Especially for production changes
- **Limit access to GCS buckets** - Only authorized users/service accounts
- **Rotate secrets regularly** - Update in Secret Manager, ESO syncs automatically
