data "aws_partition" "current" {}
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  partition  = data.aws_partition.current.partition
  policy_arn = "arn:${local.partition}:iam::aws:policy"

  # Self-managed addons are only needed when Auto Mode is OFF.
  # When Auto Mode is ON (even in hybrid), it handles vpc-cni, coredns,
  # kube-proxy, and pod-identity-agent automatically.
  self_managed_addons = !var.automode_enabled && var.managed_node_group_enabled
  use_vpc_cni         = local.self_managed_addons && !(var.calico_enabled && var.calico_mode == "cni")

  # In hybrid mode the managed node group needs the full node policies.
  # Karpenter also needs the full policies for nodes it launches.
  # Minimal automode-only policies are used only in pure Auto Mode.
  managed_node_policies  = var.managed_node_group_enabled || var.karpenter_enabled
  automode_node_policies = var.automode_enabled && !var.managed_node_group_enabled && !var.karpenter_enabled
}

# ─────────────────────────────────────────────────────────────────────────────
# Cluster IAM role
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
  })

  tags = var.tags
}

# Policies — always attached
resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSClusterPolicy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "${local.policy_arn}/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSVPCResourceController" {
  role       = aws_iam_role.cluster.name
  policy_arn = "${local.policy_arn}/AmazonEKSVPCResourceController"
}

# Policies — Auto Mode (including hybrid)
resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSComputePolicy" {
  count      = var.automode_enabled ? 1 : 0
  role       = aws_iam_role.cluster.name
  policy_arn = "${local.policy_arn}/AmazonEKSComputePolicy"
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSBlockStoragePolicy" {
  count      = var.automode_enabled ? 1 : 0
  role       = aws_iam_role.cluster.name
  policy_arn = "${local.policy_arn}/AmazonEKSBlockStoragePolicy"
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSLoadBalancingPolicy" {
  count      = var.automode_enabled ? 1 : 0
  role       = aws_iam_role.cluster.name
  policy_arn = "${local.policy_arn}/AmazonEKSLoadBalancingPolicy"
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSNetworkingPolicy" {
  count      = var.automode_enabled ? 1 : 0
  role       = aws_iam_role.cluster.name
  policy_arn = "${local.policy_arn}/AmazonEKSNetworkingPolicy"
}

# ─────────────────────────────────────────────────────────────────────────────
# Node IAM role
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_iam_role" "node" {
  name = "${var.cluster_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = var.tags
}

# Policies — always attached
resource "aws_iam_role_policy_attachment" "node_AmazonSSMManagedInstanceCore" {
  role       = aws_iam_role.node.name
  policy_arn = "${local.policy_arn}/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "node_CloudWatchAgentServerPolicy" {
  role       = aws_iam_role.node.name
  policy_arn = "${local.policy_arn}/CloudWatchAgentServerPolicy"
}

# Policies — managed node group (managed-only OR hybrid)
# These are the full policies required by self-managed EC2 nodes.
resource "aws_iam_role_policy_attachment" "node_AmazonEKSWorkerNodePolicy" {
  count      = local.managed_node_policies ? 1 : 0
  role       = aws_iam_role.node.name
  policy_arn = "${local.policy_arn}/AmazonEKSWorkerNodePolicy"
}

