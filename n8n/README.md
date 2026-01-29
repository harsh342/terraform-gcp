# n8n on GKE - Terraform Configuration

This Terraform configuration deploys [n8n](https://n8n.io/) workflow automation platform on Google Kubernetes Engine (GKE) with Cloud SQL PostgreSQL backend and secure secrets management via External Secrets Operator.

## Architecture Overview

```mermaid
graph TB
    subgraph "Google Cloud Platform"
        subgraph "VPC Network: n8n-network"
            subgraph "GKE Cluster"
                subgraph "n8n Namespace"
                    N8N[n8n Pod]
                    K8S_SA[K8s Service Account]
                    K8S_SEC[K8s Secrets]
                end
                subgraph "default Namespace"
                    ESO[External Secrets Operator]
                end
                NP[Node Pool<br/>e2-standard-4]
            end
            
            subgraph "Subnet 10.10.0.0/16"
                PODS[Pod Range<br/>10.20.0.0/16]
                SVC[Service Range<br/>10.30.0.0/20]
            end
            
            subgraph "Private Service Access"
                CLOUDSQL[(Cloud SQL<br/>PostgreSQL 15)]
            end
        end
        
        SM[Secret Manager]
        GCP_SA[GCP Service Account]
        
        subgraph "GCP APIs"
            API1[Compute API]
            API2[Container API]
            API3[SQL Admin API]
            API4[Secret Manager API]
            API5[IAM API]
        end
    end
    
    USER((User)) -->|HTTPS| N8N
    N8N -->|Private IP| CLOUDSQL
    ESO -->|Workload Identity| GCP_SA
    GCP_SA -->|secretAccessor| SM
    ESO -->|Sync| K8S_SEC
    K8S_SEC -->|Mount| N8N
    K8S_SA -->|Annotated| GCP_SA
```

## Terraform Resource Workflow

This diagram shows the dependency chain and execution order of Terraform resources:

```mermaid
flowchart TD
    subgraph "Phase 1: Foundation"
        VAR[variables.tf<br/>Input Variables]
        PROV[providers.tf<br/>Provider Config]
        API[apis.tf<br/>Enable GCP APIs]
    end
    
    subgraph "Phase 2: Networking"
        VPC[VPC Network<br/>n8n-network]
        SUBNET[Subnet<br/>10.10.0.0/16]
        PSA[Private Service Access<br/>VPC Peering Range]
        SNC[Service Networking<br/>Connection]
    end
    
    subgraph "Phase 3: Compute & Database"
        GKE[GKE Cluster<br/>n8n-gke]
        NP[Node Pool<br/>e2-standard-4 x2]
        SQL[(Cloud SQL Instance<br/>PostgreSQL 15)]
        DB[(Database<br/>n8n)]
    end
    
    subgraph "Phase 4: IAM & Secrets"
        GCP_SA[GCP Service Account<br/>n8n-external-secrets]
        IAM[IAM Binding<br/>secretAccessor]
        WI[Workload Identity<br/>Binding]
    end
    
    subgraph "Phase 5: Kubernetes Resources"
        NS[Namespace<br/>n8n]
        K8S_SA[K8s Service Account<br/>external-secrets]
        SS[SecretStore<br/>n8n-gcp-sm]
        ES_KEYS[ExternalSecret<br/>n8n-keys]
        ES_DB[ExternalSecret<br/>n8n-db]
    end
    
    subgraph "Phase 6: Application"
        HELM[Helm Release<br/>n8n]
    end
    
    subgraph "Phase 7: Outputs"
        OUT[outputs.tf<br/>Export Values]
    end
    
    VAR --> PROV --> API
    API --> VPC --> SUBNET
    SUBNET --> PSA --> SNC
    
    VPC --> GKE
    SUBNET --> GKE
    API --> GKE
    GKE --> NP
    
    SNC --> SQL --> DB
    VPC --> SQL
    
    NP --> NS
    NS --> K8S_SA
    GCP_SA --> IAM
    GCP_SA --> WI
    K8S_SA --> WI
    K8S_SA --> SS
    SS --> ES_KEYS
    SS --> ES_DB
    
    ES_KEYS --> HELM
    ES_DB --> HELM
    SQL --> HELM
    
    HELM --> OUT
    GKE --> OUT
    SQL --> OUT
    VPC --> OUT
```

## Process Flow Diagram

Step-by-step deployment process showing what happens when you run `terraform apply`:

```mermaid
sequenceDiagram
    participant U as User
    participant TF as Terraform
    participant GCP as GCP APIs
    participant VPC as VPC Network
    participant GKE as GKE Cluster
    participant SQL as Cloud SQL
    participant SM as Secret Manager
    participant ESO as External Secrets
    participant K8S as Kubernetes
    participant N8N as n8n App

    U->>TF: terraform apply
    
    rect rgb(240, 248, 255)
        Note over TF,GCP: Phase 1: Enable APIs
        TF->>GCP: Enable compute.googleapis.com
        TF->>GCP: Enable container.googleapis.com
        TF->>GCP: Enable sqladmin.googleapis.com
        TF->>GCP: Enable secretmanager.googleapis.com
        TF->>GCP: Enable servicenetworking.googleapis.com
        GCP-->>TF: APIs Enabled
    end
    
    rect rgb(255, 248, 240)
        Note over TF,VPC: Phase 2: Create Network
        TF->>VPC: Create VPC (n8n-network)
        TF->>VPC: Create Subnet (10.10.0.0/16)
        TF->>VPC: Create Secondary Ranges (pods, services)
        TF->>VPC: Reserve Private Service Access Range
        TF->>VPC: Create VPC Peering Connection
        VPC-->>TF: Network Ready
    end
    
    rect rgb(240, 255, 240)
        Note over TF,SQL: Phase 3: Create Database
        TF->>SQL: Create Cloud SQL Instance
        TF->>SQL: Create Database (n8n)
        SQL-->>TF: Database Ready (Private IP)
    end
    
    rect rgb(255, 240, 255)
        Note over TF,GKE: Phase 4: Create GKE Cluster
        TF->>GKE: Create GKE Cluster
        TF->>GKE: Enable Workload Identity
        TF->>GKE: Create Node Pool
        GKE-->>TF: Cluster Ready
    end
    
    rect rgb(255, 255, 240)
        Note over TF,SM: Phase 5: Setup IAM & Secrets
        TF->>GCP: Create GCP Service Account
        TF->>GCP: Grant secretAccessor Role
        TF->>K8S: Create Namespace (n8n)
        TF->>K8S: Create K8s Service Account
        TF->>GCP: Bind Workload Identity
        TF->>K8S: Create SecretStore (kubectl_manifest)
        TF->>K8S: Create ExternalSecret (n8n-keys)
        TF->>K8S: Create ExternalSecret (n8n-db)
        ESO->>SM: Fetch Secrets
        SM-->>ESO: Return Secret Values
        ESO->>K8S: Create K8s Secrets
    end
    
    rect rgb(240, 255, 255)
        Note over TF,N8N: Phase 6: Deploy n8n
        TF->>K8S: Helm Install n8n
        K8S->>N8N: Create Deployment
        K8S->>N8N: Mount Secrets
        K8S->>N8N: Create Service (LoadBalancer/Ingress)
        N8N->>SQL: Connect via Private IP
        N8N-->>TF: Deployment Complete
    end
    
    TF-->>U: Apply Complete + Outputs
```

## File Responsibilities

```mermaid
graph LR
    subgraph "Configuration Files"
        V[variables.tf]
        P[providers.tf]
    end
    
    subgraph "Infrastructure Files"
        A[apis.tf]
        N[network_gke.tf]
        G[gke.tf]
        C[cloudsql.tf]
    end
    
    subgraph "Application Files"
        K[k8s_providers.tf]
        E[external_secrets.tf]
        N8N[n8n.tf]
    end
    
    subgraph "Output Files"
        O[outputs.tf]
    end
    
    V -->|Provides inputs to| A
    V -->|Provides inputs to| N
    V -->|Provides inputs to| G
    V -->|Provides inputs to| C
    V -->|Provides inputs to| E
    V -->|Provides inputs to| N8N
    
    P -->|Configures| A
    A -->|Enables APIs for| N
    A -->|Enables APIs for| G
    N -->|Provides network for| G
    N -->|Provides PSA for| C
    G -->|Provides cluster for| K
    K -->|Configures providers for| E
    K -->|Configures providers for| N8N
    E -->|Provides secrets for| N8N
    C -->|Provides DB connection for| N8N
    
    G -->|Exports to| O
    C -->|Exports to| O
    N -->|Exports to| O
```

## Secrets Flow Diagram

How secrets are securely managed from GCP Secret Manager to n8n:

```mermaid
flowchart LR
    subgraph "GCP Secret Manager"
        S1[encryption-key-secret]
        S2[db-password-secret]
    end
    
    subgraph "IAM"
        GSA[GCP Service Account<br/>n8n-external-secrets]
        ROLE[roles/secretmanager<br/>.secretAccessor]
    end
    
    subgraph "Workload Identity"
        WI[Workload Identity<br/>Binding]
    end
    
    subgraph "Kubernetes"
        KSA[K8s Service Account<br/>external-secrets]
        SS[SecretStore<br/>n8n-gcp-sm]
        
        subgraph "ExternalSecrets"
            ES1[n8n-keys]
            ES2[n8n-db]
        end
        
        subgraph "K8s Secrets"
            KS1[n8n-keys<br/>N8N_ENCRYPTION_KEY]
            KS2[n8n-db<br/>postgres-password]
        end
    end
    
    subgraph "n8n Pod"
        ENV[Environment Variables]
    end
    
    GSA --> ROLE
    ROLE --> S1
    ROLE --> S2
    
    KSA -->|Annotated with| GSA
    GSA <-->|Workload Identity| WI
    WI <--> KSA
    
    KSA --> SS
    SS --> ES1
    SS --> ES2
    
    ES1 -->|Syncs| S1
    ES2 -->|Syncs| S2
    
    ES1 -->|Creates| KS1
    ES2 -->|Creates| KS2
    
    KS1 -->|Mounts as| ENV
    KS2 -->|Mounts as| ENV
```

## Network Architecture

```mermaid
graph TB
    subgraph "Internet"
        USER((Users))
    end
    
    subgraph "GCP Project: YOUR_PROJECT_ID"
        subgraph "VPC: n8n-network"
            subgraph "Region: europe-north1"
                subgraph "Subnet: n8n-network-subnet<br/>10.10.0.0/16"
                    subgraph "GKE Cluster: n8n-gke"
                        subgraph "Pod Range: 10.20.0.0/16"
                            N8N_POD[n8n Pod]
                            ESO_POD[ESO Pod]
                        end
                        subgraph "Service Range: 10.30.0.0/20"
                            LB[LoadBalancer<br/>or Ingress]
                        end
                    end
                end
                
                subgraph "Private Service Access"
                    CLOUDSQL[(Cloud SQL<br/>PostgreSQL 15<br/>Private IP)]
                end
            end
            
            PEERING[VPC Peering<br/>servicenetworking.googleapis.com]
        end
    end
    
    USER -->|HTTPS| LB
    LB --> N8N_POD
    N8N_POD -->|Port 5432| CLOUDSQL
    PEERING --- CLOUDSQL
```

## Quick Start

### Prerequisites

1. GCP project with billing enabled
2. `gcloud` CLI authenticated (`gcloud auth application-default login`)
3. Terraform >= 1.5.0
4. kubectl installed

### Step 1: Create Secrets in GCP Secret Manager

**Before running Terraform**, create the required secrets:

```bash
# Generate and store the n8n encryption key
echo -n "$(openssl rand -hex 32)" | gcloud secrets create n8n-encryption-key \
  --data-file=- --project=YOUR_PROJECT_ID

# Store the database password (use a secure password)
echo -n "your-secure-db-password" | gcloud secrets create n8n-db-password \
  --data-file=- --project=YOUR_PROJECT_ID
```

### Step 2: Deploy Infrastructure

```bash
# Set required environment variables
export TF_VAR_n8n_encryption_key_secret_name="n8n-encryption-key"
export TF_VAR_n8n_db_password_secret_name="n8n-db-password"

# Initialize and apply
cd n8n/
terraform init
terraform apply
```

### Step 3: Install External Secrets Operator

After the GKE cluster is created, install ESO:

```bash
# Get cluster credentials
gcloud container clusters get-credentials n8n-gke --zone europe-north1-a --project YOUR_PROJECT_ID

# Install ESO using kubectl (server-side apply for large CRDs)
kubectl apply --server-side -f https://github.com/external-secrets/external-secrets/releases/download/v0.12.1/external-secrets.yaml

# Wait for ESO pods to be ready
kubectl get pods -A | grep external
```

### Step 4: Create Database User

```bash
# Create the n8n database user in Cloud SQL
gcloud sql users create n8n \
  --instance=n8n-postgres \
  --password="your-secure-db-password" \
  --project=YOUR_PROJECT_ID
```

### Step 5: Complete Deployment

```bash
# Re-run terraform to create K8s resources
terraform apply \
  -var="n8n_encryption_key_secret_name=n8n-encryption-key" \
  -var="n8n_db_password_secret_name=n8n-db-password"
```

### Step 6: Access n8n

```bash
# Get the LoadBalancer IP
kubectl get svc -n n8n

# Access n8n at http://<EXTERNAL-IP>:5678
```

## Provider Versions

| Provider | Source | Version |
|----------|--------|---------|
| google | hashicorp/google | 6.8.0 |
| kubernetes | hashicorp/kubernetes | >= 2.25.0 |
| helm | hashicorp/helm | ~> 2.12.0 |
| kubectl | gavinbunney/kubectl | >= 1.14.0 |

**Note**: The `kubectl` provider is used for Custom Resource Definitions (SecretStore, ExternalSecret) because it handles the chicken-and-egg problem where these resources need to be planned before the cluster exists.

## Variables Reference

| Variable | Description | Default |
|----------|-------------|---------|
| `project_id` | GCP project ID | (required, no default) |
| `region` | GCP region | `europe-north1` |
| `zone` | GCP zone | `europe-north1-a` |
| `network_name` | VPC network name | `n8n-network` |
| `cluster_name` | GKE cluster name | `n8n-gke` |
| `namespace` | K8s namespace | `n8n` |
| `node_machine_type` | Node VM type | `e2-standard-4` |
| `node_count` | Number of nodes | `2` |
| `n8n_timezone` | Container timezone | `Europe/London` |
| `n8n_host` | Ingress hostname | `""` (uses LoadBalancer) |
| `n8n_chart_version` | Helm chart version | `1.16.25` |
| `cloudsql_tier` | Cloud SQL tier | `db-custom-2-7680` |
| `cloudsql_disk_size_gb` | Disk size | `50` |
| `n8n_encryption_key_secret_name` | Secret Manager secret name for encryption key | (required) |
| `n8n_db_password_secret_name` | Secret Manager secret name for DB password | (required) |

## Outputs

| Output | Description |
|--------|-------------|
| `project` | GCP project ID |
| `region` | Deployment region |
| `zone` | Deployment zone |
| `vpc_network_name` | VPC network name |
| `cluster_name` | GKE cluster name |
| `namespace` | Kubernetes namespace |
| `cloudsql_instance_name` | Cloud SQL instance name |
| `cloudsql_private_ip` | Cloud SQL private IP |
| `cloudsql_database` | Database name |

## Security Considerations

- **No secrets in Terraform state**: All sensitive values stored in GCP Secret Manager
- **Private networking**: Cloud SQL accessible only via private IP
- **Workload Identity**: Secure GCP authentication without service account keys
- **Least privilege**: ESO service account has only `secretAccessor` role
- **Separate VPC**: n8n uses its own VPC (`n8n-network`) isolated from other workloads

## Troubleshooting

### External Secrets not syncing

```bash
# Check ExternalSecret status
kubectl get externalsecret -n n8n

# Check ESO logs
kubectl logs -n default -l app.kubernetes.io/name=external-secrets

# Verify SecretStore is valid
kubectl get secretstore -n n8n
```

### n8n pod not starting

```bash
# Check pod status
kubectl get pods -n n8n

# Check pod events
kubectl describe pod -n n8n -l app.kubernetes.io/name=n8n

# Check if secrets exist
kubectl get secrets -n n8n
```

### Database connection issues

```bash
# Verify Cloud SQL private IP
terraform output cloudsql_private_ip

# Check if database user exists
gcloud sql users list --instance=n8n-postgres --project=YOUR_PROJECT_ID
```

## Terraform Commands

```bash
terraform init              # Initialize providers
terraform fmt -recursive    # Format .tf files
terraform validate          # Validate syntax
terraform plan -out tfplan  # Preview changes
terraform apply tfplan      # Apply changes
terraform destroy           # Tear down all resources
```
