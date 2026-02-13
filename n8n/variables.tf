/*
  variables.tf
  - Inputs with sensible defaults for region and zone:
      region:  europe-north1
      zone:    europe-north1-a
  - project_id is required (no default) to avoid exposing project IDs in public repos
  - Also includes n8n + database settings and secrets.
*/

variable "project_id" {
  type        = string
  description = "GCP project id (required - set via TF_VAR_project_id or terraform.tfvars)"
  # No default - must be provided to avoid exposing project IDs in public repos
}

variable "environment" {
  type        = string
  description = "Environment: dev, staging, production"
  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Must be dev, staging, or production"
  }
}

variable "org_prefix" {
  type        = string
  description = "Org prefix for naming (e.g., 'yesgaming')"
  default     = ""
}

variable "region" {
  type        = string
  description = "GCP region"
}

variable "zone" {
  type        = string
  description = "GCP zone"
}

variable "network_name" {
  type        = string
  description = "VPC network name for n8n infrastructure"
}

variable "subnet_cidr" {
  type        = string
  description = "Primary subnet CIDR"
}

variable "pods_cidr" {
  type        = string
  description = "Secondary range for pods"
}

variable "services_cidr" {
  type        = string
  description = "Secondary range for services"
}

variable "cluster_name" {
  type        = string
  description = "GKE cluster name"
}

variable "namespace" {
  type        = string
  description = "Kubernetes namespace for n8n"
  default     = ""
}

variable "node_machine_type" {
  type        = string
  description = "Node pool machine type"
  default     = "e2-standard-4"
}

variable "node_count" {
  type        = number
  description = "Node count for the primary node pool"
  default     = 2
}

variable "n8n_timezone" {
  type        = string
  description = "Timezone inside the n8n container"
  default     = "Europe/London"
}

# Secret Manager secret names (no secret payloads stored in Terraform state).
variable "n8n_encryption_key_secret_name" {
  type        = string
  description = "Secret Manager secret name holding N8N_ENCRYPTION_KEY."
}

variable "n8n_license_activation_key_secret_name" {
  type        = string
  description = "Secret Manager secret name holding N8N_LICENSE_ACTIVATION_KEY (optional)."
  default     = ""
}

variable "n8n_db_password_secret_name" {
  type        = string
  description = "Secret Manager secret name holding the Cloud SQL password."
}

variable "n8n_db_user" {
  type        = string
  description = "Cloud SQL database user for n8n (user must exist)."
}

variable "cloudsql_instance_name" {
  type        = string
  description = "Cloud SQL instance name."
}

variable "cloudsql_database_name" {
  type        = string
  description = "Cloud SQL database name."
}

variable "cloudsql_tier" {
  type        = string
  description = "Cloud SQL machine tier."
  default     = "db-custom-2-7680"
}

variable "cloudsql_disk_size_gb" {
  type        = number
  description = "Cloud SQL disk size in GB."
  default     = 50
}

variable "cloudsql_deletion_protection" {
  type        = bool
  description = "Protect the Cloud SQL instance from deletion."
  default     = false
}

variable "external_secrets_k8s_sa_name" {
  type        = string
  description = "Kubernetes service account used by External Secrets Operator."
  default     = "external-secrets"
}

variable "external_secrets_gcp_sa_name" {
  type        = string
  description = "GCP service account name used for Secret Manager access."
}

variable "external_secrets_store_name" {
  type        = string
  description = "SecretStore name for External Secrets."
  default     = "n8n-gcp-sm"
}

# Optional: hostname for ingress (if empty, chart will use LoadBalancer service).
variable "n8n_host" {
  type        = string
  description = "Public hostname for n8n HTTPS ingress with Google-managed TLS certificate. Example: n8n-dev.theyes.cloud"
  default     = ""
}

# Optional: explicit webhook/editor base URL for n8n.
# Required for LoadBalancer setups where the external IP is dynamic.
# If unset and n8n_host is provided, the URL is derived from n8n_host automatically.
variable "n8n_webhook_url" {
  type        = string
  description = "External base URL for n8n webhooks and editor. Overrides the URL derived from n8n_host. Example: http://34.88.223.46:5678"
  default     = ""
}

# Helm chart version for community-charts/n8n.
# Pinning is recommended for repeatable deployments.
variable "n8n_chart_version" {
  type        = string
  description = "Helm chart version for community-charts/n8n"
  default     = "1.16.25"
}

locals {
  namespace   = var.namespace != "" ? var.namespace : "n8n-${var.environment}"
  name_prefix = var.org_prefix != "" ? "${var.org_prefix}-n8n-${var.environment}" : "n8n-${var.environment}"

  # Effective webhook URL: explicit override > derived from n8n_host > empty (n8n defaults to localhost)
  webhook_url = var.n8n_webhook_url != "" ? var.n8n_webhook_url : (
    var.n8n_host != "" ? "https://${var.n8n_host}" : ""
  )

  common_labels = {
    environment = var.environment
    managed_by  = "terraform"
    application = "n8n"
  }
}
