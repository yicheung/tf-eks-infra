output "guardduty_detector_id" {
  description = "GuardDuty detector ID."
  value       = local.detector_id
}

output "security_alerts_topic_arn" {
  description = "SNS topic for security alerts. Falcosidekick can publish here too."
  value       = aws_sns_topic.security_alerts.arn
}

output "security_alerts_kms_key_arn" {
  description = "KMS key protecting the alerts topic. Publishers need kms:GenerateDataKey on it."
  value       = aws_kms_key.alerts.arn
}
