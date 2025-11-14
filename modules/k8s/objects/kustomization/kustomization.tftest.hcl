variables {
  name = "test"
  # Changed to string because namespace should be a single value not an array
  namespace = "test"
  patches   = []
  resources = []
  helm_charts = [{
    name         = "test"
    release_name = "test"
    version      = "2.23.0"
    repo         = "https://helm.test.com/v2"
    namespace    = "test"
    values_file  = "./values.yaml"
    values_inline = {
      test = "test"
    }
  }]
  config_map_generator = [{
    name      = "test"
    namespace = "test"
    behavior  = "create"
    envs      = []
    files     = []
    options = {
      disableNameSuffixHash = true
    }
  }]
  secret_generator = [{
    name      = "gcloud-auth"
    namespace = "litellm"
    behavior  = "create"
    files     = ["secrets/service_account.json"]
    options = {
      disableNameSuffixHash = true
    }
  }]
  expected = <<-EOF
    apiVersion: kustomize.config.k8s.io/v1beta1
    kind: Kustomization
    namespace: test
    helmCharts:
      - name: test
        releaseName: test
        version: 2.23.0
        repo: https://helm.test.com/v2
        namespace: test
        valuesFile: ./values.yaml
        valuesInline:
            test: test
        
    secretGenerator:
      - name: gcloud-auth
        namespace: litellm
        behavior: create
        options:
            disableNameSuffixHash: true
        files:
        - secrets/service_account.json

    configMapGenerator:
      - name: test
        namespace: test
        behavior: create
        envs: []
        files: []
        options:
            disableNameSuffixHash: true

    resources: []
    patches: []
    EOF
}

run "build" {}

run "verify" {
  command = plan

  assert {
    condition     = yamldecode(run.build.manifest) == yamldecode(var.expected)
    error_message = "Namespace manifest produced unequal output."
  }
}