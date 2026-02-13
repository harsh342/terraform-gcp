# Multi-Environment Deployment Guide

This guide walks through deploying n8n infrastructure across multiple environments (dev, staging, production) using Terraform with GCS backend.

## Architecture Overview

```
GCP Organization
├── yesgaming-nonprod (project)
│   ├── Dev:     https://n8n-dev.theyes.cloud   → gs://yesgaming-tfstate-dev/n8n/
│   └── Staging: https://n8n-stage.theyes.cloud → gs://yesgaming-tfstate-staging/n8n/
└── boxwood-coil-484213-r6 (project)
    └── Prod:    https://n8n.theyes.cloud       → gs://yesgaming-tfstate-production/n8n/
```

> **Note:** Dev and staging share the `yesgaming-nonprod` project. Production uses a separate project (`boxwood-coil-484213-r6`).

## Prerequisites

### 1. Tools

- Terraform >= 1.5.0
- `gcloud` CLI authenticated
- kubectl + GKE auth plugin

```sh
gcloud auth application-default login
gcloud components install kubectl gke-gcloud-auth-plugin
```

### 2. Enable GCP APIs

APIs must be enabled in each GCP project before Terraform can create resources.

**For yesgaming-nonprod (dev + staging):**

```sh
gcloud services enable \
  compute.googleapis.com \
  container.googleapis.com \
  sqladmin.googleapis.com \
  secretmanager.googleapis.com \
  servicenetworking.googleapis.com \
  iam.googleapis.com \
  --project=yesgaming-nonprod
```

**For boxwood-coil-484213-r6 (production):**

```sh
gcloud services enable \
  compute.googleapis.com \
  container.googleapis.com \
  sqladmin.googleapis.com \
  secretmanager.googleapis.com \
  servicenetworking.googleapis.com \
  iam.googleapis.com \
  --project=boxwood-coil-484213-r6
```

### 3. Create GCS Backend Buckets

Each environment needs a separate GCS bucket for Terraform state storage.

```sh
# Dev
gcloud storage buckets create gs://yesgaming-tfstate-dev \
  --project=yesgaming-nonprod \
  --location=europe-north1 \
  --uniform-bucket-level-access
gcloud storage buckets update gs://yesgaming-tfstate-dev --versioning

# Staging
gcloud storage buckets create gs://yesgaming-tfstate-staging \
  --project=yesgaming-nonprod \
  --location=europe-north1 \
  --uniform-bucket-level-access
gcloud storage buckets update gs://yesgaming-tfstate-staging --versioning

# Production
gcloud storage buckets create gs://yesgaming-tfstate-production \
  --project=boxwood-coil-484213-r6 \
  --location=europe-north1 \
  --uniform-bucket-level-access
gcloud storage buckets update gs://yesgaming-tfstate-production --versioning
```

### 4. Create Secrets in Secret Manager

Each environment needs an encryption key and a database password placeholder in Secret Manager. Terraform generates the actual DB password and updates the secret.

**Dev secrets (yesgaming-nonprod):**

```sh
echo -n "$(openssl rand -hex 32)" | gcloud secrets create n8n-dev-encryption-key \
  --data-file=- \
  --project=yesgaming-nonprod \
  --replication-policy="automatic"

echo -n "placeholder" | gcloud secrets create n8n-dev-db-password \
  --data-file=- \
  --project=yesgaming-nonprod \
  --replication-policy="automatic"
```

**Staging secrets (yesgaming-nonprod):**

```sh
echo -n "$(openssl rand -hex 32)" | gcloud secrets create n8n-staging-encryption-key \
  --data-file=- \
  --project=yesgaming-nonprod \
  --replication-policy="automatic"

echo -n "placeholder" | gcloud secrets create n8n-staging-db-password \
  --data-file=- \
  --project=yesgaming-nonprod \
  --replication-policy="automatic"
```

**Production secrets (boxwood-coil-484213-r6):**

```sh
echo -n "$(openssl rand -hex 32)" | gcloud secrets create n8n-production-encryption-key \
  --data-file=- \
  --project=boxwood-coil-484213-r6 \
  --replication-policy="automatic"

echo -n "placeholder" | gcloud secrets create n8n-production-db-password \
  --data-file=- \
  --project=boxwood-coil-484213-r6 \
  --replication-policy="automatic"

# Optional: n8n license key (only if you have one)
echo -n "your-license-key" | gcloud secrets create n8n-production-license \
  --data-file=- \
  --project=boxwood-coil-484213-r6 \
  --replication-policy="automatic"
```

**Verify secrets were created:**

```sh
gcloud secrets list --project=yesgaming-nonprod --filter="name:n8n-"
gcloud secrets list --project=boxwood-coil-484213-r6 --filter="name:n8n-"
```

> **Note:** The `n8n-*-db-password` secrets are created with a `placeholder` value. Terraform generates a random 32-character password, creates the Cloud SQL user, and updates the secret with the real password on first `terraform apply`.

## Deployment Steps

### Deploy Development Environment