# Attached even in Calico CNI mode — Approach A needs the self-managed VPC CNI
# to function during bootstrap so nodes become Ready before the CNI swap.
# The policy is harmless once Calico takes over (unused ENI permissions).
resource "aws_iam_role_policy_attachment" "node_AmazonEKS_CNI_Policy" {
  count      = local.managed_node_policies ? 1 : 0
  role       = aws_iam_role.node.name
  policy_arn = "${local.policy_arn}/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_AmazonEC2ContainerRegistryReadOnly" {
  count      = local.managed_node_policies ? 1 : 0
  role       = aws_iam_role.node.name
  policy_arn = "${local.policy_arn}/AmazonEC2ContainerRegistryReadOnly"
}

# Policies — pure Auto Mode only (lighter-weight, no managed nodes)
resource "aws_iam_role_policy_attachment" "node_AmazonEKSWorkerNodeMinimalPolicy" {
  count      = local.automode_node_policies ? 1 : 0
  role       = aws_iam_role.node.name
  policy_arn = "${local.policy_arn}/AmazonEKSWorkerNodeMinimalPolicy"
}

resource "aws_iam_role_policy_attachment" "node_AmazonEC2ContainerRegistryPullOnly" {
  count      = local.automode_node_policies ? 1 : 0
  role       = aws_iam_role.node.name
  policy_arn = "${local.policy_arn}/AmazonEC2ContainerRegistryPullOnly"
}

# ─────────────────────────────────────────────────────────────────────────────
# Cluster security group
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_security_group" "cluster" {
  name_prefix = "${var.cluster_name}-cluster-"
  description = "EKS cluster security group"
  vpc_id      = var.vpc_id

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-cluster-sg"
  })
}

resource "aws_vpc_security_group_egress_rule" "cluster_all" {
  security_group_id = aws_security_group.cluster.id
  description       = "Allow all outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# Allow VPN / private network CIDR blocks to reach the Kubernetes API (port 443)
resource "aws_vpc_security_group_ingress_rule" "cluster_private_access" {
  for_each = toset(var.private_access_cidrs)

  security_group_id = aws_security_group.cluster.id
  description       = "Allow HTTPS from ${each.value}"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = each.value
}

# ─────────────────────────────────────────────────────────────────────────────
# CloudWatch log group (created before the cluster so we control retention)
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.cluster_log_retention_days
}

# ─────────────────────────────────────────────────────────────────────────────
# EKS cluster
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids              = var.subnet_ids
    security_group_ids      = [aws_security_group.cluster.id]
    endpoint_private_access = true
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.endpoint_public_access ? var.public_access_cidrs : null
  }

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  enabled_cluster_log_types = var.cluster_log_types

  # ── Secrets encryption at rest ─────────────────────────────────────────────
  dynamic "encryption_config" {
    for_each = var.cluster_encryption_kms_key_arn != "" ? [1] : []
    content {
      provider {
        key_arn = var.cluster_encryption_kms_key_arn
      }
      resources = ["secrets"]
    }
  }

  # ── Auto Mode (pure or hybrid) ────────────────────────────────────────────

  dynamic "compute_config" {
    for_each = var.automode_enabled ? [1] : []
    content {
      enabled       = true
      node_pools    = var.automode_node_pools
      node_role_arn = aws_iam_role.node.arn
    }
  }

  dynamic "kubernetes_network_config" {
    for_each = var.automode_enabled ? [1] : []
    content {
      elastic_load_balancing {
        enabled = true
      }
    }
  }

  dynamic "storage_config" {
    for_each = var.automode_enabled ? [1] : []
    content {
      block_storage {
        enabled = true
      }
    }
  }

  tags = var.tags

  lifecycle {
    precondition {
      condition     = !(var.automode_enabled && var.calico_enabled && var.calico_mode == "cni")
      error_message = "Calico CNI mode is incompatible with EKS Auto Mode. Auto Mode manages the VPC CNI automatically. Use calico_mode = \"policy-only\" with Auto Mode instead."
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster_AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.cluster_AmazonEKSVPCResourceController,
    aws_iam_role_policy_attachment.cluster_AmazonEKSComputePolicy,
    aws_iam_role_policy_attachment.cluster_AmazonEKSBlockStoragePolicy,
    aws_iam_role_policy_attachment.cluster_AmazonEKSLoadBalancingPolicy,
    aws_iam_role_policy_attachment.cluster_AmazonEKSNetworkingPolicy,
    aws_cloudwatch_log_group.cluster,
  ]
}

# ─────────────────────────────────────────────────────────────────────────────
# OIDC provider for IRSA (IAM Roles for Service Accounts)
# ─────────────────────────────────────────────────────────────────────────────
data "tls_certificate" "cluster" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "cluster" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.cluster.certificates[0].sha1_fingerprint]
}

