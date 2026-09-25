# Ported from github.com/mchmarny/cluster provider/eks/terraform/cluster.tf @ 0ac8457
# (MIT, Copyright (c) 2025 Mark Chmarny; see LICENSE in this directory).
# Changes: config lookups -> typed variables; coredns, metrics-server, ebs-csi and
#   cloudwatch-observability add-ons moved to ../eks-compute/addons.tf (after the
#   node groups); vpc-cni moved to ../cluster-prereqs (after the ENIConfigs); the
#   toleration locals moved with the add-ons that use them.

locals {
  # #10: Normalize addon versions — empty string means latest (null)
  addon_versions = {
    for k, v in var.cluster.add_ons :
    k => v == "" ? null : v
  }
}

# KMS Key for EKS Secret Encryption
resource "aws_kms_key" "eks" {
  description             = "${local.prefix} EKS Secret Encryption Key"
  deletion_window_in_days = local.kms_deletion_window_days
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${local.account}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow CloudWatch Logs"
        Effect = "Allow"
        Principal = {
          Service = "logs.${local.region}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:CreateGrant",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${local.region}:${local.account}:log-group:*"
          }
        }
      }
    ]
  })

  # #5: Removed LastReconciled timestamp tag (caused drift every apply)
  tags = { Name = "${local.prefix}-eks-secrets" }
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${local.prefix}-eks-secrets"
  target_key_id = aws_kms_key.eks.key_id
}

# CloudWatch Log Group for EKS Control Plane
resource "aws_cloudwatch_log_group" "eks_cluster" {
  name              = "/aws/eks/cluster/${local.prefix}-${local.cluster_name}"
  retention_in_days = local.log_retention_days
  kms_key_id        = aws_kms_key.eks.arn

  tags = { Name = "${local.prefix}-eks-control-plane-logs" }
}

# EKS Cluster
resource "aws_eks_cluster" "main" {
  name     = local.cluster_name
  version  = local.eks_version
  role_arn = aws_iam_role.eks_cluster.arn

  enabled_cluster_log_types = ["api", "authenticator", "audit", "scheduler", "controllerManager"]

  tags = { Name = local.cluster_name }

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  encryption_config {
    provider {
      key_arn = aws_kms_key.eks.arn
    }
    resources = ["secrets"]
  }

  kubernetes_network_config {
    service_ipv4_cidr = local.service_cidr
  }

  vpc_config {
    endpoint_private_access = true
    endpoint_public_access  = true
    subnet_ids              = local.system_subnet_ids

    public_access_cidrs = concat(
      var.cluster.allowed_cidrs,
      [local.egress_cidr],
    )

    security_group_ids = [
      aws_security_group.main["${local.prefix}-system"].id,
      aws_security_group.main["${local.prefix}-worker"].id
    ]
  }

  # #17: Keep only IAM policy + log group deps (cluster already refs KMS by attribute)
  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_vpc_resource_controller,
    aws_cloudwatch_log_group.eks_cluster,
  ]
}

# EKS Access Entries
# System nodes use an EKS managed node group — access entry auto-created
resource "aws_eks_access_entry" "worker_nodes" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_iam_role.worker_nodes.arn
  type          = "EC2_LINUX"

  tags = { Name = "${local.prefix}-worker-nodes-access" }
}

# EKS Access Entries for Admin Roles
# Supports two formats:
#   - Full ARN: arn:aws:iam::ACCOUNT:role/path/ROLE_NAME (used as-is)
#   - Role name: MyRole or AWSReservedSSO_* (looked up via IAM data source)
data "aws_iam_role" "admin_roles" {
  for_each = {
    for role in var.cluster.admin_roles :
    role => role if !startswith(role, "arn:")
  }
  name = each.value
}

locals {
  configured_admin_role_arns = merge(
    # Roles looked up via data source (by name)
    { for k, v in data.aws_iam_role.admin_roles : k => v.arn },
    # Roles provided as full ARNs (used as-is)
    { for role in var.cluster.admin_roles : role => role if startswith(role, "arn:") }
  )

  # EKS auto-creates an access entry for the deploying principal
  # (bootstrap_cluster_creator_admin_permissions = true), so an explicit entry
  # for the same role fails with ResourceInUseException. The caller ARN is an
  # STS assumed-role ARN that drops the IAM role path, so the creator is
  # matched by account ID + role name rather than full ARN.
  creator_role_name = (
    strcontains(data.aws_caller_identity.current.arn, ":assumed-role/")
    ? split("/", data.aws_caller_identity.current.arn)[1]
    : null
  )

  admin_role_arns = {
    for k, v in local.configured_admin_role_arns : k => v
    if local.creator_role_name == null || !(
      split(":", v)[4] == data.aws_caller_identity.current.account_id &&
      element(split("/", v), length(split("/", v)) - 1) == local.creator_role_name
    )
  }
}

resource "aws_eks_access_entry" "admin_roles" {
  for_each = local.admin_role_arns

  cluster_name  = aws_eks_cluster.main.name
  principal_arn = each.value
  type          = "STANDARD"

  tags = { Name = "${local.prefix}-${replace(each.key, "/[^a-zA-Z0-9-]/", "-")}-access" }
}

# #18: Only ClusterAdminPolicy (superset of EKSAdminPolicy — removed duplicate)
resource "aws_eks_access_policy_association" "admin_cluster_admin" {
  for_each = local.admin_role_arns

  cluster_name  = aws_eks_cluster.main.name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  principal_arn = each.value

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.admin_roles]
}

# EKS Add-ons
#
# Only kube-proxy stays with the cluster. vpc-cni moved to ../cluster-prereqs
# (it must follow the ENIConfig objects, which now live in the graph), and
# coredns, metrics-server, ebs-csi and cloudwatch-observability moved to
# ../eks-compute/addons.tf: they are Deployments, so they are created after the
# node groups exist rather than racing them.
resource "aws_eks_addon" "kube_proxy" {
  count = var.cluster.add_ons.kube_proxy != null ? 1 : 0

  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "kube-proxy"
  addon_version               = local.addon_versions.kube_proxy
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = { Name = "${local.prefix}-kube-proxy" }
}

data "tls_certificate" "oidc_provider" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "oidc_provider" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer

  client_id_list = ["sts.amazonaws.com"]

  thumbprint_list = [data.tls_certificate.oidc_provider.certificates[0].sha1_fingerprint]

  tags = { Name = "${local.prefix}-oidc-provider" }
}
