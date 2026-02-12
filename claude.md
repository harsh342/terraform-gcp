# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# terraform-gcp

- `n8n/` - Production n8n workflow automation on GKE with Cloud SQL

## Multi-Environment Architecture

The n8n deployment supports 3 isolated environments (dev/staging/production) with:
- **State storage:** Separate GCS buckets per environment (`gs://{org_prefix}-tfstate-{env}/n8n/`)
- **Terraform workspaces:** One workspace per environment
- **GCP projects:** dev and staging share `yesgaming-nonprod`; production uses `boxwood-coil-484213-r6`
- **CIDR allocation:** Non-overlapping ranges to enable future VPC peering

| Environment | Subnet | Pods | Services | Node Type | Node Count | SQL Tier |
|-------------|--------|------|----------|-----------|------------|----------|
| dev | 10.10.0.0/16 | 10.11.0.0/16 | 10.12.0.0/20 | e2-standard-2 | 1 | db-f1-micro |
| staging | 10.20.0.0/16 | 10.21.0.0/16 | 10.22.0.0/20 | e2-standard-2 | 1 | db-custom-2-7680 |
| production | 10.30.0.0/16 | 10.31.0.0/16 | 10.32.0.0/20 | e2-standard-4 | 2 | db-custom-4-15360 |

**Naming convention:** Resources follow `{org_prefix}-n8n-{environment}-{resource}` pattern
- Example: `yesgaming-n8n-dev-gke`, `yesgaming-n8n-production-postgres`
- K8s namespace: `n8n-{environment}`

**Dynamic naming via locals:**
```hcl
locals {
  namespace   = var.namespace != "" ? var.namespace : "n8n-${var.environment}"
  name_prefix = var.org_prefix != "" ? "${var.org_prefix}-n8n-${var.environment}" : "n8n-${var.environment}"
  common_labels = { environment = var.environment, managed_by = "terraform", application = "n8n" }
}
```

## n8n Deployment Architecture

The deployment uses a **multi-provider pattern** to handle GKE cluster bootstrapping:

```
GCP Provider → Create GKE Cluster
    ↓
k8s_providers.tf → Wire K8s/Helm/kubectl providers to cluster endpoint
    ↓
kubectl Provider → Deploy CRDs (SecretStore, ExternalSecret)
    ↓
Helm Provider → Deploy External Secrets Operator + n8n
```

**Why three Kubernetes providers?**
- `kubernetes`: Native resources (namespace, service accounts)
- `helm`: Chart deployments (ESO, n8n)
- `kubectl`: CRDs that must be planned before cluster exists (avoids "resource type not found" errors)

**Critical dependency chain:**
1. `apis.tf` enables GCP APIs → all resources depend on this
2. `network_gke.tf` creates VPC + Private Service Access → required for Cloud SQL private IP
3. `gke.tf` creates cluster with Workload Identity → enables `{project_id}.svc.id.goog` pool
4. `external_secrets.tf` binds GCP SA to K8s SA → includes 60s wait for IAM propagation
5. `external_secrets.tf` deploys ESO Helm chart → installs CRDs with `installCRDs: true`
6. `external_secrets.tf` creates SecretStore + ExternalSecrets → materializes K8s secrets
7. `n8n.tf` deploys n8n Helm chart → depends on secrets existing

**Secrets flow (zero secrets in Terraform state):**
```
GCP Secret Manager
    ↓ (Workload Identity: GCP SA ↔ K8s SA)
External Secrets Operator
    ↓ (Syncs every 1h)
K8s Secrets (n8n-keys, n8n-db)
    ↓ (Mounted as env vars)
n8n Pod → Cloud SQL (private IP)
```

## File Organization

Files are grouped by infrastructure concern:

