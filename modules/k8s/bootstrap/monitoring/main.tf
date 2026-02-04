terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.17.0"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}

variable "chart_version" {
    type = string
    default = "0.6.2"
}

variable "chart_timeout" {
    type = number
    default = 300
}

variable "cluster_name" {
  type = string
}

variable "cluster_oidc_provider_arn" {
  type = string
}

variable "coder" {
    type = object({
        db = object({
            host = string
            port = optional(number, 5432)
            password = string
            username = string
            database = string
            sslmode = optional(string, "require")
        })
        selector = object({
            coderd = string
            provisionerd = string
            workspaces = string
            ctrl_plane_ns = string
            ext_prov_ns = string
        })
    })
    sensitive = true
}

variable "grafana" {
    type = object({
        admin = object({
            username = string
            password = string
        })
        db = object({
            host = string
            port = optional(number, 5432)
            password = string
            username = string
            database = string
            sslmode = optional(string, "require")
        })
        svc = object({
            annots = map(string)
        })
    })
    sensitive = true
}

variable "loki" {
    type = object({
        s3 = object({
            chunks_bucket = string
            ruler_bucket = string
            region = string
        })
    })
}

variable "domain_name" {
    type = string
}

variable "cert_config" {
  type = object({
    create_secret = bool
    name          = string
    kind          = optional(string, "ClusterIssuer")
    issuer        = optional(string, "issuer")
    store    = optional(string, "issuer")
  })
  default = {
    create_secret = true
    name          = "grafana-tls"
    kind       = "ClusterIssuer"
    issuer        = "issuer"
    store        = "issuer"
  }
}

variable "tolerations" {
  type = list(map(any))
  default = []
}

locals {
  normalized_domain_name = split(".", var.domain_name)[0]
  apex_domain = join(".", slice(split(".", var.domain_name), length(split(".", var.domain_name))-2, length(split(".", var.domain_name))))
  ssl_vol_friendly_name = replace(var.cert_config.name, ".", "-")
  daemonset_tolerations = [{
    effect = "NoSchedule"
    operator = "Exists"
  }]
  system_tolerations = [{
    key      = "CriticalAddonsOnly"
    operator = "Exists"
  }]
}

data "aws_s3_bucket" "loki" {
  bucket = "${var.cluster_name}-grafana"
}

data "aws_region" "this" {}

data "aws_caller_identity" "this" {}

locals {
  region      = data.aws_region.this.region
  account_id  = data.aws_caller_identity.this.account_id
  policy_name = "loki-s3-access"
  role_name   = "loki-s3-access"
}

module "oidc-role" {
  source       = "../../../security/role/access-entry"
  name         = local.role_name
  path         = "/${var.cluster_name}/${data.aws_region.this.region}/"
  cluster_name = var.cluster_name
  policy_arns = {
    "AmazonEKSLoadBalancingPolicy" = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess",
  }
  cluster_policy_arns = {
    "AmazonEKSClusterAdminPolicy" = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy",
  }
  oidc_principals = {
    "${var.cluster_oidc_provider_arn}" = ["system:serviceaccount:*:*"]
  }
  tags = {}
}

resource "kubernetes_namespace_v1" "this" {
    metadata {
        name = "coder-observe"
    }
}

locals {
  common_name   = "grafana.${trimprefix(trimprefix(var.domain_name, "https://"), "http://")}"
  wildcard_name = "*.${local.common_name}"
  cert_refresh_interval = "2160h" # 90 days
  cert_renew_before = "360h" # 15 days
  secret_refresh_interval = "1812h0m0s" # 75.5 days
  tls_secret_key = "tls.key"
  tls_secret_crt = "tls.crt"
  tls_remote_key = "tls-${local.common_name}.key"
  tls_remote_crt = "tls-${local.common_name}.crt"
}

resource "kubernetes_manifest" "pull" {

  field_manager {
    force_conflicts = true
  }

  wait {
    fields = {
      "status.conditions[0].type" = "Ready"
    }
  }
  
  timeouts {
    create = "1m"
    update = "1m"
    delete = "30s"
  }

  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind = "ExternalSecret"
    metadata = {
      name = var.cert_config.name 
      namespace = kubernetes_namespace_v1.this.metadata[0].name
    }
    spec = {
      secretStoreRef = {
        kind = "ClusterSecretStore"
        name = var.cert_config.store
      }
      refreshPolicy = "Periodic"
      refreshInterval = local.secret_refresh_interval
      target = {
        name = local.ssl_vol_friendly_name
        creationPolicy = "Orphan"
        deletionPolicy = "Retain"
        template = {
          type = "kubernetes.io/tls"
          metadata = {
            labels = {
              "controller.cert-manager.io/fao" = "true"
            }
            annotations = {
              "cert-manager.io/alt-names" = "${local.wildcard_name},${local.common_name}"                                                                                                                                
              "cert-manager.io/certificate-name" = var.cert_config.name                                                                                     
              "cert-manager.io/common-name" = local.common_name 
              "cert-manager.io/ip-sans" = ""
              "cert-manager.io/issuer-group" = ""                                                                                                                   
              "cert-manager.io/issuer-kind" = "ClusterIssuer"                                                                                               
              "cert-manager.io/issuer-name" = var.cert_config.issuer
              "cert-manager.io/uri-sans" = ""
            }
          }
        }
      }
      data = [{
        secretKey = local.tls_secret_crt
        remoteRef = {
          key = local.tls_remote_crt
        }
      },{
        secretKey = local.tls_secret_key
        remoteRef = {
          key = local.tls_remote_key
        }
      }]
    }
  }
}

