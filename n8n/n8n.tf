/*
  n8n.tf
  - Creates a namespace
  - Relies on External Secrets to materialize:
      - N8N_ENCRYPTION_KEY
      - N8N_LICENSE_ACTIVATION_KEY (optional)
      - DB_POSTGRESDB_PASSWORD
  - Deploys n8n using the community-charts Helm chart.
  - Uses Cloud SQL (PostgreSQL) for persistence.
*/

resource "kubernetes_namespace_v1" "n8n" {
  metadata {
    name = var.namespace
  }

  depends_on = [google_container_node_pool.primary]
}

resource "helm_release" "n8n" {
  name       = "n8n"
  namespace  = kubernetes_namespace_v1.n8n.metadata[0].name
  repository = "https://community-charts.github.io/helm-charts"
  chart      = "n8n"
  version    = var.n8n_chart_version
  timeout    = 600 # Increase timeout to 10m to handle potential image pull or secret sync delays

  # All chart configuration passed as a values.yaml payload
  values = [yamlencode({
    timezone = var.n8n_timezone

    # --- Encryption key handling ---
    # Chart expects a secret containing the key: N8N_ENCRYPTION_KEY
    existingEncryptionKeySecret = "n8n-keys"

    # Database configuration - use external PostgreSQL
    db = {
      type = "postgresdb"
    }

    # External PostgreSQL configuration (Cloud SQL)
    externalPostgresql = {
      host           = google_sql_database_instance.n8n.private_ip_address
      port           = 5432
      database       = var.cloudsql_database_name
      username       = var.n8n_db_user
      existingSecret = "n8n-db"
    }

    # Disable in-cluster PostgreSQL
    postgresql = {
      enabled = false
    }

    # Extra environment variables for HTTP access
    extraEnvVars = {
      # Allow HTTP access (disable HTTPS requirement for dev/testing)
      N8N_SECURE_COOKIE = "false"
      # Disable SSL for webhook URLs
      N8N_PROTOCOL = "http"
    }

    # Service configuration
    service = {
      enabled = true
      type    = var.n8n_host == "" ? "LoadBalancer" : "ClusterIP"
      port    = 5678
    }

    # Ingress configuration
    ingress = {
      enabled   = var.n8n_host != ""
      className = "gce"
      hosts     = var.n8n_host != "" ? [{
        host  = var.n8n_host
        paths = [{ path = "/", pathType = "Prefix" }]
      }] : []
    }
  })]

  depends_on = [kubectl_manifest.n8n_keys, kubectl_manifest.n8n_db]
}