| File | Purpose | Key Resources |
|------|---------|--------------|
| `providers.tf` | Provider versions + GCS backend | `terraform {}`, `backend "gcs"` |
| `variables.tf` | Input variables + locals | No defaults on required vars |
| `k8s_providers.tf` | K8s provider authentication wiring | Dynamic cluster endpoint + token |
| `apis.tf` | GCP API enablement | `google_project_service` |
| `network_gke.tf` | VPC + Private Service Access | Uses `var.subnet_cidr`, `var.pods_cidr`, `var.services_cidr` |
| `gke.tf` | GKE cluster + node pool | Adds `common_labels` |
| `cloudsql.tf` | PostgreSQL + auto-generated password | Stores password in Secret Manager |
| `external_secrets.tf` | ESO + Workload Identity + CRDs | Helm chart + kubectl manifests |
| `n8n.tf` | n8n namespace + Helm deployment | Depends on secrets + Cloud SQL user |
| `outputs.tf` | Cluster/DB info + environment metadata | `environment`, `workspace`, `namespace` |
| `environments/*.tfvars` | Per-environment variable values | No sensitive data |
## Common Commands

### Initial Setup (per environment)

See [DEPLOYMENT.md](n8n/DEPLOYMENT.md) for full step-by-step instructions. Summary of prerequisites before `terraform apply`:

1. **Authenticate:** `gcloud auth application-default login && gcloud components install gke-gcloud-auth-plugin`
2. **Enable APIs:** `gcloud services enable compute.googleapis.com container.googleapis.com sqladmin.googleapis.com secretmanager.googleapis.com servicenetworking.googleapis.com iam.googleapis.com --project=<PROJECT_ID>`
3. **Create GCS bucket:** `gcloud storage buckets create gs://yesgaming-tfstate-{env} --project=<PROJECT_ID> --location=europe-north1 --uniform-bucket-level-access` + enable versioning
4. **Create secrets:** encryption key (`openssl rand -hex 32`) + db-password placeholder in Secret Manager with `--replication-policy="automatic"`

### Deploy to Environment

```sh
cd n8n/

# Create workspace (first time only)
terraform workspace new dev

# Initialize with GCS backend
terraform init -backend-config="bucket=yesgaming-tfstate-dev"

# Standard workflow
terraform fmt -recursive
terraform validate
terraform plan -var-file=environments/dev.tfvars -out=tfplan-dev
terraform apply tfplan-dev

# Get cluster credentials
gcloud container clusters get-credentials $(terraform output -raw cluster_name) \
  --zone $(terraform output -raw zone) --project $(terraform output -raw project_id)

# Verify deployment
kubectl get pods -n $(terraform output -raw namespace)
kubectl get svc -n $(terraform output -raw namespace)
kubectl logs -n $(terraform output -raw namespace) -l app.kubernetes.io/name=n8n --tail=50
```

### Switch Environments

```sh
# List workspaces
terraform workspace list

# Switch workspace
terraform workspace select staging

# Reconfigure backend (required when switching projects)
terraform init -backend-config="bucket=yesgaming-tfstate-staging" -reconfigure

# Now operate on staging
terraform plan -var-file=environments/staging.tfvars
```

### Check External Secrets

```sh
NAMESPACE=$(terraform output -raw namespace)
kubectl get externalsecret -n $NAMESPACE
kubectl get secretstore -n $NAMESPACE
kubectl describe externalsecret n8n-keys -n $NAMESPACE
kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=external-secrets
```

## Key Patterns

### No Defaults on Required Variables
`project_id`, `environment`, `subnet_cidr`, and all secret names have **no defaults** to prevent accidental exposure in public repos. Must be passed explicitly via `-var-file` or `TF_VAR_*`.

### Provider Wiring Pattern
All three K8s providers authenticate using `google_client_config.default.access_token` pointing to `google_container_cluster.gke.endpoint`. This creates an implicit dependency ensuring providers configure **after** cluster creation.

### kubectl Provider for CRDs
Use `kubectl_manifest` (not `kubernetes_manifest`) for CRDs to avoid plan-time errors when cluster doesn't exist. The kubectl provider can plan CRDs without a live cluster.

### Workload Identity Binding
```hcl
# GCP SA ↔ K8s SA binding requires cluster to exist first
resource "google_service_account_iam_member" "external_secrets_wi" {
  member = "serviceAccount:${var.project_id}.svc.id.goog[${local.namespace}/${var.external_secrets_k8s_sa_name}]"
  depends_on = [google_container_cluster.gke]
}

# 60s wait for IAM propagation
resource "time_sleep" "wait_for_wi" {
  create_duration = "60s"
  depends_on = [google_service_account_iam_member.external_secrets_wi]
}
```

