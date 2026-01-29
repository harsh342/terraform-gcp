# terraform-gcp

Terraform configurations for provisioning and deploying infrastructure on Google Cloud Platform (GCP).

## Project Overview

This repository contains Infrastructure as Code (IaC) using Terraform to deploy resources on GCP. It consists of two main configurations:

1. **`learn/`** - A simple learning/sandbox configuration for basic GCP resources
2. **`n8n/`** - A production-ready configuration for deploying n8n workflow automation on GKE

## Repository Structure

```
terraform-gcp/
├── claude.md                 # Project documentation (this file)
├── learn/                    # Learning/sandbox Terraform config
│   └── main.tf               # Simple VPC + VM instance
└── n8n/                      # Production n8n deployment
    ├── README.md             # Detailed n8n deployment documentation
    ├── AGENTS.md             # Guidelines for AI agents
    ├── variables.tf          # Input variables
    ├── providers.tf          # Provider versions and config
    ├── apis.tf               # GCP API enablement
    ├── network_gke.tf        # VPC, subnets, Private Service Access
    ├── gke.tf                # GKE cluster and node pool
    ├── k8s_providers.tf      # Kubernetes/Helm/kubectl provider wiring
    ├── cloudsql.tf           # Cloud SQL PostgreSQL instance
    ├── external_secrets.tf   # External Secrets Operator + Workload Identity
    ├── n8n.tf                # n8n namespace and Helm release
    └── outputs.tf            # Output values
```

## Technology Stack

| Component | Technology | Version |
|-----------|------------|---------|
| IaC | Terraform | >= 1.5.0 |
| Cloud Provider | Google Cloud Platform | - |
| Terraform Provider | hashicorp/google | 6.8.0 |
| Kubernetes Provider | hashicorp/kubernetes | >= 2.25.0 |
| Helm Provider | hashicorp/helm | ~> 2.12.0 |
| Kubectl Provider | gavinbunney/kubectl | >= 1.14.0 |
| Container Orchestration | Google Kubernetes Engine (GKE) | - |
| Database | Cloud SQL (PostgreSQL 15) | - |
| Secrets Management | GCP Secret Manager + External Secrets Operator | - |
| Application | n8n (community Helm chart) | 1.16.25 |

## Configuration Details

### learn/ Directory

A minimal sandbox configuration for learning Terraform with GCP:
- Creates a VPC network (`terraform-network`)
- Provisions an `e2-micro` VM instance with Container-Optimized OS
- Uses `europe-north1` region

### n8n/ Directory

A comprehensive production configuration that deploys:

1. **Networking** (`network_gke.tf`)
   - Custom VPC (`n8n-network`) with manual subnets
   - Secondary IP ranges for GKE pods/services
   - Private Service Access for Cloud SQL

2. **GKE Cluster** (`gke.tf`)
   - Zonal GKE cluster with Workload Identity enabled
   - Managed node pool with `e2-standard-4` instances
   - VPC-native networking

3. **Cloud SQL** (`cloudsql.tf`)
   - PostgreSQL 15 instance with private IP only
   - Configurable tier and disk size

4. **External Secrets** (`external_secrets.tf`)
   - GCP Service Account with Secret Manager access
   - Kubernetes Service Account with Workload Identity binding
   - SecretStore and ExternalSecret resources using `kubectl_manifest`

5. **n8n Deployment** (`n8n.tf`)
   - Kubernetes namespace
   - Helm release using community-charts/n8n
   - Cloud SQL database connection via `externalPostgresql`
   - Optional ingress or LoadBalancer service

## Terraform Commands

```sh
# Initialize providers and state
terraform init

# Format all .tf files
terraform fmt -recursive

# Validate configuration syntax
terraform validate

# Preview changes
terraform plan -out tfplan

# Apply changes
terraform apply tfplan

# Destroy all resources
terraform destroy
```

## Deployment (n8n)

### Prerequisites

1. GCP project with billing enabled
2. `gcloud` CLI authenticated
3. Terraform >= 1.5.0 installed
4. kubectl installed

