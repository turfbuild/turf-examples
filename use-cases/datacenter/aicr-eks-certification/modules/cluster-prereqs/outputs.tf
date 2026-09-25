output "eni_config_zones" {
  value = sort(keys(kubernetes_manifest.eniconfig))
}

output "vpc_cni" {
  value = length(aws_eks_addon.vpc_cni) > 0 ? {
    version = aws_eks_addon.vpc_cni[0].addon_version
    arn     = aws_eks_addon.vpc_cni[0].arn
  } : null
}