### Cloud SQL Password Management
Terraform generates a random password, creates the Cloud SQL user, and stores the password in Secret Manager. ExternalSecrets syncs it to K8s secrets. **Important:** The password is marked `sensitive = true` in outputs.

## Troubleshooting

**n8n pod CrashLoopBackOff - "password authentication failed":**
```sh
# Check if Cloud SQL user exists
gcloud sql users list --instance=$(terraform output -raw cloudsql_instance_name) \
  --project=$(terraform output -raw project_id)

# Verify password in Secret Manager (use the secret name from your tfvars)
gcloud secrets versions access latest --secret=n8n-{environment}-db-password \
  --project=$(terraform output -raw project_id)

# Check n8n logs
kubectl logs -n $(terraform output -raw namespace) -l app.kubernetes.io/name=n8n --tail=50
```

**kubectl: "executable gke-gcloud-auth-plugin not found":**
```sh
gcloud components install gke-gcloud-auth-plugin
export USE_GKE_GCLOUD_AUTH_PLUGIN=True
```

**ExternalSecret not syncing:**
```sh
NAMESPACE=$(terraform output -raw namespace)

# Check SecretStore status (should show "Valid")
kubectl get secretstore -n $NAMESPACE

# Check ExternalSecret status (should show "SecretSynced")
kubectl get externalsecret -n $NAMESPACE

# Debug sync issues
kubectl describe externalsecret n8n-keys -n $NAMESPACE
kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=external-secrets
```

**Workload Identity errors:**
- Verify `depends_on = [google_container_cluster.gke]` exists in `external_secrets.tf`
- Check K8s SA annotation: `kubectl get sa external-secrets -n $(terraform output -raw namespace) -o yaml`
- Look for `iam.gke.io/gcp-service-account` annotation pointing to GCP SA email
- Wait 60s after IAM binding (handled by `time_sleep.wait_for_wi`)

**Wrong environment deployed:**
```sh
# Always verify before applying
terraform workspace show           # Should match intended environment
terraform output environment       # Should match workspace
terraform output project_id        # Should be correct project
terraform output namespace         # Should be n8n-{environment}
```

## Important Notes

- **State stored in GCS:** Never commit `.tfstate` files. Each environment has separate bucket.
- **Workspaces are namespace only:** Workspaces provide organization but state is still per-backend-bucket.
- **ESO Helm chart managed by Terraform:** Don't manually install ESO. Version pinned to 0.9.13.
- **License key is optional:** `n8n_license_activation_key_secret_name` defaults to `""` and conditionally added to ExternalSecret.
- **Private Service Access:** `google_service_networking_connection` in `network_gke.tf` is required for Cloud SQL private IP. Don't remove.
- **CIDR ranges are parameterized:** Use `var.subnet_cidr`, `var.pods_cidr`, `var.services_cidr` (not hardcoded).
- **Resource naming is dynamic:** Uses `local.name_prefix` and `local.namespace` computed from `var.environment` and `var.org_prefix`.
- **`.tfvars` files are gitignored at root** but tracked under `n8n/environments/` via the n8n-level `.gitignore` which only ignores `environments/*.auto.tfvars` and `environments/local.tfvars`.

## Coding Conventions

- 2-space indentation, `snake_case` naming
- Block comments (`/* */`) at file headers
- Resources grouped by concern in separate files (not monolithic)
- Pin provider versions in `providers.tf` for reproducibility (currently: google 6.8.0, kubernetes 3.0.1, helm 2.12.1, kubectl 1.19.0, random 3.8.1)
- Use `depends_on` explicitly for Workload Identity and cross-provider dependencies
- Add `common_labels` to all GCP resources for environment tracking
- Use `local.name_prefix` for resource names, `local.namespace` for K8s namespace
- Mark sensitive outputs with `sensitive = true` (e.g., database passwords)

## Documentation

- **DEPLOYMENT.md:** Comprehensive multi-environment deployment guide with prerequisites, step-by-step instructions, troubleshooting, and best practices
- **environments/README.md:** Environment-specific configuration differences and customization guide
- **Root README.md:** High-level repository overview and quick links
