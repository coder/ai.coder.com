##
# Coder Helm Chart Installation w/ auxillary dependcies on:
# - cert-manager
# - karpenter
# - external-dns
# - external-secrets
##

variable "coder_username" {
  description = "Coder DB's username."
  type        = string
  default     = "coder"
}

variable "coder_password" {
  description = "Coder DB's password."
  type        = string
  default     = "th1s1sn0tas3cur3pass0wrd"
  sensitive = true
}

variable "coder_license" {
  type      = string
  default   = ""
  sensitive = true
}

variable "coder_admin_email" {
  type    = string
  default = "admin@coder.com"
}

variable "coder_admin_username" {
  type    = string
  default = "admin"
}

variable "coder_admin_password" {
  type      = string
  default   = "Th1s1sN0TS3CuR3!!"
  sensitive = true
}

variable "grafana_username" {
  description = "Grafana DB's username."
  type        = string
  default     = "grafana"
}

variable "grafana_password" {
  description = "Grafana DB's password."
  type        = string
  default     = "th1s1sn0tas3cur3pass0wrd"
  sensitive = true
}

variable "grafana_admin_username" {
  type    = string
  default = "admin"
}

variable "grafana_admin_password" {
  type      = string
  default   = "Th1s1sN0TS3CuR3!!"
  sensitive = true
}

variable "use_ext_dns" {
  description = "Toggle the K8s 'external-dns' addon. Disable in-case you want to manage DNS records yourself."
  type = bool
  default = true
}

variable "azs" {
  type    = list(string)
  default = ["a", "b", "c"]
}

resource "aws_iam_user" "bedrock" {

  count = var.coder_license != "" ? 1 : 0

  name = "bedrock-access"
  path = "/${local.normalized_domain_name}/${data.aws_region.this.region}/"
}

resource "aws_iam_access_key" "bedrock" {

  count = var.coder_license != "" ? 1 : 0

  user = aws_iam_user.bedrock[0].name
}

resource "aws_iam_user_policy_attachment" "bedrock" {

  count = var.coder_license != "" ? 1 : 0

  user = aws_iam_user.bedrock[0].name
  # https://docs.aws.amazon.com/aws-managed-policy/latest/reference/AmazonBedrockLimitedAccess.html
  policy_arn = "arn:aws:iam::aws:policy/AmazonBedrockLimitedAccess"
}

resource "aws_eip" "coder" {
  count = length(var.azs)
  domain   = "vpc"
  public_ipv4_pool = "amazon"
  tags = {
    Name = "${var.name}-${local.normalized_domain_name}-coder-${count.index}"
  }
}

locals {
  pub_subs = [ for az in var.azs : "${var.name}-${local.normalized_domain_name}-public-${data.aws_region.this.region}${az}"]
}

module "coder-server" {

  depends_on = [kubernetes_manifest.nodepool]

  source = "../../../modules/k8s/bootstrap/coder-server"

  cluster_name              = "${var.name}-${local.normalized_domain_name}"
  cluster_oidc_provider_arn = data.aws_iam_openid_connect_provider.coder.arn

  namespace = "coder"

  helm_version        = "2.29.4"

  coder = {
    access_url  = "https://${var.domain_name}"
    wildcard_url = "*.${var.domain_name}"
    pub_ips = aws_eip.coder.*.public_ip
    image_repo          = "ghcr.io/coder/coder"
    image_tag           = "v2.29.4"
    rep_cnt = 1
    # Use this instead of external provisioners. DNS might not propagate fast enough for Coder to be "reachable".
    prov_rep_cnt = 4
    # csp_policy = "frame-src https://${var.domain_name}"
  }

  db = {
    url = data.aws_db_instance.coder.endpoint
    username = var.coder_username
    password = var.coder_password
  }

  aibridge = var.coder_license == "" ? null : {
    enabled = true
    bedrock = {
      region = data.aws_region.this.region
      model = "global.anthropic.claude-opus-4-5-20251101-v1:0"
      access_id = aws_iam_access_key.bedrock[0].id
      secret_id = aws_iam_access_key.bedrock[0].secret
    }
  }

  resource_request = {
    cpu    = "1000m"
    memory = "2Gi"
  }
  resource_limit = {
    cpu    = "1000m"
    memory = "2Gi"
  }

