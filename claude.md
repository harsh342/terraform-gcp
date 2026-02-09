# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# terraform-gcp

Terraform configurations for deploying infrastructure on GCP. Two main directories:
- `learn/` - Simple sandbox configuration (VPC + VM)
- `n8n/` - Production n8n workflow automation on GKE with Cloud SQL

## Multi-Environment Setup

Supports 3 environments via Terraform workspaces: dev, staging, production.

### Prerequisites (per environment)

**1. Create GCS backend bucket:**
```sh
gcloud storage buckets create gs://myorg-tfstate-dev \
  --project=development \
  --location=europe-north1 \
  --uniform-bucket-level-access

gcloud storage buckets update gs://myorg-tfstate-dev --versioning
```

**2. Create secrets:**
```sh
echo -n "$(openssl rand -hex 32)" | gcloud secrets create n8n-dev-encryption-key \
  --data-file=- --project=development

echo -n "your-password" | gcloud secrets create n8n-dev-db-password \
  --data-file=- --project=development
```

### Deployment

```sh
cd n8n/

# Create workspace
terraform workspace new dev

# Initialize
terraform init -backend-config="bucket=myorg-tfstate-dev"

# Deploy
terraform plan -var-file=environments/dev.tfvars -out=tfplan-dev
terraform apply tfplan-dev
```

### Switching Environments

```sh
terraform workspace select staging
terraform plan -var-file=environments/staging.tfvars
```

### Naming Conventions

Resources: `{org_prefix}-n8n-{environment}-{resource}`
- VPC: `myorg-n8n-dev-network`
- GKE: `myorg-n8n-staging-gke`
- Cloud SQL: `myorg-n8n-production-postgres`
- K8s namespace: `n8n-{environment}`

### CIDR Allocation

| Env | Subnet | Pods | Services |
|-----|--------|------|----------|
| dev | 10.10.0.0/16 | 10.11.0.0/16 | 10.12.0.0/20 |
| staging | 10.20.0.0/16 | 10.21.0.0/16 | 10.22.0.0/20 |
| production | 10.30.0.0/16 | 10.31.0.0/16 | 10.32.0.0/20 |

## Architecture (n8n)

The n8n deployment uses a **multi-provider pattern** unique to Kubernetes-on-GCP scenarios:

```
GCP Provider → Create GKE Cluster
    ↓
k8s_providers.tf → Wire K8s/Helm/kubectl providers to cluster endpoint
    ↓
kubectl Provider → Deploy CRDs (SecretStore, ExternalSecret)
    ↓
Helm Provider → Deploy n8n application
```

**Why three Kubernetes providers?**
- `kubernetes`: Native resources (namespace, service accounts)
- `helm`: Chart deployments
- `kubectl`: CRDs that must be planned before cluster exists (avoids plan-time errors)

**Critical dependency chain:**
1. `apis.tf` enables GCP APIs → must complete before any resource creation
2. `network_gke.tf` creates VPC with Private Service Access → required for Cloud SQL private IP
3. `gke.tf` creates cluster with Workload Identity → pool name needed for IAM bindings
4. `external_secrets.tf` uses `depends_on = [google_container_cluster.gke]` for Workload Identity binding
5. `external_secrets.tf` includes `time_sleep.wait_for_wi` (60s) to allow IAM propagation
6. ExternalSecrets materialize K8s secrets → n8n Helm release depends on these

## Key Patterns

### Secrets Flow (No secrets in Terraform state)
```
GCP Secret Manager
    ↓ (Workload Identity: GCP SA ↔ K8s SA)
External Secrets Operator
    ↓ (Syncs every 1h)
K8s Secrets (n8n-keys, n8n-db)
    ↓ (Mounted as env vars)
n8n Pod
```

**Important:** ESO Helm chart is now installed by Terraform in `external_secrets.tf` (previously manual). The chart installs CRDs automatically with `installCRDs: true`.

### Variable Pattern (No defaults for required values)
`project_id`, `region`, `zone`, `network_name`, `cluster_name`, and all secret names have **no defaults** to force explicit passing. This prevents accidental exposure in public repos. Always pass via `-var` or `TF_VAR_*`.

### Provider Wiring Pattern (k8s_providers.tf)
All three K8s providers authenticate using `google_client_config.default.access_token` pointing to `google_container_cluster.gke.endpoint`. This creates an implicit dependency where providers are configured **after** cluster creation.

## Common Commands

```sh
# Work from n8n/ directory
cd n8n/

# Standard workflow
terraform init -backend-config="bucket=myorg-tfstate-dev"
terraform fmt -recursive
terraform validate
terraform plan -var-file=environments/dev.tfvars -out=tfplan-dev
terraform apply tfplan-dev

# Get cluster credentials
gcloud container clusters get-credentials $(terraform output -raw cluster_name) \
  --zone $(terraform output -raw zone) --project $(terraform output -raw project_id)

# Check n8n status
kubectl get pods -n $(terraform output -raw namespace)
kubectl get svc -n $(terraform output -raw namespace)
kubectl logs -n $(terraform output -raw namespace) -l app.kubernetes.io/name=n8n

# Check External Secrets
kubectl get externalsecret -n $(terraform output -raw namespace)
kubectl get secretstore -n $(terraform output -raw namespace)
kubectl describe externalsecret n8n-keys -n $(terraform output -raw namespace)
```

