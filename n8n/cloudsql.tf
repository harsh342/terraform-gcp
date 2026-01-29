/*
  cloudsql.tf
  - Provisions a private-IP Cloud SQL (PostgreSQL) instance for n8n.
  - Creates the database; the DB user/password are managed outside Terraform.
*/

resource "google_sql_database_instance" "n8n" {
  name                = var.cloudsql_instance_name
  region              = var.region
  database_version    = "POSTGRES_15"
  deletion_protection = var.cloudsql_deletion_protection

  settings {
    tier      = var.cloudsql_tier
    disk_size = var.cloudsql_disk_size_gb

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.vpc_network.id
    }
  }

  depends_on = [google_service_networking_connection.private_vpc_connection]
}

resource "google_sql_database" "n8n" {
  name     = var.cloudsql_database_name
  instance = google_sql_database_instance.n8n.name
}