  cert_config = {
    name          = var.domain_name
    kind = kubernetes_manifest.issuer.manifest.kind
    issuer      = kubernetes_manifest.issuer.manifest.metadata.name
    store  = kubernetes_manifest.secret-store.manifest.metadata.name
    create_secret = true
  }

  tags = {}

  svc_annot = merge({
    "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "instance"
    "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internet-facing"
    "service.beta.kubernetes.io/aws-load-balancer-attributes"      = "deletion_protection.enabled=false"
    "service.beta.kubernetes.io/aws-load-balancer-eip-allocations" = join(",", aws_eip.coder.*.allocation_id)
    "service.beta.kubernetes.io/aws-load-balancer-subnets" = join(",", local.pub_subs)
  }, !var.use_ext_dns ? null : {
    "external-dns.alpha.kubernetes.io/hostname"                    = "${var.domain_name},*.${var.domain_name}"
    "external-dns.alpha.kubernetes.io/ttl"                         = 60
  })

  node_selector = kubernetes_manifest.nodepool["coder"].manifest.spec.template.metadata.labels
  tolerations = [for toleration in kubernetes_manifest.nodepool["coder"].manifest.spec.template.spec.taints : {
    key      = toleration.key
    operator = "Equal"
    value    = toleration.value
    effect   = toleration.effect
  }]

  topology_spread = [{
    max_skew           = 1
    topology_key       = "kubernetes.io/hostname"
    when_unsatisfiable = "ScheduleAnyway"
    label_selector = {
      match_labels = {
        "app.kubernetes.io/name"    = "coder"
        "app.kubernetes.io/part-of" = "coder"
      }
    }
    match_label_keys = [
      "app.kubernetes.io/instance"
    ]
  }]
  pod_aaf_pref_sched_ie = [{
    weight = 100
    pod_affinity_term = {
      label_selector = {
        match_labels = {
          "app.kubernetes.io/instance" = "coder-v2"
          "app.kubernetes.io/name"     = "coder"
          "app.kubernetes.io/part-of"  = "coder"
        }
      }
      topology_key = "kubernetes.io/hostname"
    }
  }]
}

# Wait for DNS propagation. May require multiple redeploys
# resource "time_sleep" "wait_for_dns" {
#   depends_on      = [ module.coder-server ]
#   create_duration = "120s"
# }

data "http" "first-user" {

  # depends_on = [ time_sleep.wait_for_dns ]
  depends_on      = [ module.coder-server ]

  url = "https://${aws_eip.coder[0].public_ip}/api/v2/users/first"
  method = "POST"
  insecure = true
  request_headers = {
    Host = var.domain_name
    Accept = "application/json"
  }
  request_body = jsonencode({
    email    = var.coder_admin_email
    username = var.coder_admin_username
    password = var.coder_admin_password
    trial = false
  })
  retry {
    attempts = 60+1
    max_delay_ms = 5000
    min_delay_ms = 5000
  }
}

data "http" "login" {

  depends_on = [data.http.first-user]

  url = "https://${aws_eip.coder[0].public_ip}/api/v2/users/login"
  insecure = true
  method = "POST"
  request_headers = {
    Host = var.domain_name
    Accept = "application/json"
  }
  request_body = jsonencode({
    email    = var.coder_admin_email
    password = var.coder_admin_password
  })
}

##
# Adding a license crashes Coder temporarily. 
# Use 'external' to allow custom handling, and then wait before proceeding.
##

data "external" "add-license" {

  count = var.coder_license != "" ? 1 : 0

  program = ["bash", "${path.module}/scripts/add-license.sh"]

  query = {
    ip_addr = aws_eip.coder[0].public_ip
    domain = var.domain_name
    license_key = var.coder_license
    session_token = jsondecode(data.http.login.response_body).session_token
  }
}

resource "time_sleep" "wait_for_coder" {

  count = var.coder_license != "" ? 1 : 0

  depends_on      = [ data.external.add-license[0] ]
  create_duration = "30s"
}

resource "aws_eip" "grafana" {
  count = length(var.azs)
  domain   = "vpc"
  public_ipv4_pool = "amazon"
  tags = {
    Name = "${var.name}-${local.normalized_domain_name}-grafana-${count.index}"
  }
}

module "monitoring" {
  source = "../../../modules/k8s/bootstrap/monitoring"