resource "time_sleep" "wait" {
  # Let the secret create first if it exists in AWS Secrets Manager.
  depends_on = [ kubernetes_manifest.pull ]
  create_duration = "30s"
}

## 
# Requires the cert-manager
## 

resource "kubernetes_manifest" "certificate" {

  depends_on = [ time_sleep.wait ]

  field_manager {
    force_conflicts = true
  }

  wait {
    condition {
      type   = "Ready"
      status = "True"
    }
  }

  timeouts {
    create = "10m"
    update = "10m"
    delete = "30s"
  }

  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind = "Certificate"
    metadata = {
      name = var.cert_config.name
      namespace = kubernetes_namespace_v1.this.metadata[0].name
    }
    spec = {
      commonName = local.common_name
      dnsNames = [
        local.common_name,
        local.wildcard_name
      ]
      duration = local.cert_refresh_interval
      renewBefore = local.cert_renew_before
      issuerRef = {
        kind = var.cert_config.kind
        name = var.cert_config.issuer
      }
      secretName = local.ssl_vol_friendly_name
      privateKey = {
        rotationPolicy = "Never"
        algorithm = "RSA"
        encoding = "PKCS1"
        size = "2048"
      }
    }
  }
}

resource "kubernetes_manifest" "push" {

  depends_on = [ kubernetes_manifest.certificate ]

  field_manager {
    force_conflicts = true
  }

  wait {
    condition {
      type   = "Ready"
      status = "True"
    }
  }

  timeouts {
    create = "10m"
    update = "10m"
    delete = "30s"
  }

  manifest = {
    apiVersion = "external-secrets.io/v1alpha1"
    kind = "PushSecret"
    metadata = {
      name = var.cert_config.name 
      namespace = kubernetes_namespace_v1.this.metadata[0].name
    }
    spec = {
      updatePolicy = "Replace"
      deletionPolicy = "None"
      refreshInterval = local.secret_refresh_interval
      secretStoreRefs = [{
        kind = "ClusterSecretStore"
        name = var.cert_config.store
      }]
      selector = {
        secret = {
          name = kubernetes_manifest.certificate.manifest.spec.secretName
        } 
      }
      data = [{
        match = {
          secretKey = local.tls_secret_crt
          remoteRef = {
            remoteKey = local.tls_remote_crt
          }
        }
      },{
        match = {
          secretKey = local.tls_secret_key
          remoteRef = {
            remoteKey = local.tls_remote_key
          }
        }
      }]
    }
  }
}

