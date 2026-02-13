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
    name   = local.namespace
    labels = local.common_labels
  }

  depends_on = [google_container_node_pool.primary]
}

# Google-managed TLS certificate for HTTPS ingress
resource "kubectl_manifest" "n8n_managed_cert" {
  count = var.n8n_host != "" ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "networking.gke.io/v1"
    kind       = "ManagedCertificate"
    metadata = {
      name      = "${local.name_prefix}-cert"
      namespace = kubernetes_namespace_v1.n8n.metadata[0].name
    }
    spec = {
      domains = [var.n8n_host]
    }
  })

  depends_on = [kubernetes_namespace_v1.n8n]
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

    # Extra environment variables for protocol and webhook URL
    extraEnvVars = merge(
      {
        N8N_PROTOCOL      = var.n8n_host != "" ? "https" : "http"
        N8N_SECURE_COOKIE = var.n8n_host != "" ? "true" : "false"
      },
      # Set WEBHOOK_URL and N8N_EDITOR_BASE_URL so n8n generates correct webhook/editor URLs
      local.webhook_url != "" ? {
        WEBHOOK_URL         = "${local.webhook_url}/"
        N8N_EDITOR_BASE_URL = local.webhook_url
      } : {}
    )

    # Service configuration
    service = {
      enabled = true
      type    = var.n8n_host == "" ? "LoadBalancer" : "ClusterIP"
      port    = 5678
    }

    # Ingress disabled — managed separately via kubectl_manifest to set defaultBackend
    # (GKE's default-http-backend NEG may be missing, causing sync errors)
    ingress = {
      enabled = false
    }
  })]

  depends_on = [
    kubectl_manifest.n8n_keys,
    kubectl_manifest.n8n_db,
    kubectl_manifest.n8n_managed_cert,
    time_sleep.wait_for_secrets,
    google_sql_user.n8n
  ]
}

# Ingress managed outside Helm to set defaultBackend and avoid broken system default backend NEG
resource "kubectl_manifest" "n8n_ingress" {
  count = var.n8n_host != "" ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name      = "n8n"
      namespace = kubernetes_namespace_v1.n8n.metadata[0].name
      annotations = {
        "kubernetes.io/ingress.class"            = "gce"
        "networking.gke.io/managed-certificates" = "${local.name_prefix}-cert"
      }
    }
    spec = {
      defaultBackend = {
        service = {
          name = "n8n"
          port = { number = 5678 }
        }
      }
      rules = [{
        host = var.n8n_host
        http = {
          paths = [{
            path     = "/*"
            pathType = "ImplementationSpecific"
            backend = {
              service = {
                name = "n8n"
                port = { number = 5678 }
              }
            }
          }]
        }
      }]
    }
  })

  depends_on = [helm_release.n8n]
}