```sh
cd n8n/

# Create workspace (first time only)
terraform workspace new dev

# Initialize with dev backend
terraform init -backend-config="bucket=yesgaming-tfstate-dev"

# Validate and plan
terraform fmt -recursive
terraform validate
terraform plan -var-file=environments/dev.tfvars -out=tfplan-dev

# Apply
terraform apply tfplan-dev

# Get cluster credentials
gcloud container clusters get-credentials $(terraform output -raw cluster_name) \
  --zone $(terraform output -raw zone) \
  --project $(terraform output -raw project_id)

# Verify deployment
kubectl get pods -n $(terraform output -raw namespace)
kubectl get ingress -n $(terraform output -raw namespace)
```

### Deploy Staging Environment

```sh
# Create workspace (first time only)
terraform workspace new staging

# Reconfigure backend for staging (same project, different bucket)
terraform init -backend-config="bucket=yesgaming-tfstate-staging" -reconfigure

# Plan and apply
terraform plan -var-file=environments/staging.tfvars -out=tfplan-staging
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
# Create workspace (first time only)
terraform workspace new production

# Reconfigure backend for production (different project + bucket)
terraform init -backend-config="bucket=yesgaming-tfstate-production" -reconfigure

# Plan — review carefully before applying!
terraform plan -var-file=environments/production.tfvars -out=tfplan-production

# Apply
terraform apply tfplan-production

# Get cluster credentials
gcloud container clusters get-credentials $(terraform output -raw cluster_name) \
  --zone $(terraform output -raw zone) \
  --project $(terraform output -raw project_id)

# Verify deployment
kubectl get pods -n $(terraform output -raw namespace)
```

**Production checklist (before applying):**
- [ ] Review all settings in `environments/production.tfvars`
- [ ] Verify `cloudsql_deletion_protection = true`
- [ ] Confirm correct project ID (`boxwood-coil-484213-r6`)
- [ ] Plan output shows expected resources

### DNS and TLS Setup (Cloudflare)

After each `terraform apply`, Terraform creates a GCE Ingress and a Google-managed TLS certificate. You must configure DNS so the certificate can provision.

> **Important:** The Ingress is managed via `kubectl_manifest` outside the Helm chart. This sets an explicit `defaultBackend` to avoid GKE's system default-http-backend NEG issues.

**1. Get the ingress external IP:**

```sh
NAMESPACE=$(terraform output -raw namespace)
kubectl get ingress -n $NAMESPACE
# Note the ADDRESS column — this is the IP for your DNS record
# It may take 2-5 minutes for the GCE load balancer to provision an IP
```

**2. Create DNS A records in Cloudflare** (`theyes.cloud` zone):

| Environment | Domain | Record Type | Value | Proxy Status |
|-------------|--------|-------------|-------|--------------|
| dev | `n8n-dev.theyes.cloud` | A | `<dev ingress IP>` | **DNS only (gray cloud)** |
| staging | `n8n-stage.theyes.cloud` | A | `<staging ingress IP>` | **DNS only (gray cloud)** |
| production | `n8n.theyes.cloud` | A | `<production ingress IP>` | **DNS only (gray cloud)** |

> **CRITICAL — Cloudflare proxy must be OFF:**
> - Set proxy status to **DNS only (gray cloud)**, NOT Proxied (orange cloud)
> - Cloudflare proxy resolves DNS to Cloudflare IPs, which prevents Google from verifying domain ownership for the managed certificate
> - If proxied, you will see "Dangerous site" warnings and the certificate will stay stuck in "Provisioning"
>
> **Do NOT create Cloudflare origin/port rewrite rules:**
> - The GCE load balancer handles 80/443 → backend port (5678) routing internally
> - Adding a port rewrite rule (e.g., to port 5678) bypasses the load balancer and breaks HTTPS

**3. Wait for managed certificate provisioning** (10-15 minutes after DNS propagates):

```sh
# Check certificate status — should go from "Provisioning" to "Active"
kubectl get managedcertificate -n $NAMESPACE

# Detailed status
kubectl describe managedcertificate -n $NAMESPACE

# Verify DNS resolves to the ingress IP (not Cloudflare IPs)
dig n8n-dev.theyes.cloud
```

> **Note:** The certificate will stay in `Provisioning` until Google can verify the domain resolves to the ingress IP. If it stays stuck:
> 1. Verify the DNS A record points to the correct ingress IP
> 2. Verify Cloudflare proxy is **OFF** (gray cloud, not orange cloud)
> 3. Remove any Cloudflare origin rules that rewrite ports
> 4. Wait for DNS propagation (`dig <domain>` should return the ingress IP)

**4. Verify HTTPS access:**

| Environment | URL |
|-------------|-----|
| dev | `https://n8n-dev.theyes.cloud` |
| staging | `https://n8n-stage.theyes.cloud` |
| production | `https://n8n.theyes.cloud` |

### Post-Deploy Verification Checklist

Run this after each environment deployment + DNS setup:

