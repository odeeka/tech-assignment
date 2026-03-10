include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "."
}

# Read outputs from Stage 1 and pass them as variables to this module
dependency "base" {
  config_path = "../01-base-infra"

  # Mock outputs allow `terragrunt validate/plan` to succeed before Stage 1 is applied.
  # The mock CA cert is a self-signed placeholder - providers will accept its format
  # but cannot connect (which is fine for plan-only runs).
  mock_outputs = {
    cluster_name                       = "mock-cluster"
    cluster_endpoint                   = "https://mock-endpoint.eks.amazonaws.com"
    cluster_certificate_authority_data = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUJlVENDQVIrZ0F3SUJBZ0lVUFhndGc1WDJZZlpFUytkV2FRTzVkdWs4c2F3d0NnWUlLb1pJemowRUF3SXcKRWpFUU1BNEdBMVVFQXd3SGJXOWpheTFqWVRBZUZ3MHlOakF6TVRBeE9ERTJOVEphRncwek5qQXpNRGN4T0RFMgpOVEphTUJJeEVEQU9CZ05WQkFNTUIyMXZZMnN0WTJFd1dUQVRCZ2NxaGtqT1BRSUJCZ2dxaGtqT1BRTUJCd05DCkFBVEtjU0VQL0oxc1h2RnUveDBkZ0haT09CY2F3N1lVUWdHVzVvMjl6WmcvVHp1WWhMS09TTHlQbGNscno1aGcKcG81SXM2V2dtMncwMGdtcGxxV3d5clJWbzFNd1VUQWRCZ05WSFE0RUZnUVUzTktDNzR4TFJtcHQremx6Y2RvbgpCRlo5Zm1Nd0h3WURWUjBqQkJnd0ZvQVUzTktDNzR4TFJtcHQremx6Y2RvbkJGWjlmbU13RHdZRFZSMFRBUUgvCkJBVXdBd0VCL3pBS0JnZ3Foa2pPUFFRREFnTklBREJGQWlFQXAzWG1rVzFBNW5uYWZ2V2N5Zlo0bHF2Mng1bWcKRUJTam5EWjAzNFZQTUV3Q0lCd1BoSi9aVGJmRFQ0Wk8veXVSVzhuYmNRN2I5bFJLUTlrR0s3eHpmamVFCi0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K"
    karpenter_queue_name               = "mock-queue"
    karpenter_node_iam_role_name       = "mock-role"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

inputs = {
  cluster_name                       = dependency.base.outputs.cluster_name
  cluster_endpoint                   = dependency.base.outputs.cluster_endpoint
  cluster_certificate_authority_data = dependency.base.outputs.cluster_certificate_authority_data
  karpenter_queue_name               = dependency.base.outputs.karpenter_queue_name
  karpenter_node_iam_role_name       = dependency.base.outputs.karpenter_node_iam_role_name
}
