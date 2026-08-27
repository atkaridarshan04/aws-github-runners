data "aws_secretsmanager_secret" "github_app_secrets" {
  name = "${var.project_name}-github-app-secrets"
}

data "aws_secretsmanager_secret_version" "github_app_secrets" {
  secret_id = data.aws_secretsmanager_secret.github_app_secrets.id
}

locals {
  github_app_secrets = jsondecode(data.aws_secretsmanager_secret_version.github_app_secrets.secret_string)
}

# Security group for the runner to reach whatever it needs (internal services, etc.).
# Left with AWS's default (all egress, no ingress) — add rules as your workloads require.
resource "aws_security_group" "runner_access" {
  name_prefix = "${var.project_name}-runner-access-sg"
  vpc_id      = var.vpc_id
  tags        = var.tags
}

module "github_runner" {
  source  = "github-aws-runners/github-runner/aws"
  version = "7.11.0" # pin explicitly — do not float on a range. Bump deliberately; the
  # downloaded Lambda zip release (scripts/download-lambda-packages.sh) must match this.

  aws_region = var.aws_region
  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids
  prefix     = "${var.project_name}-gh-runner"
  tags       = var.tags

  github_app = {
    id             = local.github_app_secrets["github_app_id"]
    key_base64     = local.github_app_secrets["github_app_key_base64"]
    webhook_secret = local.github_app_secrets["github_app_webhook_secret"]
  }

  runner_os           = "linux"
  runner_architecture = "x64"
  runner_run_as       = "ubuntu"

  # Spot for cost, price-capacity-optimized for fewer interruptions.
  instance_types                = var.instance_types
  instance_target_capacity_type = "spot"
  instance_allocation_strategy  = "price-capacity-optimized"

  runners_maximum_count           = var.runners_maximum_count
  create_service_linked_role_spot = true
  enable_organization_runners     = var.enable_organization_runners
  enable_ephemeral_runners        = true
  enable_userdata                 = false # not needed — everything is baked into the AMI
  scale_down_schedule_expression  = var.scale_down_schedule_expression
  minimum_running_time_in_minutes = var.minimum_running_time_in_minutes

  scale_up_reserved_concurrent_executions = var.scale_up_reserved_concurrent_executions

  runner_additional_security_group_ids = [aws_security_group.runner_access.id]

  # Matches the AMI built by Packer
  ami = {
    filter = {
      name  = ["github-runner-ubuntu-jammy-amd64-*"]
      state = ["available"]
    }
    owners = [var.aws_account_id]
  }

  block_device_mappings = [{
    device_name           = "/dev/sda1"
    volume_size           = var.root_volume_size_gb
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }]

  # Downloaded separately (scripts/download-lambda-packages.sh) — must match the module version pinned above
  webhook_lambda_zip                = "${path.module}/lambda-packages/webhook.zip"
  runners_lambda_zip                = "${path.module}/lambda-packages/runners.zip"
  runner_binaries_syncer_lambda_zip = "${path.module}/lambda-packages/runner-binaries-syncer.zip"

  log_level                 = var.log_level
  logging_retention_in_days = var.logging_retention_in_days
}
