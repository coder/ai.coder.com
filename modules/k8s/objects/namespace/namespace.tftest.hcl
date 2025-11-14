variables {
  name = "test"
  # Fixed variable reference to use direct value instead of var.name for proper error handling
  expected = <<-EOF
    apiVersion: v1
    kind: Namespace
    metadata:
        name: test
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