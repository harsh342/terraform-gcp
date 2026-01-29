# terraform-gcp

Terraform configurations for provisioning and deploying infrastructure on Google Cloud Platform (GCP).

## Overview

This repository contains Infrastructure as Code (IaC) using Terraform to deploy resources on GCP. It consists of two main configurations:

| Directory | Description | Documentation |
|-----------|-------------|---------------|
| `learn/` | Learning/sandbox configuration for basic GCP resources | [main.tf](learn/main.tf) |
| `n8n/` | Production n8n workflow automation on GKE | [README.md](n8n/README.md) |

## Quick Links

- 📖 [Project Documentation](claude.md) - Full project overview, tech stack, and conventions
- 🚀 [n8n Deployment Guide](n8n/README.md) - Step-by-step deployment instructions with diagrams
- 🤖 [AI Agent Guidelines](n8n/AGENTS.md) - Guidelines for AI-assisted development

## Technology Stack

| Component | Technology |
|-----------|------------|
| IaC | Terraform >= 1.5.0 |
| Cloud Provider | Google Cloud Platform |
| Container Orchestration | Google Kubernetes Engine (GKE) |
| Database | Cloud SQL (PostgreSQL 15) |
| Secrets Management | GCP Secret Manager + External Secrets Operator |
| Application | n8n (community Helm chart) |

## Getting Started

### Prerequisites

- GCP project with billing enabled
- `gcloud` CLI authenticated
- Terraform >= 1.5.0
- kubectl

### Deploy n8n

See the [n8n README](n8n/README.md) for complete deployment instructions.

```bash
cd n8n/
terraform init
terraform apply
```

## Repository Structure

```
terraform-gcp/
├── README.md                 # This file
├── claude.md                 # Project documentation
├── learn/                    # Learning/sandbox config
│   └── main.tf
└── n8n/                      # Production n8n deployment
    ├── README.md             # Deployment guide with diagrams
    ├── AGENTS.md             # AI agent guidelines
    ├── variables.tf
    ├── providers.tf
    ├── apis.tf
    ├── network_gke.tf
    ├── gke.tf
    ├── k8s_providers.tf
    ├── cloudsql.tf
    ├── external_secrets.tf
    ├── n8n.tf
    └── outputs.tf
```

## Documentation

| Document | Purpose |
|----------|---------|
| [claude.md](claude.md) | Comprehensive project documentation including tech stack, deployment steps, variables, and conventions |
| [n8n/README.md](n8n/README.md) | Detailed n8n deployment guide with Mermaid architecture diagrams |
| [n8n/AGENTS.md](n8n/AGENTS.md) | Guidelines for AI agents working with this codebase |

## License

This project is for internal use.
