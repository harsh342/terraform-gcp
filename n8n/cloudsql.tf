/*
  cloudsql.tf
  - Provisions a private-IP Cloud SQL (PostgreSQL) instance for n8n.
  - Creates the database and database user with a secure random password.
  - Stores the password in Secret Manager for External Secrets to sync.
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

# Generate a secure random password for the database user
resource "random_password" "n8n_db_password" {
  length  = 32
  special = true
}

# Create the database user
resource "google_sql_user" "n8n" {
  name     = var.n8n_db_user
  instance = google_sql_database_instance.n8n.name
  password = random_password.n8n_db_password.result

  depends_on = [google_sql_database.n8n]
}

# Check if the Secret Manager secret exists
data "google_secret_manager_secret" "n8n_db_password" {
  secret_id = var.n8n_db_password_secret_name
  project   = var.project_id
}

# Store the password in Secret Manager (create a new version)
resource "google_secret_manager_secret_version" "n8n_db_password" {
  secret      = data.google_secret_manager_secret.n8n_db_password.id
  secret_data = random_password.n8n_db_password.result

  depends_on = [google_sql_user.n8n]
}