# ─────────────────────────────────────────────────────────────────────────────
# EKS addons — self-managed (only when Auto Mode is OFF)
# When Auto Mode is ON (pure or hybrid), it manages vpc-cni, coredns,
# kube-proxy, and pod-identity-agent automatically.
# ─────────────────────────────────────────────────────────────────────────────

# VPC CNI — enhanced networking with prefix delegation
#
# Custom networking flags (AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG, ENI_CONFIG_LABEL_DEF)
# are NOT set here because they require ENIConfig CRDs to exist first. Without
# ENIConfigs, the CNI cannot assign pod IPs and the addon fails to become healthy.
# ENIConfigs are created in layer 03-platform (eniconfig.tf), which also updates
# this addon to enable custom networking after the CRDs are in place.
resource "aws_eks_addon" "vpc_cni" {
  count        = local.use_vpc_cni ? 1 : 0
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "vpc-cni"

  # When transitioning to Calico CNI mode, this addon's count drops to 0.
  # preserve = true keeps the aws-node DaemonSet running as a self-managed
  # resource so new nodes (from the replaced node group) still get VPC CNI
  # during bootstrap. null_resource.remove_vpc_cni handles the actual cleanup
  # after nodes are Ready and before Calico is installed.
  preserve = true

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  configuration_values = jsonencode({
    env = merge(
      {
        ENABLE_PREFIX_DELEGATION          = tostring(var.vpc_cni_prefix_delegation)
        WARM_PREFIX_TARGET                = "1"
        ENABLE_POD_ENI                    = "true"
        POD_SECURITY_GROUP_ENFORCING_MODE = "standard"
      },
      var.vpc_cni_prefix_delegation ? {
        MINIMUM_IP_TARGET = "2"
      } : {}
    )
  })

  depends_on = [aws_eks_node_group.this]
}

# CoreDNS
resource "aws_eks_addon" "coredns" {
  count        = local.self_managed_addons ? 1 : 0
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "coredns"

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.this]
}

# kube-proxy
resource "aws_eks_addon" "kube_proxy" {
  count        = local.self_managed_addons ? 1 : 0
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "kube-proxy"

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.this]
}

# EKS Pod Identity Agent
resource "aws_eks_addon" "pod_identity_agent" {
  count        = local.self_managed_addons ? 1 : 0
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "eks-pod-identity-agent"

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.this]
}

# EBS CSI Driver
resource "aws_eks_addon" "ebs_csi_driver" {
  count        = var.ebs_csi_driver_enabled ? 1 : 0
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "aws-ebs-csi-driver"

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  service_account_role_arn = aws_iam_role.ebs_csi_driver[0].arn

  depends_on = [aws_eks_node_group.this]
}

# ── EBS CSI Driver IRSA ──────────────────────────────────────────────────────
data "aws_iam_policy_document" "ebs_csi_driver_assume_role" {
  count = var.ebs_csi_driver_enabled ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.cluster.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }
  }
}

resource "aws_iam_role" "ebs_csi_driver" {
  count              = var.ebs_csi_driver_enabled ? 1 : 0
  name               = "${var.cluster_name}-ebs-csi-driver"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_driver_assume_role[0].json
}

resource "aws_iam_role_policy_attachment" "ebs_csi_driver" {
  count      = var.ebs_csi_driver_enabled ? 1 : 0
  role       = aws_iam_role.ebs_csi_driver[0].name
  policy_arn = "${local.policy_arn}/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_iam_role_policy" "ebs_csi_driver_kms" {
  count = var.ebs_csi_driver_enabled && var.ebs_csi_kms_key_arns != null ? 1 : 0
  name  = "ebs-csi-driver-kms"
  role  = aws_iam_role.ebs_csi_driver[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "KMSAccess"
        Effect = "Allow"
        Action = [
          "kms:CreateGrant",
          "kms:ListGrants",
          "kms:DescribeKey",
        ]
        Resource = var.ebs_csi_kms_key_arns
        Condition = {
          Bool = {
            "kms:GrantIsForAWSResource" = "true"
          }
        }
      },
      {
        Sid    = "KMSEncryptDecrypt"
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncryptFrom",
          "kms:ReEncryptTo",
          "kms:GenerateDataKey",
          "kms:GenerateDataKeyWithoutPlaintext",
        ]
        Resource = var.ebs_csi_kms_key_arns
      }
    ]
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# EKS addons — all modes
# ─────────────────────────────────────────────────────────────────────────────

