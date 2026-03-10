output "karpenter_chart_version" {
  description = "Deployed Karpenter Helm chart version"
  value       = helm_release.karpenter.version
}
