# ── KMS key for EKS secrets encryption ───────────────────────────────────────
module "kms_eks" {
  source = "../../modules/kms-key"

  alias_name         = "alias/${local.cluster_name}-eks-secrets"
  description        = "Encryption key for EKS cluster secrets - ${local.cluster_name}"
  service_principals = ["eks.amazonaws.com"]
}

# ── EKS cluster ──────────────────────────────────────────────────────────────
module "eks" {
  source = "../../modules/eks-cluster"

  cluster_name       = local.cluster_name
  kubernetes_version = var.kubernetes_version
  vpc_id             = data.aws_vpc.this.id
  subnet_ids         = data.aws_subnets.this.ids

  # Encryption
  cluster_encryption_kms_key_arn = module.kms_eks.key_arn

  # Endpoint access
  endpoint_public_access = var.endpoint_public_access
  public_access_cidrs    = var.public_access_cidrs
  private_access_cidrs   = var.private_access_cidrs

  # Cluster access
  access_entries = var.access_entries

  # Compute mode
  automode_enabled           = var.automode_enabled
  automode_node_pools        = var.automode_node_pools
  managed_node_group_enabled = var.managed_node_group_enabled
  karpenter_enabled          = var.karpenter_enabled

  # Node group
  node_instance_types = var.node_instance_types
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
  node_disk_size      = var.node_disk_size
  node_ami_type       = var.node_ami_type

  # Additional node groups (for_each map; default group above stays intact)
  additional_node_groups = var.additional_node_groups

  # CloudWatch logging
  cluster_log_types          = var.cluster_log_types
  cluster_log_retention_days = var.cluster_log_retention_days

  # Enhanced networking (managed mode only)
  vpc_cni_prefix_delegation = var.vpc_cni_prefix_delegation

  # Calico CNI
  calico_enabled            = var.calico_enabled
  calico_mode               = var.calico_mode
  calico_version            = var.calico_version
  calico_pod_cidr           = var.calico_pod_cidr
  calico_encapsulation      = var.calico_encapsulation
  calico_chart_repository   = var.calico_chart_repository
  calico_image_registry     = var.calico_image_registry
  calico_image_pull_secrets = var.calico_image_pull_secrets
  calico_max_pods_per_node  = var.calico_max_pods_per_node

  tags = {
    Cluster = local.cluster_name
  }
}
