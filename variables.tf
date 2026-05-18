variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Optional project name inserted into the cluster name. When set, the cluster is named {environment}-{project_name}-eks (e.g. prod-sharedservices-eks). When empty, the cluster is named {environment}-eks."
  type        = string
  default     = ""
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.32"
}

# ── Compute mode ─────────────────────────────────────────────────────────────

variable "automode_enabled" {
  description = "Enable EKS Auto Mode (AWS manages compute, networking addons, and storage)"
  type        = bool
  default     = false
}

variable "automode_node_pools" {
  description = "Node pool types for Auto Mode"
  type        = list(string)
  default     = ["general-purpose", "system"]
}

variable "managed_node_group_enabled" {
  description = "Create a managed node group. Can be combined with Auto Mode for hybrid compute."
  type        = bool
  default     = true
}

variable "karpenter_enabled" {
  description = "Provision Karpenter infrastructure (controller IAM role, instance profile, SQS queue, EventBridge rules)"
  type        = bool
  default     = false
}

# ── Cluster access ────────────────────────────────────────────────────────────

variable "access_entries" {
  description = "Map of IAM principal ARN to EKS access configuration. Key is the IAM role/user ARN. When namespaces is empty the policy applies cluster-wide."
  type = map(object({
    access_policy_arn = string
    namespaces        = optional(list(string), [])
  }))
  default = {}
}

# ── Networking ───────────────────────────────────────────────────────────────

variable "endpoint_public_access" {
  description = "Whether the EKS API server endpoint is publicly accessible (set false for prod)"
  type        = bool
  default     = false
}

variable "public_access_cidrs" {
  description = "List of CIDR blocks allowed to access the EKS public API endpoint. Only used when endpoint_public_access is true."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "private_access_cidrs" {
  description = "List of CIDR blocks (e.g. VPN) allowed to reach the EKS API server on port 443 via the private endpoint. Adds ingress rules to the cluster security group."
  type        = list(string)
  default     = []
}

variable "vpc_tags" {
  description = "Tags used to look up the VPC (e.g. { Name = \"dev-vpc\" }). Must match exactly one VPC."
  type        = map(string)
}

variable "subnet_tags" {
  description = "Tags used to filter subnets within the VPC (e.g. { Tier = \"private\" }). All matching subnets are used for the cluster and node groups."
  type        = map(string)
}

# ── Node group (requires managed_node_group_enabled) ────────────────────────

variable "node_instance_types" {
  description = "EC2 instance types for the managed node group"
  type        = list(string)
  default     = ["m5.xlarge"]
}

variable "node_desired_size" {
  description = "Desired number of nodes (ignored in Auto Mode)"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of nodes (ignored in Auto Mode)"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of nodes (ignored in Auto Mode)"
  type        = number
  default     = 5
}

variable "node_disk_size" {
  description = "Root EBS volume size in GiB for worker nodes (ignored in Auto Mode)"
  type        = number
  default     = 50
}

variable "node_ami_type" {
  description = "AMI type for the managed node group (ignored in Auto Mode)"
  type        = string
  default     = "AL2023_x86_64_STANDARD"
}

# ── Additional node groups ───────────────────────────────────────────────────

variable "additional_node_groups" {
  description = "Map of additional managed node groups created alongside the default group. Each entry yields one EKS node group named \"$${cluster_name}-$${key}\" (or \"-$${key}-calico\" when Calico CNI launch template is active). See the eks-cluster module for object shape details."
  type = map(object({
    instance_types = list(string)
    ami_type       = optional(string, "AL2023_x86_64_STANDARD")
    capacity_type  = optional(string, "ON_DEMAND")
    disk_size      = optional(number, 50)
    desired_size   = number
    min_size       = number
    max_size       = number
    labels         = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = optional(string)
      effect = string
    })), [])
    subnet_ids = optional(list(string))
  }))
  default = {}
}

# ── Control plane logging ────────────────────────────────────────────────────

variable "cluster_log_types" {
  description = "EKS control plane log types to enable"
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "cluster_log_retention_days" {
  description = "CloudWatch log retention in days for control plane logs"
  type        = number
  default     = 90
}

# ── VPC CNI (managed mode without Auto Mode only) ───────────────────────────

variable "vpc_cni_prefix_delegation" {
  description = "Enable VPC CNI prefix delegation for higher pod density (ignored when Auto Mode is enabled)"
  type        = bool
  default     = true
}

# ── Calico CNI ────────────────────────────────────────────────────────────────

variable "calico_enabled" {
  description = "Deploy Calico via Helm. When true, calico_mode controls the deployment model."
  type        = bool
  default     = false
}

variable "calico_mode" {
  description = "Calico deployment mode: 'policy-only' keeps VPC CNI for networking and uses Calico for network policy enforcement. 'cni' replaces VPC CNI entirely with Calico for both networking and policy. Note: 'cni' mode is incompatible with EKS Auto Mode and requires kubectl + aws CLI on the Terraform runner."
  type        = string
  default     = "policy-only"
  validation {
    condition     = contains(["policy-only", "cni"], var.calico_mode)
    error_message = "calico_mode must be 'policy-only' or 'cni'."
  }
}

variable "calico_version" {
  description = "Tigera Calico operator Helm chart version"
  type        = string
  default     = "3.29.3"
}

variable "calico_pod_cidr" {
  description = "Pod CIDR for Calico IPAM (only used when calico_mode = 'cni'). Must not overlap with VPC CIDR."
  type        = string
  default     = "192.168.0.0/16"
}

variable "calico_encapsulation" {
  description = "Calico encapsulation mode when calico_mode = 'cni': VXLAN, IPIP, or None"
  type        = string
  default     = "VXLAN"
  validation {
    condition     = contains(["VXLAN", "IPIP", "None"], var.calico_encapsulation)
    error_message = "calico_encapsulation must be 'VXLAN', 'IPIP', or 'None'."
  }
}

variable "calico_chart_repository" {
  description = "Helm chart repository URL for the Tigera operator. Defaults to the public chart repo. For ECR OCI registries, use oci:// prefix (e.g. oci://<account>.dkr.ecr.<region>.amazonaws.com)."
  type        = string
  default     = "https://docs.tigera.io/calico/charts"
}

variable "calico_image_registry" {
  description = "Custom container image registry for all Calico/Tigera images (operator + components). Overrides the default public registries. Use for ECR pull-through cache (e.g. <account>.dkr.ecr.<region>.amazonaws.com/quay)."
  type        = string
  default     = ""
}

variable "calico_image_pull_secrets" {
  description = "List of Kubernetes Secret names for pulling Calico images from a private registry. Not typically needed for ECR pull-through cache when nodes have IAM-based ECR access."
  type        = list(string)
  default     = []
}

variable "calico_max_pods_per_node" {
  description = "Maximum pods per node when using Calico CNI mode. Overrides the default ENI-based limit since Calico manages its own IPAM. Set to 0 to skip the override. Only applies when calico_mode = 'cni'."
  type        = number
  default     = 110
}
