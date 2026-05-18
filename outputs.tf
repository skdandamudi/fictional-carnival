output "vpc_id" {
  description = "VPC ID resolved from vpc_tags"
  value       = data.aws_vpc.this.id
}

output "subnet_ids" {
  description = "Subnet IDs resolved from subnet_tags"
  value       = data.aws_subnets.this.ids
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority" {
  description = "Base64-encoded cluster CA certificate"
  value       = module.eks.cluster_certificate_authority
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.eks.cluster_security_group_id
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for IRSA"
  value       = module.eks.cluster_oidc_issuer_url
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider for IRSA"
  value       = module.eks.oidc_provider_arn
}

output "node_group_name" {
  description = "Name of the managed node group (null when managed node group is disabled)"
  value       = module.eks.node_group_name
}

output "node_role_arn" {
  description = "IAM role ARN used by worker nodes"
  value       = module.eks.node_role_arn
}

output "additional_node_group_names" {
  description = "Map of additional node group key -> EKS node group name"
  value       = module.eks.additional_node_group_names
}

output "additional_node_group_arns" {
  description = "Map of additional node group key -> ARN"
  value       = module.eks.additional_node_group_arns
}

output "automode_enabled" {
  description = "Whether EKS Auto Mode is enabled"
  value       = module.eks.automode_enabled
}

output "managed_node_group_enabled" {
  description = "Whether a managed node group is created"
  value       = module.eks.managed_node_group_enabled
}

output "calico_enabled" {
  description = "Whether Calico is deployed"
  value       = module.eks.calico_enabled
}

output "calico_mode" {
  description = "Calico deployment mode (policy-only or cni)"
  value       = module.eks.calico_mode
}

output "vpc_cni_removed" {
  description = "Whether the VPC CNI was actively removed for Calico CNI mode"
  value       = module.eks.vpc_cni_removed
}

output "karpenter_enabled" {
  description = "Whether Karpenter infrastructure is provisioned"
  value       = module.eks.karpenter_enabled
}

output "karpenter_controller_role_arn" {
  description = "IAM role ARN for the Karpenter controller (IRSA)"
  value       = module.eks.karpenter_controller_role_arn
}

output "karpenter_instance_profile_name" {
  description = "Instance profile name for Karpenter-launched nodes"
  value       = module.eks.karpenter_instance_profile_name
}

output "karpenter_queue_name" {
  description = "SQS queue name for Karpenter interruption handling"
  value       = module.eks.karpenter_queue_name
}