# Amazon CloudWatch Observability — Container Insights metrics only.
# Container log collection is disabled here; Fluent Bit is deployed via
# ArgoCD (argocd/apps/fluent-bit.yaml) for per-namespace log routing.
resource "aws_eks_addon" "cloudwatch_observability" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "amazon-cloudwatch-observability"

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  configuration_values = jsonencode({
    containerLogs = {
      enabled = false
    }
  })

  depends_on = [
    aws_eks_cluster.this,
    aws_eks_node_group.this,
    aws_iam_role_policy_attachment.node_CloudWatchAgentServerPolicy,
  ]
}

# ─────────────────────────────────────────────────────────────────────────────
# Managed node group
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_eks_node_group" "this" {
  count        = var.managed_node_group_enabled ? 1 : 0
  cluster_name = aws_eks_cluster.this.name
  # Name changes when Calico launch template is active so create_before_destroy
  # can stand up the new node group before tearing down the old one (EKS rejects
  # two node groups with the same name).
  node_group_name = local.use_calico_launch_template ? "${var.cluster_name}-calico" : "${var.cluster_name}-default"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids
  instance_types  = var.node_instance_types
  ami_type        = var.node_ami_type

  # disk_size cannot be set when using a launch template
  disk_size = local.use_calico_launch_template ? null : var.node_disk_size

  dynamic "launch_template" {
    for_each = local.use_calico_launch_template ? [1] : []
    content {
      id      = aws_launch_template.calico_cni[0].id
      version = aws_launch_template.calico_cni[0].latest_version
    }
  }

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.node_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.node_AmazonEC2ContainerRegistryReadOnly,
    aws_iam_role_policy_attachment.node_AmazonSSMManagedInstanceCore,
    aws_iam_role_policy_attachment.node_CloudWatchAgentServerPolicy,
  ]

  tags = var.tags

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [scaling_config[0].desired_size]
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Additional managed node groups (for_each over var.additional_node_groups)
#
# Shares the cluster's node IAM role and, when Calico CNI mode is active, the
# cluster's Calico launch template (aws_launch_template.calico_cni). The name
# carries the same -calico suffix mechanic as aws_eks_node_group.this so a
# future Calico on/off flip can create_before_destroy without a name collision.
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_eks_node_group" "additional" {
  for_each = var.additional_node_groups

  cluster_name    = aws_eks_cluster.this.name
  node_group_name = local.use_calico_launch_template ? "${var.cluster_name}-${each.key}-calico" : "${var.cluster_name}-${each.key}"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = coalesce(each.value.subnet_ids, var.subnet_ids)
  instance_types  = each.value.instance_types
  ami_type        = each.value.ami_type
  capacity_type   = each.value.capacity_type

  # disk_size cannot be set when using a launch template
  disk_size = local.use_calico_launch_template ? null : each.value.disk_size

  dynamic "launch_template" {
    for_each = local.use_calico_launch_template ? [1] : []
    content {
      id      = aws_launch_template.calico_cni[0].id
      version = aws_launch_template.calico_cni[0].latest_version
    }
  }

  scaling_config {
    desired_size = each.value.desired_size
    min_size     = each.value.min_size
    max_size     = each.value.max_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = each.value.labels

  dynamic "taint" {
    for_each = each.value.taints
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.node_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.node_AmazonEC2ContainerRegistryReadOnly,
    aws_iam_role_policy_attachment.node_AmazonSSMManagedInstanceCore,
    aws_iam_role_policy_attachment.node_CloudWatchAgentServerPolicy,
  ]

  tags = merge(var.tags, { NodeGroup = each.key })

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [scaling_config[0].desired_size]
  }
}