resource "helm_release" "coder-observe" {
  name             = "coder-observe"
  namespace        = kubernetes_namespace_v1.this.metadata[0].name
  chart            = "coder-observability"
  repository       = "https://helm.coder.com/observability"
  create_namespace = false
  upgrade_install  = true
  skip_crds        = false
  wait             = true
  wait_for_jobs    = true
  version          = var.chart_version
  timeout          = var.chart_timeout

  values = [yamlencode({
    global = {
        coder = {
            coderdSelector = var.coder.selector.coderd
            provisionerdSelector = var.coder.selector.provisionerd
            workspacesSelector = var.coder.selector.workspaces
            controlPlaneNamespace = var.coder.selector.ctrl_plane_ns
            externalProvisionersNamespace = var.coder.selector.ext_prov_ns
        }
        postgres = {
            hostname = var.coder.db.host
            port = var.coder.db.port
            password = var.coder.db.password
            username = var.coder.db.username
            database = var.coder.db.database
            sslmode = var.coder.db.sslmode
            mountSecret = ""
        }
    }
    prometheus = {
      server = {
        tolerations = local.system_tolerations
      }
      alertmanager = {
        tolerations = local.system_tolerations
      }
    }
    grafana = {
      adminUser = var.grafana.admin.username
      adminPassword = var.grafana.admin.password
      env = {
        GF_SECURITY_DISABLE_INITIAL_ADMIN_CREATION = false
      }
      "grafana.ini" = {
        app_mode = "production"
        "auth.anonymous" = {
          enabled = false
        }
        instance_name = "Coder Environment"
        database = {
            url = "postgres://${var.grafana.db.username}:${var.grafana.db.password}@${var.grafana.db.host}:${var.grafana.db.port}/${var.grafana.db.database}"
            ssl_mode = var.grafana.db.sslmode
        }
        server = {
            root_url = "https://${local.common_name}"
            domain = local.common_name
            enforce_domain = true
            http_port = 3000
            protocol = "https"
            cert_file = "/mnt/grafana-tls/tls.crt"
            cert_key =  "/mnt/grafana-tls/tls.key" 
        }
        users = {
            allow_sign_up = false
        }
      }
      replicas = 2
      useStatefulSet = true
      readinessProbe = {
        httpGet = {
          scheme = "HTTPS"
        }
      }
      livenessProbe = {
        httpGet = {
          scheme = "HTTPS"
        }
      }
      persistence = {
        enabled = false
      }
      podAnnotations = {
        "prometheus.io/port" = "3000"
        "prometheus.io/scheme" = "http"
        "prometheus.io/scrape" = "true"
      }
      service = {
        annotations = var.grafana.svc.annots
        enabled = true
        externalTrafficPolicy = "Cluster"
        internalTrafficPolicy = "Cluster"
        loadBalancerClass = "service.k8s.aws/nlb"
        port = 443
        targetPort = 3000
        type = "LoadBalancer"
      }
      extraSecretMounts = [{
        name = kubernetes_manifest.certificate.manifest.spec.secretName
        mountPath = "/mnt/grafana-tls"
        secretName = kubernetes_manifest.certificate.manifest.spec.secretName
        readOnly = true
        optional = false
        subPath = ""
      }]
    }
    grafana-agent = {
        enabled = true
        controller = {
          tolerations = local.daemonset_tolerations
        }
        discovery = <<-EOF
            // Discover k8s nodes
            discovery.kubernetes "nodes" {
                role = "node"
            }

            // Discover k8s pods
            discovery.kubernetes "pods" {
                role = "pod"
                selectors {
                    role  = "pod"
                }
            }
        EOF
        commonRelabellings = <<-EOF
            rule {
                source_labels = ["__meta_kubernetes_namespace"]
                target_label  = "namespace"
            }
            rule {
                source_labels = ["__meta_kubernetes_pod_name"]
                target_label  = "pod"
            }
            // coalesce the following labels and pick the first value; we'll use this to define the "job" label
            rule {
                source_labels  = ["__meta_kubernetes_pod_label_app_kubernetes_io_component", "app", "__meta_kubernetes_pod_container_name"]
                separator      = "/"
                target_label   = "__meta_app"
                action         = "replace"
                regex          = "^/*([^/]+?)(?:/.*)?$" // split by the delimiter if it exists, we only want the first one
                replacement    = "$${1}"
            }
            rule {
                source_labels = ["__meta_kubernetes_namespace", "__meta_kubernetes_pod_label_app_kubernetes_io_name", "__meta_app"]
                separator     = "/"
                target_label  = "job"
            }
            rule {
                source_labels = ["__meta_kubernetes_pod_container_name"]
                target_label  = "container"
            }
            rule {
                regex   = "__meta_kubernetes_pod_label_(statefulset_kubernetes_io_pod_name|controller_revision_hash)"
                action  = "labeldrop"
            }
            rule {
                regex   = "pod_template_generation"
                action  = "labeldrop"
            }
            rule {
                source_labels = ["__meta_kubernetes_pod_phase"]
                regex = "Pending|Succeeded|Failed|Completed"
                action = "drop"
            }
            rule {
                source_labels = ["__meta_kubernetes_pod_node_name"]
                action = "replace"
                target_label = "node"
            }
            rule {
                action = "labelmap"
                regex = "__meta_kubernetes_pod_annotation_prometheus_io_param_(.+)"
                replacement = "__param_$1"
            }
        EOF
        controller = {
            type = "daemonset"
            podAnnotations = {
                "prometheus.io/scheme" = "http"
                "prometheus.io/scrape" = "true"
            }
        }
    }
    loki = {
      loki = {
        storage = {
          bucketNames = {
            chunks = var.loki.s3.chunks_bucket
            ruler = var.loki.s3.ruler_bucket
          }
          s3 = {
            region = var.loki.s3.region
          }
          type = "s3"
        }
      }
      lokiCanary = {
        tolerations = local.daemonset_tolerations
      }
      backend = {
        tolerations = local.system_tolerations
      }
      resultsCache = {
        tolerations = local.system_tolerations
      }
      chunksCache = {
        tolerations = local.system_tolerations
      }
      storage = {
        tolerations = local.system_tolerations
      }
      write = {
        tolerations = local.system_tolerations
      }
      serviceAccount = {
        create = true
        annotations = {
          "eks.amazonaws.com/role-arn" = module.oidc-role.role_arn
        }
      }
    }
  })]
}

output "namespace" {
  value = kubernetes_namespace_v1.this.metadata[0].name
}