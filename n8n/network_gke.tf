/*
  network_gke.tf
  - Creates the VPC network using the SAME name you had in main.tf: "terraform-network".
  - Adds a custom subnet + secondary ranges required for VPC-native GKE (recommended).
*/

resource "google_compute_network" "vpc_network" {
  name                    = "${local.name_prefix}-network"
  auto_create_subnetworks = false

  depends_on = [google_project_service.apis]
}

resource "google_compute_subnetwork" "subnet" {
  name          = "${local.name_prefix}-subnet"
  region        = var.region
  network       = google_compute_network.vpc_network.id
  ip_cidr_range = var.subnet_cidr

  # Secondary ranges are used by GKE for Pods and Services IPs.
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pods_cidr
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_cidr
  }
}

# Private Services Access range for Cloud SQL private IP.
resource "google_compute_global_address" "private_services" {
  name          = "${local.name_prefix}-psa"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc_network.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.vpc_network.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_services.name]
}
