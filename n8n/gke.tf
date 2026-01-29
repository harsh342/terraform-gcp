/*
  gke.tf
  - Creates a standard regional/zonally-located GKE cluster.
  - Removes default node pool and adds a managed node pool.
*/

resource "google_container_cluster" "gke" {
  name     = var.cluster_name
  location = var.zone

  network    = google_compute_network.vpc_network.id
  subnetwork = google_compute_subnetwork.subnet.id

  # Best practice: manage node pools explicitly
  remove_default_node_pool = true
  initial_node_count       = 1

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Workload Identity is enabled (useful later if you integrate Secret Manager, etc.)
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  depends_on = [google_project_service.apis]
}

resource "google_container_node_pool" "primary" {
  name       = "${var.cluster_name}-np"
  cluster    = google_container_cluster.gke.name
  location   = var.zone
  node_count = var.node_count

  node_config {
    machine_type = var.node_machine_type

    # Broad scope; you can tighten later (especially if you adopt Workload Identity properly).
    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]

    labels = {
      workload = "n8n"
    }
  }
}