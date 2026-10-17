output "platform_alerts_topic_arn" {
  description = "SNS topic Alertmanager publishes to."
  value       = aws_sns_topic.platform_alerts.arn
}

output "alertmanager_role_arn" {
  description = "IAM role bound to the Alertmanager ServiceAccount."
  value       = module.alertmanager_identity.iam_role_arn
}
