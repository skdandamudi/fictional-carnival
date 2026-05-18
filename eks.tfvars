aws_region         = "us-east-1"
environment        = "prod"
project_name       = "sharedservices"
kubernetes_version = "1.32"

# ── VPC & subnet lookup ────────────────────────────────────────────────────
vpc_tags    = { Name = "prod-sharedservices-vpc" }
subnet_tags = { Tier = "private" }

# ── Compute mode ─────────────────────────────────────────────────────────────
automode_enabled           = false
managed_node_group_enabled = true
karpenter_enabled          = false

# ── Endpoint access ──────────────────────────────────────────────────────────
endpoint_public_access = false

# ── Node group ───────────────────────────────────────────────────────────────
node_instance_types = ["m5.xlarge"]
node_desired_size   = 2
node_max_size       = 5

# ── Additional node groups ───────────────────────────────────────────────────
# Zscaler workload runs on a dedicated node group via taint + label.
# Pods must set: nodeSelector { workload: zscaler } and tolerate
# { key: dedicated, value: zscaler, effect: NoSchedule }.
additional_node_groups = {
  zscaler = {
    instance_types = ["m5.xlarge"]
    desired_size   = 2
    min_size       = 1
    max_size       = 5
    labels = {
      workload = "zscaler"
    }
    taints = [{
      key    = "dedicated"
      value  = "zscaler"
      effect = "NO_SCHEDULE"
    }]
  }
}

# ── Calico CNI ───────────────────────────────────────────────────────────────
calico_enabled = false
