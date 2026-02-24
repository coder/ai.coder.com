provider "aws" {
  region  = var.region
  profile = var.profile
}

data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = var.cluster_name
}

data "aws_iam_openid_connect_provider" "this" {
  url = data.aws_eks_cluster.this.identity[0].oidc[0].issuer
}

data "aws_db_instance" "litellm" {
  db_instance_identifier = var.db_rds_id
}

data "aws_region" "this" {}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes = {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

locals {
  common_name = replace(replace(var.host_name, "https://", ""), "http://", "")
  ssl_vol_friendly_name = replace(local.common_name, ".", "-")
}

resource "kubernetes_manifest" "cert" {

  field_manager {
    force_conflicts = true
  }
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      labels    = {} # var.cert_labels
      name      = local.ssl_vol_friendly_name
      namespace = module.litellm.namespace
    }
    spec = {
      secretName  = local.ssl_vol_friendly_name
      commonName  = local.common_name
      dnsNames    = [local.common_name]
      duration    = "${90 * 24}h"
      renewBefore = "8h"
      additionalOutputFormats = [{
        type = "CombinedPEM"
      },{
        type = "DER"
      }]
      issuerRef = {
        kind = "ClusterIssuer"
        name = "issuer"
      }
    }
  }
}

resource "kubernetes_secret_v1" "gcloud" {
  metadata {
    name      = "gcloud-auth"
    namespace = module.litellm.namespace
    labels    = {}
  }
  data = {
    "service_account.json" = var.gcloud_auth
  }
}

locals {
  azs = slice(var.azs, 0, 1)
  pub_subs = [for az in local.azs : "${var.vpc_name}-public-${data.aws_region.this.region}${az}"]
  # App port is actually being ignored on the LiteLLM app-level. Statically set to 4000
  app_port = 4000
  # release_name = "coder"
  # chart_name = "coder"
  # namespace = "coder"
}

resource "aws_eip" "litellm" {
  count = length(local.pub_subs)
  domain           = "vpc"
  public_ipv4_pool = "amazon"
  tags = {
    Name = "litellm-eip-${count.index}"
  }
}

module "litellm" {
  source = "../../../../../modules/k8s/bootstrap/litellm"

  cluster_name              = var.cluster_name
  cluster_oidc_provider_arn = data.aws_iam_openid_connect_provider.this.arn
  namespace                 = var.addon_namespace
  
  access_url                 = var.host_name
  replicas                    = 8

  litellm_master_key          = var.litellm_master_key

  service_lb_class = "service.k8s.aws/nlb"
  svc_port = local.app_port
  svc_annots = {
    "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type"      = "ip"
    "service.beta.kubernetes.io/aws-load-balancer-scheme"               = "internet-facing"
    "service.beta.kubernetes.io/aws-load-balancer-attributes"           = "deletion_protection.enabled=false"
    "service.beta.kubernetes.io/aws-load-balancer-healthcheck-protocol" = "https"
    "service.beta.kubernetes.io/aws-load-balancer-healthcheck-port" = "${local.app_port}"
    "service.beta.kubernetes.io/aws-load-balancer-eip-allocations"      = join(",", aws_eip.litellm.*.allocation_id)
    "service.beta.kubernetes.io/aws-load-balancer-subnets"              = join(",", local.pub_subs)
  }
  node_selector = {}
  tolerations = [{
    key = "CriticalAddonsOnly"
    operator = "Exists"
  },{
    key = "dedicated"
    value = "general"
    effect = "NoSchedule"
  }]
  affinity = {
    nodeAffinity = {
      requiredDuringSchedulingIgnoredDuringExecution = {
        nodeSelectorTerms = [{
          matchExpressions = [
            {
              key = "topology.kubernetes.io/zone"
              operator = "In"
              values = [for az in local.azs : "${data.aws_region.this.region}${az}"]
            },
            {
              key = "eks.amazonaws.com/compute-type",
              operator = "In",
              values = ["auto"]
            }
          ] 
        }]
      }
    }
  }

  db = {
    use_existing = true
    db_name = "litellm"
    endpoint = data.aws_db_instance.litellm.endpoint
    username = "litellm"
    admin_password = var.db_admin_password
    user_password = var.db_user_password
  }

