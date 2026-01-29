/*
  apis.tf
  - Enables the APIs required for:
    - GKE (container.googleapis.com)
    - VPC/subnets (compute.googleapis.com)
    - IAM bindings (iam.googleapis.com)
*/

locals {
  required_apis = [
    "compute.googleapis.com",
    "container.googleapis.com",
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "servicenetworking.googleapis.com",
    "sqladmin.googleapis.com",
    "secretmanager.googleapis.com",
  ]
}

resource "google_project_service" "apis" {
  for_each           = toset(local.required_apis)
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}