## Deployment Prerequisites

**Before running Terraform:**

1. Create secrets in GCP Secret Manager:
```sh
echo -n "$(openssl rand -hex 32)" | gcloud secrets create n8n-encryption-key \
  --data-file=- --project=YOUR_PROJECT_ID

echo -n "your-secure-password" | gcloud secrets create n8n-db-password \
  --data-file=- --project=YOUR_PROJECT_ID
```

2. Authenticate gcloud and install kubectl plugin:
```sh
gcloud auth application-default login
gcloud components install gke-gcloud-auth-plugin
```

**After first apply (cluster exists):**

3. Create Cloud SQL user (CRITICAL - n8n will fail without this):
```sh
gcloud container clusters get-credentials n8n-gke --zone europe-north1-a --project YOUR_PROJECT_ID

gcloud sql users create n8n \
  --instance=n8n-postgres \
  --password="your-secure-password" \
  --project=YOUR_PROJECT_ID
```

4. Re-run terraform apply to deploy n8n application

## File Organization (n8n/)

Resources are grouped by concern in separate files:

| File | Purpose | Key Resources |
|------|---------|--------------|
| `variables.tf` | Input variables (no defaults for required) | All `variable` blocks |
| `providers.tf` | Provider versions (pinned) | `terraform`, `required_providers` |
| `k8s_providers.tf` | K8s provider auth wiring | `kubernetes`, `helm`, `kubectl` providers |
| `apis.tf` | GCP API enablement (first step) | `google_project_service` |
| `network_gke.tf` | VPC + Private Service Access | `google_compute_network`, `google_service_networking_connection` |
| `gke.tf` | GKE cluster with Workload Identity | `google_container_cluster`, `google_container_node_pool` |
| `cloudsql.tf` | PostgreSQL instance (private IP only) | `google_sql_database_instance`, `google_sql_database` |
| `external_secrets.tf` | ESO + Workload Identity + ExternalSecrets | `kubectl_manifest` for CRDs, `helm_release` for ESO |
| `n8n.tf` | n8n namespace and Helm deployment | `kubernetes_namespace_v1`, `helm_release` |
| `outputs.tf` | Export cluster/DB info | `output` blocks |

## Troubleshooting

**n8n pod CrashLoopBackOff - "password authentication failed":**
```sh
# MOST COMMON ISSUE: Database user doesn't exist
gcloud sql users list --instance=n8n-postgres --project=YOUR_PROJECT_ID

# If n8n user missing, create it:
gcloud sql users create n8n \
  --instance=n8n-postgres \
  --password="your-secure-password" \
  --project=YOUR_PROJECT_ID

# Restart deployment
kubectl rollout restart deployment n8n -n n8n
```

**kubectl: "executable gke-gcloud-auth-plugin not found":**
```sh
gcloud components install gke-gcloud-auth-plugin
gcloud container clusters get-credentials n8n-gke --zone europe-north1-a
```

**ExternalSecret not syncing:**
```sh
# Check SecretStore status
kubectl get secretstore n8n-gcp-sm -n n8n -o yaml

# Check ExternalSecret status
kubectl describe externalsecret n8n-keys -n n8n

# Check ESO logs
kubectl logs -n n8n -l app.kubernetes.io/name=external-secrets
```

**n8n pod not starting:**
```sh
# Check if secrets exist
kubectl get secrets -n n8n

# Check pod logs
kubectl logs -n n8n -l app.kubernetes.io/name=n8n --tail=50

# Check pod events
kubectl describe pod -n n8n -l app.kubernetes.io/name=n8n

# Verify DB connection (check private IP matches Cloud SQL)
terraform output cloudsql_private_ip
```

**Workload Identity errors:**
- Ensure `depends_on = [google_container_cluster.gke]` exists in `external_secrets.tf:36`
- Wait 60s after IAM binding (handled by `time_sleep.wait_for_wi`)
- Verify annotation on K8s SA: `kubectl get sa external-secrets -n n8n -o yaml`

## Important Notes

- **Two-step deployment required**:
  1. First `terraform apply` creates cluster, Cloud SQL, and ESO
  2. Manually create database user: `gcloud sql users create n8n`
  3. Second `terraform apply` deploys n8n application

  **Why?** Terraform can't create Cloud SQL users (requires password), and n8n fails without the user.

- **No defaults on required vars**: Prevents accidental credential exposure. Always pass explicitly.

- **kubectl provider for CRDs**: Avoids plan-time errors when cluster doesn't exist yet. Don't replace with `kubernetes_manifest`.

- **Private Service Access**: Created in `network_gke.tf` before Cloud SQL. Don't remove `google_service_networking_connection`.

- **ESO Helm chart**: Now managed by Terraform (not manual install). Uses version 0.9.13.

- **License key is optional**: `n8n_license_activation_key_secret_name` defaults to `""` and is conditionally added to ExternalSecret.

- **kubectl plugin required**: Install `gke-gcloud-auth-plugin` before using kubectl with GKE.

## Coding Conventions

- 2-space indentation, `snake_case` naming
- Block comments (`/* */`) at file headers
- Resources grouped by concern in separate files
- Pin provider versions in `providers.tf` for reproducibility
- Use `depends_on` explicitly for Workload Identity and cross-provider dependencies
