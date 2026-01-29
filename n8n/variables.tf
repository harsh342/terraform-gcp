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

variable "region" {
  type        = string
  description = "GCP region"
  default     = "europe-north1"
}

variable "zone" {
  type        = string
  description = "GCP zone"
  default     = "europe-north1-a"
}

variable "network_name" {
  type        = string
  description = "VPC network name for n8n infrastructure"
  default     = "n8n-network"
}

variable "cluster_name" {
  type        = string
  description = "GKE cluster name"
  default     = "n8n-gke"
}

variable "namespace" {
  type        = string
  description = "Kubernetes namespace for n8n"
  default     = "n8n"
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
  default     = "n8n"
}

variable "cloudsql_instance_name" {
  type        = string
  description = "Cloud SQL instance name."
  default     = "n8n-postgres"
}

variable "cloudsql_database_name" {
  type        = string
  description = "Cloud SQL database name."
  default     = "n8n"
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
  default     = "n8n-external-secrets"
}

variable "external_secrets_store_name" {
  type        = string
  description = "SecretStore name for External Secrets."
  default     = "n8n-gcp-sm"
}

# Optional: hostname for ingress (if empty, chart will use LoadBalancer service).
variable "n8n_host" {
  type        = string
  description = "Public hostname for n8n ingress. Example: n8n.example.com (optional)."
  default     = ""
}

# Helm chart version for community-charts/n8n.
# Pinning is recommended for repeatable deployments.
variable "n8n_chart_version" {
  type        = string
  description = "Helm chart version for community-charts/n8n"
  default     = "1.16.25"
}
