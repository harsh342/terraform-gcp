/*
  outputs.tf
  - Useful outputs so you can quickly find cluster + namespace.
*/

output "project" {
  value = var.project_id
}

output "region" {
  value = var.region
}

output "zone" {
  value = var.zone
}

output "vpc_network_name" {
  value = google_compute_network.vpc_network.name
}

output "cluster_name" {
  value = google_container_cluster.gke.name
}

output "namespace" {
  value = var.namespace
}

output "cloudsql_instance_name" {
  value = google_sql_database_instance.n8n.name
}

output "cloudsql_private_ip" {
  value = google_sql_database_instance.n8n.private_ip_address
}

output "cloudsql_database" {
  value = google_sql_database.n8n.name
}

output "n8n_db_password" {
  value     = random_password.n8n_db_password.result
  sensitive = true
}
