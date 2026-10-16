variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "create_guardduty_detector" {
  description = "Create the account/region GuardDuty detector. Set false if one already exists (e.g. enabled by your org) and pass its ID."
  type        = bool
  default     = true
}

variable "existing_guardduty_detector_id" {
  description = "Detector ID to enable EKS features on when create_guardduty_detector = false."
  type        = string
  default     = null
}

variable "alert_emails" {
  description = "Email addresses subscribed to high-severity security alerts."
  type        = list(string)
  default     = []
}

variable "alert_min_severity" {
  description = "Minimum GuardDuty severity (1-10) that triggers an alert. 7 = High."
  type        = number
  default     = 7
}

variable "enable_container_logs" {
  description = "Install the CloudWatch Observability add-on for container logs and Container Insights."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
