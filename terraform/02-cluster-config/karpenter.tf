################################################################################
# Karpenter Helm Release
################################################################################

resource "helm_release" "karpenter" {
  namespace        = "kube-system"
  name             = "karpenter"
  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter"
  version          = var.karpenter_version
  wait             = true
  create_namespace = false

  values = [
    <<-EOT
    settings:
      clusterName: ${var.cluster_name}
      clusterEndpoint: ${var.cluster_endpoint}
      interruptionQueue: ${var.karpenter_queue_name}
    nodeSelector:
      nodegroup-type: system
    EOT
  ]
}

################################################################################
# Karpenter EC2NodeClass
# Defines HOW nodes are launched (AMI, subnets, security groups, IAM role)
################################################################################

resource "kubectl_manifest" "karpenter_node_class" {
  yaml_body = <<-YAML
    apiVersion: karpenter.k8s.aws/v1
    kind: EC2NodeClass
    metadata:
      name: default
    spec:
      role: "${var.karpenter_node_iam_role_name}"
      amiSelectorTerms:
        - alias: bottlerocket@latest
      subnetSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${var.cluster_name}
      securityGroupSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${var.cluster_name}
      tags:
        karpenter.sh/discovery: ${var.cluster_name}
        managed-by: karpenter
  YAML

  depends_on = [helm_release.karpenter]
}

################################################################################
# Karpenter NodePool
# Defines WHAT nodes to launch (instance types, architectures, capacity types)
# Supports both x86 (amd64) and ARM64 (Graviton) with Spot and On-Demand
################################################################################

resource "kubectl_manifest" "karpenter_node_pool" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1
    kind: NodePool
    metadata:
      name: default
    spec:
      template:
        metadata:
          labels:
            managed-by: karpenter
        spec:
          requirements:
            - key: kubernetes.io/arch
              operator: In
              values: ["amd64", "arm64"]
            - key: karpenter.sh/capacity-type
              operator: In
              values: ["spot", "on-demand"]
            - key: karpenter.k8s.aws/instance-category
              operator: In
              values: ["c", "m", "r"]
            - key: karpenter.k8s.aws/instance-generation
              operator: Gt
              values: ["5"]
          nodeClassRef:
            group: karpenter.k8s.aws
            kind: EC2NodeClass
            name: default
      limits:
        cpu: "32"
        memory: 64Gi
      disruption:
        consolidationPolicy: WhenEmptyOrUnderutilized
        consolidateAfter: 30s
  YAML

  depends_on = [kubectl_manifest.karpenter_node_class]
}
