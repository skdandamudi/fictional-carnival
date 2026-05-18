output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority" {
  description = "Base64-encoded cluster CA certificate"
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = aws_security_group.cluster.id
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for IRSA"
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider for IRSA"
  value       = aws_iam_openid_connect_provider.cluster.arn
}

output "node_group_name" {
  description = "Name of the managed node group (null when managed node group is disabled)"
  value       = var.managed_node_group_enabled ? aws_eks_node_group.this[0].node_group_name : null
}

output "node_role_arn" {
  description = "IAM role ARN used by worker nodes"
  value       = aws_iam_role.node.arn
}

output "additional_node_group_names" {
  description = "Map of additional node group key -> EKS node group name"
  value       = { for k, ng in aws_eks_node_group.additional : k => ng.node_group_name }
}

output "additional_node_group_arns" {
  description = "Map of additional node group key -> ARN"
  value       = { for k, ng in aws_eks_node_group.additional : k => ng.arn }
}

output "automode_enabled" {
  description = "Whether EKS Auto Mode is enabled"
  value       = var.automode_enabled
}

output "managed_node_group_enabled" {
  description = "Whether a managed node group is created"
  value       = var.managed_node_group_enabled
}

# ── Calico ───────────────────────────────────────────────────────────────────

output "calico_enabled" {
  description = "Whether Calico is deployed"
  value       = var.calico_enabled
}

output "calico_mode" {
  description = "Calico deployment mode (policy-only or cni)"
  value       = var.calico_enabled ? var.calico_mode : null
}

output "vpc_cni_removed" {
  description = "Whether the VPC CNI (aws-node DaemonSet) was actively removed for Calico CNI mode"
  value       = var.calico_enabled && var.calico_mode == "cni"
}

# ── EBS CSI Driver ────────────────────────────────────────────────────────────

output "ebs_csi_driver_enabled" {
  description = "Whether the EBS CSI driver addon is installed"
  value       = var.ebs_csi_driver_enabled
}

output "ebs_csi_driver_role_arn" {
  description = "IAM role ARN for the EBS CSI driver (IRSA)"
  value       = var.ebs_csi_driver_enabled ? aws_iam_role.ebs_csi_driver[0].arn : null
}

# ── Karpenter ────────────────────────────────────────────────────────────────

output "karpenter_enabled" {
  description = "Whether Karpenter infrastructure is provisioned"
  value       = var.karpenter_enabled
}

output "karpenter_controller_role_arn" {
  description = "IAM role ARN for the Karpenter controller (IRSA)"
  value       = var.karpenter_enabled ? aws_iam_role.karpenter_controller[0].arn : null
}

output "karpenter_instance_profile_name" {
  description = "Instance profile name for Karpenter-launched nodes"
  value       = var.karpenter_enabled ? aws_iam_instance_profile.karpenter[0].name : null
}

output "karpenter_queue_name" {
  description = "SQS queue name for Karpenter interruption handling"
  value       = var.karpenter_enabled ? aws_sqs_queue.karpenter[0].name : null
}
