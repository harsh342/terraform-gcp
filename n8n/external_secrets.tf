/*
  external_secrets.tf
  - Wires External Secrets Operator (ESO) to Google Secret Manager via Workload Identity.
  - Creates ExternalSecrets that materialize K8s secrets used by n8n.
  - Uses kubectl_manifest instead of kubernetes_manifest to handle plan-time cluster absence.
  NOTE: ESO must be installed in the cluster separately.
*/

resource "google_service_account" "external_secrets" {
  account_id   = var.external_secrets_gcp_sa_name
  display_name = "n8n External Secrets"
}

resource "google_project_iam_member" "external_secrets_sm_access" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.external_secrets.email}"
}

resource "kubernetes_service_account_v1" "external_secrets" {
  metadata {
    name      = var.external_secrets_k8s_sa_name
    namespace = kubernetes_namespace_v1.n8n.metadata[0].name
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.external_secrets.email
    }
  }
}

resource "google_service_account_iam_member" "external_secrets_wi" {
  service_account_id = google_service_account.external_secrets.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.namespace}/${var.external_secrets_k8s_sa_name}]"

  # The Workload Identity pool only exists after the GKE cluster is created
  depends_on = [google_container_cluster.gke]
}

# Add a wait timer to allow Workload Identity bindings to propagate
resource "time_sleep" "wait_for_wi" {
  create_duration = "60s"

  depends_on = [google_service_account_iam_member.external_secrets_wi]
}

resource "helm_release" "external_secrets" {
  name       = "external-secrets"
  namespace  = kubernetes_namespace_v1.n8n.metadata[0].name
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = "0.9.13" # Pinning version for stability

  set {
    name  = "installCRDs"
    value = "true"
  }

  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = var.external_secrets_k8s_sa_name
  }

  depends_on = [
    kubernetes_service_account_v1.external_secrets,
    time_sleep.wait_for_wi
  ]
}

resource "kubectl_manifest" "secret_store" {
  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "SecretStore"
    metadata = {
      name      = var.external_secrets_store_name
      namespace = var.namespace
    }
    spec = {
      provider = {
        gcpsm = {
          projectID = var.project_id
          auth = {
            workloadIdentity = {
              clusterLocation = var.zone
              clusterName     = var.cluster_name
              serviceAccountRef = {
                name = var.external_secrets_k8s_sa_name
              }
            }
          }
        }
      }
    }
  })

  depends_on = [
    kubernetes_service_account_v1.external_secrets,
    helm_release.external_secrets
  ]
}

locals {
  n8n_keys_data = concat(
    [
      {
        secretKey = "N8N_ENCRYPTION_KEY"
        remoteRef = { key = var.n8n_encryption_key_secret_name }
      }
    ],
    var.n8n_license_activation_key_secret_name != "" ? [
      {
        secretKey = "N8N_LICENSE_ACTIVATION_KEY"
        remoteRef = { key = var.n8n_license_activation_key_secret_name }
      }
    ] : []
  )
}

resource "kubectl_manifest" "n8n_keys" {
  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "n8n-keys"
      namespace = var.namespace
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        name = var.external_secrets_store_name
        kind = "SecretStore"
      }
      target = {
        name = "n8n-keys"
      }
      data = local.n8n_keys_data
    }
  })

  depends_on = [kubectl_manifest.secret_store]
}

resource "kubectl_manifest" "n8n_db" {
  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "n8n-db"
      namespace = var.namespace
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        name = var.external_secrets_store_name
        kind = "SecretStore"
      }
      target = {
        name = "n8n-db"
      }
      data = [
        {
          secretKey = "postgres-password"
          remoteRef = { key = var.n8n_db_password_secret_name }
        }
      ]
    }
  })

  depends_on = [kubectl_manifest.secret_store]
}

# Add a wait timer to allow External Secrets to synchronize
resource "time_sleep" "wait_for_secrets" {
  create_duration = "30s"

  depends_on = [
    kubectl_manifest.n8n_keys,
    kubectl_manifest.n8n_db
  ]
}