  chart_version = "0.7.0-rc.1"
  cluster_name              = "${var.name}-${local.normalized_domain_name}"
  cluster_oidc_provider_arn = data.aws_iam_openid_connect_provider.coder.arn

  domain_name = var.domain_name
  tolerations = concat([{
    key      = "CriticalAddonsOnly"
    operator = "Exists"
  }], [for toleration in kubernetes_manifest.nodepool["coder"].manifest.spec.template.spec.taints : {
    key      = toleration.key
    operator = "Equal"
    value    = toleration.value
    effect   = toleration.effect
  }])

  coder = {
    db = {
      host = data.aws_db_instance.coder.address
      password = var.coder_password
      username = var.coder_username
      database = data.aws_db_instance.coder.db_name
    }
    selector = {
      coderd = "pod=~`coder.*`, pod!~`.*provisioner.*`, namespace=~`(coder)`"
      provisionerd = "pod=~`coder-provisioner.*`, namespace=~`(coder)`"
      workspaces = "pod!~`coder.*`, namespace=~`(coder)`"
      ctrl_plane_ns = "coder"
      ext_prov_ns = "coder"
    }
  }
  grafana = {
    admin = {
      username = var.grafana_admin_username
      password = var.grafana_admin_password
    }
    db = {
      host = data.aws_db_instance.grafana.address
      password = var.grafana_password
      username = var.grafana_username
      database = data.aws_db_instance.grafana.db_name
    }
    svc = {
      annots = merge({
        "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "instance"
        "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internet-facing"
        "service.beta.kubernetes.io/aws-load-balancer-attributes"      = "deletion_protection.enabled=false"
        "service.beta.kubernetes.io/aws-load-balancer-healthcheck-protocol" = "https"
        "service.beta.kubernetes.io/aws-load-balancer-healthcheck-path" = "/api/health"
        "service.beta.kubernetes.io/aws-load-balancer-eip-allocations" = join(",", aws_eip.grafana.*.allocation_id)
        "service.beta.kubernetes.io/aws-load-balancer-subnets" = join(",", local.pub_subs)
      }, !var.use_ext_dns ? null : {
        "external-dns.alpha.kubernetes.io/hostname"                    = "grafana.${var.domain_name},*.grafana.${var.domain_name}"
        "external-dns.alpha.kubernetes.io/ttl"                         = 60
      })
    }
  }
  loki = {
    s3 = {
      chunks_bucket = data.aws_s3_bucket.loki.id
      ruler_bucket = data.aws_s3_bucket.loki.id
      region = data.aws_s3_bucket.loki.bucket_region
    }
  }
}

##
# Coder Binary Prefetch
##

locals {
  coder_path = "/opt/coder/bin"
  bin_fetch_script = <<-EOF
    if [ ! -f ${local.coder_path}/coder ]; then
      curl -L https://${var.domain_name}/bin/coder-linux-amd64 -o ${local.coder_path}/coder
      chmod +x ${local.coder_path}/coder
    fi
  EOF
}

resource "kubernetes_daemon_set_v1" "bin-fetch" {
  metadata {
    name = "coder-bin-fetch"
    namespace = module.coder-server.namespace
    labels = {
      "app.kubernetes.io/name"    = "bin-fetch"
      "app.kubernetes.io/part-of" = "coder-workspaces"
    }
  }

  spec {

    selector {
      match_labels = {
        "app.kubernetes.io/name" = "bin-fetch"
      }
    }

    template {

      metadata {
        labels = {
          "app.kubernetes.io/name" = "bin-fetch"
        }
      }
      
      spec {

        host_aliases {
          hostnames = [var.domain_name]
          ip = aws_eip.coder[0].private_ip
        }
        
        security_context {
          run_as_user = "0"
        }

        init_container {
          name = "fetch-binary"
          image = "curlimages/curl:latest"
          command = ["sh", "-c", "${local.bin_fetch_script}"]
          
          volume_mount {
            name = "coder-bin"
            mount_path = local.coder_path
            read_only = false
          }

        }

        container {
          name  = "pause"
          image = "registry.k8s.io/pause:3.9"

          resources {
            requests = {
              cpu    = "1m"
              memory = "1Mi"
            }
            limits = {
              cpu    = "10m"
              memory = "10Mi"
            }
          }
        }

        volume {
          name = "coder-bin"
          host_path {
            path = local.coder_path
            type = "DirectoryOrCreate"
          }
        }
      }
    }
  }
}