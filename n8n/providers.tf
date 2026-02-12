/*
  providers.tf
  - Pins Terraform providers.
  - Uses the Google provider version requested (6.8.0), matching your main.tf.
*/

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "6.8.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.25.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  backend "gcs" {
    # Bucket specified during init: terraform init -backend-config="bucket=yesgaming-tfstate-dev"
    prefix = "n8n"
  }
}

# Google provider config (defaults come from variables.tf, matching your original main.tf values)
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}