output "ebs_kms_key_arn" {
  description = "KMS key the encrypted StorageClass uses for EBS volumes."
  value       = aws_kms_key.ebs.arn
}

output "ebs_csi_addon_version" {
  description = "Installed EBS CSI driver add-on version."
  value       = aws_eks_addon.ebs_csi.addon_version
}