```sh
NAMESPACE=$(terraform output -raw namespace)

# 1. All pods should be Running
kubectl get pods -n $NAMESPACE

# 2. ExternalSecrets should show "SecretSynced"
kubectl get externalsecret -n $NAMESPACE

# 3. Ingress should have an external IP in ADDRESS column
kubectl get ingress -n $NAMESPACE

# 4. ManagedCertificate should show "Active" (takes 10-15 min after DNS)
kubectl get managedcertificate -n $NAMESPACE

# 5. DNS should resolve to the ingress IP (not Cloudflare IPs)
dig +short $(terraform output -raw n8n_host 2>/dev/null || echo "n8n-dev.theyes.cloud")

# 6. HTTPS should work (after cert is Active)
curl -I https://$(terraform output -raw n8n_host 2>/dev/null || echo "n8n-dev.theyes.cloud")
```

## Switching Between Environments

```sh
# List workspaces
terraform workspace list

# Switch to a different environment
terraform workspace select dev

# Reconfigure backend (required when switching)
terraform init -backend-config="bucket=yesgaming-tfstate-dev" -reconfigure

# Now operate on dev
terraform plan -var-file=environments/dev.tfvars
```

> **Always verify before applying:**
> ```sh
> terraform workspace show       # Should match intended environment
> terraform output environment   # Should match workspace
> terraform output project_id    # Should be correct project
> ```

## Verification

### Check Terraform Outputs

```sh
terraform output environment  # dev/staging/production
terraform output workspace    # Should match environment
terraform output namespace    # n8n-{environment}
terraform output cluster_name # yesgaming-n8n-{env}-gke
```

### Check Kubernetes Resources

```sh
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
# Check ingress and managed certificate status
kubectl get ingress -n $NAMESPACE
kubectl get managedcertificate -n $NAMESPACE
```

| Environment | URL |
|-------------|-----|
| dev | `https://n8n-dev.theyes.cloud` |
| staging | `https://n8n-stage.theyes.cloud` |
| production | `https://n8n.theyes.cloud` |

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

**"password authentication failed"** — verify the Cloud SQL user and password:

```sh
# Check if Cloud SQL user exists
gcloud sql users list \
  --instance=$(terraform output -raw cloudsql_instance_name) \
  --project=$(terraform output -raw project_id)

# Verify password in Secret Manager (replace {environment} with dev/staging/production)
gcloud secrets versions access latest \
  --secret=n8n-{environment}-db-password \
  --project=$(terraform output -raw project_id)
```

### External Secrets Not Syncing

```sh
NAMESPACE=$(terraform output -raw namespace)

# Check SecretStore (should show "Valid")
kubectl get secretstore -n $NAMESPACE -o yaml

# Check ExternalSecret (should show "SecretSynced")
kubectl describe externalsecret n8n-keys -n $NAMESPACE

# Check ESO logs
kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=external-secrets
```

### Ingress Has No External IP

```sh
NAMESPACE=$(terraform output -raw namespace)

# Check ingress events for errors
kubectl describe ingress n8n -n $NAMESPACE

# Verify the ingress was created by Terraform (not Helm)
terraform state list | grep n8n_ingress
```

The GCE load balancer may take 2-5 minutes to provision. If the ADDRESS column stays empty:
- Check `kubectl describe ingress` for error events
- Verify `n8n_host` is set in your tfvars file (ingress is only created when `n8n_host != ""`)

### ManagedCertificate Stuck in "Provisioning"

```sh
kubectl describe managedcertificate -n $NAMESPACE
dig +short <your-domain>
```

**Checklist:**
1. DNS A record points to the ingress IP (not Cloudflare proxy IPs like 104.x.x.x)
2. Cloudflare proxy is **OFF** — must be DNS-only (gray cloud)
3. No Cloudflare origin rules rewriting ports
4. Wait 10-15 minutes after DNS propagation

### "Dangerous Site" or SSL Errors

This means Cloudflare proxy is intercepting traffic:
1. Go to Cloudflare dashboard → DNS → find the A record
2. Click the orange cloud icon to toggle to **gray cloud (DNS-only)**
3. Remove any origin rules that rewrite the port to 5678
4. Wait 10-15 minutes for the Google-managed certificate to provision

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
terraform init -backend-config="bucket=yesgaming-tfstate-<correct-env>" -reconfigure
```

## Best Practices

1. **Always use workspaces** — Each environment gets its own workspace
2. **Always use -var-file** — Never hardcode environment values
3. **Always run plan first** — Review changes before applying
4. **Use plan output files** — Ensures what you reviewed is what gets applied
5. **Name plan files by environment** — `tfplan-dev`, `tfplan-staging`, etc.
6. **Verify workspace before applying** — Run `terraform workspace show`
7. **Keep state in GCS** — Never commit state files to git
8. **Version your backend buckets** — Enables rollback if needed
9. **Separate GCP projects** — Isolates environments completely
10. **Use different CIDR ranges** — Enables VPC peering if needed later

## Security Notes

- **Never commit** `.tfstate` files or `.auto.tfvars` files
- **Secrets live in Secret Manager** — Never in Terraform state or code
- **Use Workload Identity** — No service account keys needed
- **Enable deletion protection** — On staging and production Cloud SQL
- **Review plans carefully** — Especially for production changes
- **Limit access to GCS buckets** — Only authorized users/service accounts
- **Rotate secrets regularly** — Update in Secret Manager, ESO syncs automatically
