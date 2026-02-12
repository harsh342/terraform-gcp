# Environment Configuration Files

This directory contains environment-specific Terraform variable files for deploying n8n infrastructure across multiple environments.

## Files

- `dev.tfvars` - Development environment configuration
- `staging.tfvars` - Staging environment configuration
- `production.tfvars` - Production environment configuration

## Usage

Use these files with the `-var-file` flag when running Terraform commands:

```sh
# Development
terraform plan -var-file=environments/dev.tfvars -out=tfplan-dev
terraform apply tfplan-dev

# Staging
terraform plan -var-file=environments/staging.tfvars -out=tfplan-staging
terraform apply tfplan-staging

# Production
terraform plan -var-file=environments/production.tfvars -out=tfplan-production
terraform apply tfplan-production
```

## Environment Differences

| Setting | Dev | Staging | Production |
|---------|-----|---------|------------|
| Node Type | e2-standard-2 | e2-standard-2 | e2-standard-4 |
| Node Count | 1 | 1 | 2 |
| SQL Tier | db-f1-micro | db-custom-2-7680 | db-custom-4-15360 |
| Disk Size | 10GB | 20GB | 100GB |
| Deletion Protection | false | true | true |
| Subnet CIDR | 10.10.0.0/16 | 10.20.0.0/16 | 10.30.0.0/16 |
| Pods CIDR | 10.11.0.0/16 | 10.21.0.0/16 | 10.31.0.0/16 |
| Services CIDR | 10.12.0.0/20 | 10.22.0.0/20 | 10.32.0.0/20 |

## Project Mapping

| Environment | GCP Project | GCS State Bucket |
|-------------|-------------|------------------|
| dev | `yesgaming-nonprod` | `yesgaming-tfstate-dev` |
| staging | `yesgaming-nonprod` | `yesgaming-tfstate-staging` |
| production | `boxwood-coil-484213-r6` | `yesgaming-tfstate-production` |

> Dev and staging share the same GCP project (`yesgaming-nonprod`). Production uses a separate project.

## Customization

Key values to review in each tfvars file:

1. `n8n_host` - Your domain name for n8n (empty = LoadBalancer, set = Ingress)
2. `node_machine_type` / `node_count` - Adjust compute capacity
3. `cloudsql_tier` / `cloudsql_disk_size_gb` - Adjust database capacity
4. Secret names - Must match secrets created in GCP Secret Manager (see [DEPLOYMENT.md](../DEPLOYMENT.md#4-create-secrets-in-secret-manager))

## Important Notes

- **Do not commit** files matching `*.auto.tfvars` or `local.tfvars` - these are in .gitignore
- Each environment requires its own GCS backend bucket for state storage
- Secrets must be created in GCP Secret Manager before deployment (see [DEPLOYMENT.md](../DEPLOYMENT.md))
- CIDR ranges are non-overlapping to allow future VPC peering if needed