### Step 1: Create Secrets in GCP Secret Manager

```sh
# Create encryption key secret
echo -n "$(openssl rand -hex 32)" | gcloud secrets create n8n-encryption-key \
  --data-file=- --project=YOUR_PROJECT_ID

# Create database password secret
echo -n "your-secure-password" | gcloud secrets create n8n-db-password \
  --data-file=- --project=YOUR_PROJECT_ID
```

### Step 2: Deploy Infrastructure

```sh
export TF_VAR_n8n_encryption_key_secret_name="n8n-encryption-key"
export TF_VAR_n8n_db_password_secret_name="n8n-db-password"

cd n8n/
terraform init
terraform apply
```

### Step 3: Install External Secrets Operator

```sh
# Get cluster credentials
gcloud container clusters get-credentials n8n-gke --zone europe-north1-a

# Install ESO
kubectl apply --server-side -f https://github.com/external-secrets/external-secrets/releases/download/v0.12.1/external-secrets.yaml
```

### Step 4: Create Database User

```sh
gcloud sql users create n8n \
  --instance=n8n-postgres \
  --password="your-secure-password" \
  --project=YOUR_PROJECT_ID
```

### Step 5: Complete Deployment

```sh
terraform apply \
  -var="n8n_encryption_key_secret_name=n8n-encryption-key" \
  -var="n8n_db_password_secret_name=n8n-db-password"
```

## Key Variables (n8n)

| Variable | Description | Default |
|----------|-------------|---------|
| `project_id` | GCP project ID | (required, no default) |
| `region` | GCP region | `europe-north1` |
| `zone` | GCP zone | `europe-north1-a` |
| `network_name` | VPC network name | `n8n-network` |
| `cluster_name` | GKE cluster name | `n8n-gke` |
| `namespace` | Kubernetes namespace | `n8n` |
| `node_machine_type` | Node pool machine type | `e2-standard-4` |
| `node_count` | Number of nodes | `2` |
| `n8n_host` | Ingress hostname (optional) | `""` |
| `n8n_chart_version` | Helm chart version | `1.16.25` |
| `n8n_encryption_key_secret_name` | Secret Manager secret name | (required) |
| `n8n_db_password_secret_name` | Secret Manager secret name | (required) |

## Coding Conventions

- **Style**: Standard Terraform formatting with 2-space indentation
- **Naming**: `snake_case` for variables, resources, and outputs
- **Organization**: Resources grouped by concern (APIs, network, cluster, app)
- **Versioning**: Explicit provider and Helm chart versions for reproducibility
- **Comments**: Block comments (`/* */`) at file headers describing purpose

## Security Best Practices

1. **Secrets Management**
   - Secrets stored in GCP Secret Manager (not in Terraform state)
   - External Secrets Operator materializes secrets in-cluster
   - Workload Identity for secure GCP authentication

2. **Network Security**
   - Cloud SQL uses private IP only (no public access)
   - VPC-native GKE cluster
   - Private Service Access for managed services
   - Separate VPC (`n8n-network`) for isolation

3. **IAM**
   - Principle of least privilege for service accounts
   - `roles/secretmanager.secretAccessor` only for ESO service account

## Testing

- No automated tests defined
- Use `terraform validate` for syntax validation
- Review `terraform plan` output before applying changes

## Commit Guidelines

- Use short, imperative commit messages (e.g., "Add n8n ingress host input")
- PRs should include:
  - Summary of changes
  - `terraform plan` output
  - New variables or outputs documented

## Outputs (n8n)

After successful apply, the following outputs are available:

- `project` - GCP project ID
- `region` - GCP region
- `zone` - GCP zone
- `vpc_network_name` - VPC network name
- `cluster_name` - GKE cluster name
- `namespace` - Kubernetes namespace
- `cloudsql_instance_name` - Cloud SQL instance name
- `cloudsql_private_ip` - Cloud SQL private IP address
- `cloudsql_database` - Database name
