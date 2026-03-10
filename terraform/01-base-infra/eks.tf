################################################################################
# EKS Cluster
################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.15.1"

  name               = var.cluster_name
  kubernetes_version  = var.cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Allow public access to the API server for management
  # In production, restrict this to specific CIDRs or use private access only
  endpoint_public_access = true

  # Grant the Terraform caller admin permissions on the cluster
  enable_cluster_creator_admin_permissions = true

  # EKS managed addons
  addons = {
    coredns                = {
      most_recent    = true
    }
    kube-proxy             = { 
      most_recent    = true
    }
    vpc-cni                = { 
      most_recent    = true
      before_compute = true
    }
    eks-pod-identity-agent = { 
      most_recent    = true
      before_compute = true
    }
  }

  # System node group -> hosts Karpenter controller and critical system components
  # Uses Graviton (ARM64) instances for cost/performance efficiency
  eks_managed_node_groups = {
    system = {
      #ami_type       = "BOTTLEROCKET_ARM_64"
      #instance_types = ["t4g.medium"]
      ami_type = "AL2023_x86_64_STANDARD"
      instance_types = ["t3.small"]

      min_size     = 2
      max_size     = 3
      desired_size = 2

      labels = {
        "nodegroup-type" = "system"
      }
    }
  }

  # Tag node security group for Karpenter discovery
  node_security_group_tags = {
    "karpenter.sh/discovery" = var.cluster_name
  }

  tags = local.tags
}
