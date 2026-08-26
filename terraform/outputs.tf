output "webhook_endpoint" {
  description = "Set this as the GitHub App's Webhook → Payload URL (docs/02-setup-guide.md, step 5)."
  value       = module.github_runner.webhook.endpoint
}

output "runner_iam_role_arn" {
  description = "IAM role assumed by runner EC2 instances — attach additional policies here if jobs need AWS access."
  value       = module.github_runner.runners.role_runner.arn
}

output "runner_security_group_id" {
  description = "Security group attached to runner instances — reference this when wiring up access to other resources."
  value       = aws_security_group.runner_access.id
}

output "scale_up_lambda_name" {
  description = "Scale-up Lambda function name — useful for the CloudWatch Logs Insights boot-latency check in docs/01-concepts.md."
  value       = module.github_runner.runners.lambda_up.function_name
}

output "runner_labels" {
  description = "GitHub Actions runs-on labels this fleet registers under."
  value       = module.github_runner.runners.labels
}
