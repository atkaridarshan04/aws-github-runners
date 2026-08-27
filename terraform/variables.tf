variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID that owns the custom AMI (usually this account) — scopes the AMI lookup filter."
  type        = string
}

variable "project_name" {
  description = "Short name used to prefix resources and to build the AMI name-filter pattern. Must match the naming convention your Packer build produces (see docs/02-setup-guide.md)."
  type        = string
}

variable "vpc_id" {
  description = "VPC the runners launch into."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets the runners launch into."
  type        = list(string)
}

variable "instance_types" {
  description = "Candidate EC2 instance types for the Spot fleet, in preference order."
  type        = list(string)
  default     = ["t3a.medium", "c5a.large", "c6a.large", "t3.medium", "c5.large", "c6i.large"]
}

variable "runners_maximum_count" {
  description = "Upper bound on concurrently running runner instances."
  type        = number
  default     = 8
}

variable "scale_up_reserved_concurrent_executions" {
  description = "Reserved concurrency for the scale-up Lambda. AWS requires >= 10 unreserved concurrent executions to always remain in the account/region — on a fresh account with a low account-wide Lambda concurrency quota, even the upstream default of 1 can violate that floor. Set to -1 to remove the reservation entirely (no limit) if you hit 'decreases account's UnreservedConcurrentExecution below its minimum value of [10]' on apply; set back to a small positive number once you've requested a concurrency quota increase."
  type        = number
  default     = 1
}

variable "enable_organization_runners" {
  description = "true = runners register at the GitHub org level (any in-scope repo can use them)."
  type        = bool
  default     = false
}

variable "root_volume_size_gb" {
  description = "Root EBS volume size for runner instances, in GB."
  type        = number
  default     = 100
}

variable "scale_down_schedule_expression" {
  description = "How often the scale-down Lambda sweeps for idle/orphaned runners."
  type        = string
  default     = "cron(*/5 * * * ? *)"
}

variable "minimum_running_time_in_minutes" {
  description = "Minimum time a runner instance must run before scale-down will consider terminating it as orphaned — must cover your actual boot time."
  default     = 15
}

variable "log_level" {
  description = "Log level for the module's Lambda functions."
  type        = string
  default     = "info"
}

variable "logging_retention_in_days" {
  description = "CloudWatch log retention for the module's Lambda functions."
  type        = number
  default     = 7
}

variable "tags" {
  description = "Tags applied to all resources created by this config."
  type        = map(string)
  default     = {}
}
