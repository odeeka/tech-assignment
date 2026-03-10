# Root Terragrunt config - shared settings for all stages
# Run `terragrunt run --all -- apply` from terraform/ to deploy everything in order

locals {
  aws_region   = "us-east-1"
  cluster_name = "opsfleet-eks"
}
