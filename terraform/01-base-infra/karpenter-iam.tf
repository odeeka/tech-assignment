################################################################################
# Karpenter IAM & Infrastructure
#
# This creates the IAM roles and SQS queue needed by Karpenter.
# The actual Helm release and Kubernetes manifests are in 02-cluster-config.
################################################################################

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "21.15.1"

  cluster_name = module.eks.cluster_name

  # EKS Pod Identity association is created by default in v21
  create_pod_identity_association = true

  # Node IAM role used by instances launched by Karpenter
  node_iam_role_use_name_prefix = false
  node_iam_role_name            = "KarpenterNodeRole-${var.cluster_name}"

  tags = local.tags
}