  proxy_config = {
    general_settings = {
      master_key = "os.environ/PROXY_MASTER_KEY"

      store_model_in_db = true
      store_prompts_in_spend_logs = true
      proxy_batch_write_at = 60
      database_connection_pool_limit = 10

      disable_error_logs = true
      allow_requests_on_db_unavailable = true
    }

    litellm_settings = {
      allowed_fails   = 3
      cooldown_time   = 30
      num_retries     = 1
      request_timeout = 45
      set_verbose = true
      json_logs = false
      cache = false
    }

    model_list = [
      {
        model_name = "anthropic.claude-opus-4-5-20251101-v1:0"
        litellm_params = {
          max_parallel_requests = 50
          model                 = "vertex_ai/claude-opus-4-5@20251101"
          rpm                   = 450
          tpm                   = 6000000
          vertex_location       = "us-east5"
          vertex_project = "coder-vertex-demos"
          vertex_credentials = "/tmp/gcloud/service_account.json"
        }
      },
      {
        model_name = "anthropic.claude-opus-4-5-20251101-v1:0"
        litellm_params = {
          max_parallel_requests = 50
          model                 = "vertex_ai/claude-opus-4-5@20251101"
          rpm                   = 450
          tpm                   = 6000000
          vertex_location       = "europe-west1"
          vertex_project = "coder-vertex-demos"
          vertex_credentials = "/tmp/gcloud/service_account.json"
        }
      },
      {
        model_name = "anthropic.claude-haiku-4-5-20251001-v1:0"
        litellm_params = {
          max_parallel_requests = 50
          model                 = "vertex_ai/claude-haiku-4-5@20251001"
          rpm                   = 3000
          tpm                   = 3000000
          vertex_location       = "us-east5"
          vertex_project = "coder-vertex-demos"
          vertex_credentials = "/tmp/gcloud/service_account.json"
        }
      },
      {
        model_name = "anthropic.claude-haiku-4-5-20251001-v1:0"
        litellm_params = {
          max_parallel_requests = 50
          model                 = "vertex_ai/claude-haiku-4-5@20251001"
          rpm                   = 3600
          tpm                   = 3600000
          vertex_location       = "europe-west1"
          vertex_project = "coder-vertex-demos"
          vertex_credentials = "/tmp/gcloud/service_account.json"
        }
      },
      {
        model_name = "claude-opus-4-5"
        litellm_params = {
          max_parallel_requests = 50
          model                 = "vertex_ai/claude-opus-4-5@20251101"
          rpm                   = 450
          tpm                   = 6000000
          vertex_location       = "us-east5"
          vertex_project = "coder-vertex-demos"
          vertex_credentials = "/tmp/gcloud/service_account.json"
        }
      },
      {
        model_name = "claude-opus-4-5"
        litellm_params = {
          max_parallel_requests = 50
          model                 = "vertex_ai/claude-opus-4-5@20251101"
          rpm                   = 450
          tpm                   = 6000000
          vertex_location       = "europe-west1"
          vertex_project = "coder-vertex-demos"
          vertex_credentials = "/tmp/gcloud/service_account.json"
        }
      },
      {
        model_name = "claude-sonnet-4-5"
        litellm_params = {
          max_parallel_requests = 50
          model                 = "vertex_ai/claude-sonnet-4-5@20250929"
          rpm                   = 3000
          tpm                   = 3000000
          vertex_location       = "us-east5"
          vertex_project = "coder-vertex-demos"
          vertex_credentials = "/tmp/gcloud/service_account.json"
        }
      },
      {
        model_name = "claude-sonnet-4-5"
        litellm_params = {
          max_parallel_requests = 50
          model                 = "vertex_ai/claude-sonnet-4-5@20250929"
          rpm                   = 3600
          tpm                   = 3600000
          vertex_location       = "europe-west1"
          vertex_project = "coder-vertex-demos"
          vertex_credentials = "/tmp/gcloud/service_account.json"
        }
      },
      {
        model_name = "claude-haiku-4-5"
        litellm_params = {
          max_parallel_requests = 50
          model                 = "vertex_ai/claude-haiku-4-5@20251001"
          rpm                   = 3000
          tpm                   = 3000000
          vertex_location       = "us-east5"
          vertex_project = "coder-vertex-demos"
          vertex_credentials = "/tmp/gcloud/service_account.json"
        }
      },
      {
        model_name = "claude-haiku-4-5"
        litellm_params = {
          max_parallel_requests = 50
          model                 = "vertex_ai/claude-haiku-4-5@20251001"
          rpm                   = 3600
          tpm                   = 3600000
          vertex_location       = "europe-west1"
          vertex_project = "coder-vertex-demos"
          vertex_credentials = "/tmp/gcloud/service_account.json"
        }
      }
    ]

    router_settings = {
      num_retries     = 2
      routing_strategy = "usage-based-routing-v2"
    }
  }

  mount_ssl = {
    enable = true
    secret_name = kubernetes_manifest.cert.manifest.metadata.name
    path = "/tmp/ssl"
  }

  mounts = [{
    secret_name = kubernetes_secret_v1.gcloud.metadata[0].name
    path = "/tmp/gcloud/"
  }]
}