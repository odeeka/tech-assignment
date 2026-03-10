variable "cluster_name" {
  description = "Name of the EKS cluster (must match 01-base-infra)"
  type        = string
  default     = "opsfleet-eks"
}

variable "aws_region" {
  description = "AWS region where the cluster is deployed"
  type        = string
  default     = "eu-central-1"
}

variable "cluster_endpoint" {
  description = "EKS cluster API server endpoint (from 01-base-infra output)"
  type        = string
}

variable "cluster_certificate_authority_data" {
  description = "Base64-encoded cluster CA certificate (from 01-base-infra output)"
  type        = string
  sensitive   = true
}

variable "karpenter_queue_name" {
  description = "SQS queue name for Karpenter interruption handling (from 01-base-infra output)"
  type        = string
}

variable "karpenter_node_iam_role_name" {
  description = "IAM role name for Karpenter-managed nodes (from 01-base-infra output)"
  type        = string
}

variable "karpenter_version" {
  description = "Karpenter Helm chart version"
  type        = string
  default     = "1.9.0"
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}
