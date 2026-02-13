# terraform-gcp

Terraform configurations for deploying infrastructure on Google Cloud Platform.

## Overview

This repository contains the following Terraform configuration:

| Directory | Description | Documentation |
|-----------|-------------|---------------|
| **`n8n/`** | Multi-environment n8n deployment on GKE with Cloud SQL | [README](n8n/README.md) · [Deployment Guide](n8n/DEPLOYMENT.md) |

## Quick Start

### Deploy n8n (Development)

```bash
# 1. Create GCS backend and secrets (see n8n/DEPLOYMENT.md for full steps)
gcloud storage buckets create gs://yesgaming-tfstate-dev \
  --project=yesgaming-nonprod --location=europe-north1 --uniform-bucket-level-access
echo -n "$(openssl rand -hex 32)" | gcloud secrets create n8n-dev-encryption-key \
  --data-file=- --project=yesgaming-nonprod --replication-policy="automatic"

# 2. Deploy infrastructure
cd n8n/
terraform workspace new dev
terraform init -backend-config="bucket=yesgaming-tfstate-dev"
terraform apply -var-file=environments/dev.tfvars

# 3. Access n8n
kubectl get svc -n $(terraform output -raw namespace)
```

**For detailed instructions:** See [n8n Deployment Guide](n8n/DEPLOYMENT.md)

## Architecture

The n8n deployment supports **3 isolated environments** (dev/staging/production):

```
GCP Organization
├── yesgaming-nonprod
│   ├── dev     → https://n8n-dev.theyes.cloud   → gs://yesgaming-tfstate-dev/n8n/
│   └── staging → https://n8n-stage.theyes.cloud → gs://yesgaming-tfstate-staging/n8n/
└── boxwood-coil-484213-r6
    └── prod    → https://n8n.theyes.cloud       → gs://yesgaming-tfstate-production/n8n/
```

**Key features:**
- Separate GCP projects (dev/staging share `yesgaming-nonprod`, production uses `boxwood-coil-484213-r6`)
- GCS backend for state management
- Terraform workspaces for organization
- Non-overlapping CIDR ranges (10.10.x, 10.20.x, 10.30.x)
- Dynamic resource naming: `yesgaming-n8n-{env}-{resource}`

## Technology Stack

| Component | Technology | Version |
|-----------|------------|---------|
| Infrastructure | Terraform | ≥ 1.5.0 |
| Cloud Provider | Google Cloud Platform | - |
| Orchestration | Google Kubernetes Engine | - |
| Database | Cloud SQL PostgreSQL | 15 |
| Secrets | Secret Manager + External Secrets Operator | 0.9.13 |
| Application | n8n (Helm chart) | 1.16.25 |

## Documentation

| Document | Purpose | Audience |
|----------|---------|----------|
| **[CLAUDE.md](CLAUDE.md)** | Technical reference for AI assistants and developers | Comprehensive architecture, patterns, troubleshooting |
| **[n8n/README.md](n8n/README.md)** | n8n quick start and architecture diagrams | Getting started quickly |
| **[n8n/DEPLOYMENT.md](n8n/DEPLOYMENT.md)** | Complete multi-environment deployment guide | Production deployments |
| **[n8n/environments/README.md](n8n/environments/README.md)** | Environment configuration details | Environment customization |

## Prerequisites

- GCP project with billing enabled
- `gcloud` CLI authenticated: `gcloud auth application-default login`
- Terraform ≥ 1.5.0: [Download](https://www.terraform.io/downloads)
- kubectl + `gke-gcloud-auth-plugin`: `gcloud components install kubectl gke-gcloud-auth-plugin`

## Key Patterns

### Multi-Environment Strategy
- **Workspaces:** One per environment (dev/staging/production)
- **State isolation:** Separate GCS buckets per environment
- **Project isolation:** Each environment in its own GCP project
- **CIDR allocation:** Non-overlapping for future VPC peering

### Security
- **Zero secrets in state:** All secrets in GCP Secret Manager
- **Workload Identity:** No service account keys
- **Private networking:** Cloud SQL accessible via private IP only
- **Least privilege IAM:** Minimal role assignments

### Resource Organization
```
n8n/
├── providers.tf          # Versions + GCS backend
├── variables.tf          # Inputs + dynamic locals
├── environments/         # Per-environment tfvars
│   ├── dev.tfvars
│   ├── staging.tfvars
│   └── production.tfvars
├── apis.tf              # API enablement
├── network_gke.tf       # VPC + Private Service Access
├── gke.tf               # Cluster + node pools
├── cloudsql.tf          # PostgreSQL + auto password
├── k8s_providers.tf     # K8s provider wiring
├── external_secrets.tf  # ESO + Workload Identity
├── n8n.tf               # n8n Helm deployment
└── outputs.tf           # Cluster/DB metadata
```

## Common Commands

```bash
# Format and validate
terraform fmt -recursive
terraform validate

# Deploy to environment
terraform workspace select dev
terraform plan -var-file=environments/dev.tfvars -out=tfplan-dev
terraform apply tfplan-dev

# Get cluster credentials
gcloud container clusters get-credentials $(terraform output -raw cluster_name) \
  --zone $(terraform output -raw zone) --project $(terraform output -raw project_id)

# Check deployment status
kubectl get pods -n $(terraform output -raw namespace)
kubectl get externalsecret -n $(terraform output -raw namespace)
```

## Troubleshooting

**Quick diagnostic:**
```bash
# Check all components
kubectl get pods,svc,externalsecret -n $(terraform output -raw namespace)

# View n8n logs
kubectl logs -n $(terraform output -raw namespace) -l app.kubernetes.io/name=n8n --tail=50

# Check External Secrets sync
kubectl describe externalsecret n8n-keys -n $(terraform output -raw namespace)
```

**Common issues:**
- **Database authentication errors:** Check Cloud SQL user exists
- **ExternalSecret not syncing:** Verify Workload Identity binding (wait 60s)
- **kubectl plugin error:** Install `gke-gcloud-auth-plugin`

See [CLAUDE.md](CLAUDE.md#troubleshooting) for detailed troubleshooting.

## Support

- **Architecture questions:** See [CLAUDE.md](CLAUDE.md)
- **Deployment help:** See [n8n/DEPLOYMENT.md](n8n/DEPLOYMENT.md)
- **Issues:** Check troubleshooting sections in documentation above

## License

Internal use only.
