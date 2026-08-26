# Setup guide — personal / single-account scope

This walks through standing up **one** ephemeral Spot runner fleet, backed by one custom AMI, scoped to your own GitHub account or a single org. It's the "works for me" path. If you're rolling this out for an organization with multiple teams, read this first, then see [org rollout notes](03-org-rollout.md) for what changes.

Background on *why* each piece exists is in [concepts](01-concepts.md) — this doc is the "what to actually run."

## Prerequisites

| Tool | Purpose | Version used as reference |
|---|---|---|
| Terraform | Provision runner infra, IAM | >= 1.13.x (latest stable: 1.16.x) |
| Packer | Build the custom runner AMI | latest 1.x |
| AWS CLI | Auth, secrets, general AWS ops | v2 |
| GitHub admin access | Create the GitHub App (org admin, or repo admin for a personal-account/single-repo setup) | — |
| An AWS account with a VPC already provisioned | Runners launch into existing subnets | — |

You'll need permission to create IAM roles, EC2 instances/AMIs, Lambda functions, API Gateway, Secrets Manager secrets, and CloudWatch log groups.

The Terraform in [`terraform/`](../terraform) is parameterized with variables — no placeholder find-and-replace needed. You'll fill in real values in `terraform.tfvars` in Step 4.

## Step 1 — Create a GitHub App

Self-hosted runners need an identity to register themselves with GitHub. A GitHub App (not a PAT) is the standard mechanism because it can be scoped tightly and rotated without touching a human account.

1. GitHub → **Settings → Developer settings → GitHub Apps → New GitHub App** (org-level: **Organization Settings → Developer settings**; personal-account/single-repo: your personal **Settings**).
2. Repository permissions:

    | Permission | Access |
    |---|---|
    | Actions | Read-only |
    | Checks | Read-only |
    | Administration | Read & write |
    | Metadata | Read-only |

3. Organization permissions (org-scoped installs only):

    | Permission | Access |
    |---|---|
    | Self-hosted runners | Read & write |

4. Subscribe to the **Workflow job** webhook event.
5. Generate a private key (downloads a `.pem`), note the **App ID**, and set a **Webhook secret**.
6. Install the app on your account/org, scoped to the repo(s) you want to use it with.

## Step 2 — Store the GitHub App credentials in AWS Secrets Manager

Base64-encode the private key:

```bash
cat your-app-private-key.pem | base64 -w 0
```

Create a secret (name it something like `<PROJECT_NAME>-github-app-secrets`) with this shape:

```json
{
  "github_app_id": "123456",
  "github_app_key_base64": "<base64-encoded-private-key>",
  "github_app_webhook_secret": "your-webhook-secret"
}
```

```bash
aws secretsmanager create-secret \
  --name "<PROJECT_NAME>-github-app-secrets" \
  --secret-string file://github-app-secrets.json \
  --region <REGION>
```

Never commit the raw JSON or `.pem` — only reference the secret name from Terraform.

## Step 3 — Build the custom AMI

Do this before deploying the Terraform module — the module's `ami` filter needs a matching AMI to already exist.

### What goes into it

At minimum, mirror what the reference AMI carries:

- Ubuntu 22.04 LTS (or your preferred base)
- Docker (for containerized builds)
- The GitHub Actions Runner binary
- AWS CLI v2
- Common tools: `git`, `curl`, `jq`, `unzip`

Add anything your pipelines actually need pre-installed (language runtimes, `uv`/`poetry`, `kubectl`, `helm`, `terraform`, scanners, etc.) — every tool baked into the AMI is one less install per job.

### Build it

The `terraform-aws-github-runner` project ships a ready-made Packer template — don't write one from scratch unless you need to diverge significantly.

```bash
git clone https://github.com/github-aws-runners/terraform-aws-github-runner
cd terraform-aws-github-runner/images/ubuntu-jammy
```

If you need extra tools baked in, edit the provisioning steps in this directory's `.pkr.hcl` / associated scripts before building (or fork it and add your own provisioner block).

```bash
packer init github_agent.ubuntu.pkr.hcl
packer build -var "region=<REGION>" github_agent.ubuntu.pkr.hcl
```

What happens under the hood:

1. Packer launches a temporary EC2 instance from a base Ubuntu AMI in `<REGION>`
2. It runs the provisioning scripts (Docker, runner binary, AWS CLI, your extra tools)
3. It stops the instance and snapshots it as a new AMI
4. It terminates the temporary instance
5. The resulting AMI appears in your account, named by convention — e.g. `<PROJECT_NAME>-runner-ubuntu-jammy-amd64-<timestamp>`

Requirements to run this:

- AWS credentials with EC2 (`RunInstances`, `CreateImage`, `TerminateInstances`, snapshot permissions) in the target account
- Outbound internet from wherever Packer runs (to fetch the base AMI's packages)
- The **naming convention must match** whatever `filter.name` pattern your Terraform config expects (Step 4) — this is how Terraform picks up new builds automatically.

## Step 4 — Deploy the Terraform module

Don't hand-roll the webhook/scaling logic — the [`terraform/`](../terraform) directory in this repo wraps the community-maintained [`github-aws-runners/terraform-aws-github-runner`](https://github.com/github-aws-runners/terraform-aws-github-runner) module (pinned to `7.11.0`) and is ready to run as-is:

| File | What's in it |
|---|---|
| [`terraform/versions.tf`](../terraform/versions.tf) | Terraform/provider version constraints |
| [`terraform/variables.tf`](../terraform/variables.tf) | Every input you can tune — region, account, VPC, instance types, fleet size, etc. |
| [`terraform/main.tf`](../terraform/main.tf) | The security group, the Secrets Manager lookup, and the `github_runner` module block itself |
| [`terraform/outputs.tf`](../terraform/outputs.tf) | Webhook URL, runner IAM role ARN, and other values you need after `apply` |
| [`terraform/terraform.tfvars.example`](../terraform/terraform.tfvars.example) | Template for your own `terraform.tfvars` (gitignored) |

Set it up:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: aws_region, aws_account_id, project_name, vpc_id, subnet_ids

../scripts/download-lambda-packages.sh 7.11.0   # must match the module version pinned in main.tf
```

> **Why a separate download step**: the module's Lambda code is distributed as versioned zip releases, not vendored into the module itself — `main.tf` references them from `terraform/lambda-packages/`, which is gitignored (build artifacts, not source). If you bump the module version in `main.tf`, re-run this script with the matching version — a mismatch here is a real, easy-to-miss failure mode.

```bash
terraform init
terraform plan
terraform apply
```

`project_name` drives both the AMI name filter and the `-github-app-secrets` Secrets Manager lookup — make sure it matches what you used in Steps 2 and 3.

## Step 5 — Point the GitHub App at the deployed webhook

```bash
terraform output -raw webhook_endpoint
```

Set the printed URL as the GitHub App's webhook URL (App settings → **Webhook → Payload URL**).

## Step 6 — Use it in workflows

Any job with the `self-hosted` label (plus whatever OS/arch labels you configured) now routes to your fleet instead of GitHub-hosted runners:

```yaml
name: ci

on:
  pull_request:
  push:
    branches: [main]

jobs:
  build-and-test:
    runs-on: [self-hosted, linux, x64]
    steps:
      - uses: actions/checkout@<pinned-sha>

      # Proves this is actually your fleet, and a fresh instance per job —
      # a persistent/reused runner would show the same instance ID across runs.
      - name: Identify the runner instance
        run: |
          TOKEN=$(curl -fs -X PUT "http://169.254.169.254/latest/api/token" \
            -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
          curl -fs -H "X-aws-ec2-metadata-token: $TOKEN" \
            http://169.254.169.254/latest/meta-data/instance-id

      # Proves ephemeral behavior: a leftover marker from a prior job means
      # this instance was reused instead of freshly launched.
      - name: Confirm no state left over from a previous job
        run: |
          test ! -f /tmp/ci-marker && echo "clean instance, no prior job state"
          touch /tmp/ci-marker

      # Self-contained smoke test — proves Docker itself works from the AMI
      - name: Docker smoke test
        run: docker run --rm hello-world
```

Two things worth checking the first time you run this: the instance ID printed should be different on every run (confirms ephemeral, not reused), and the smoke test should start immediately without any `apt install`/image-layer-download output beyond pulling `hello-world` itself (confirms Docker and the runner binary came from the AMI, not a fresh install). If you see package-manager output on a "normal" run, something's pulling from outside the AMI and it's worth finding out what.

## Next

- Rebuilding the AMI, cleanup, cost expectations → [operations](05-operations.md)
- Rolling this out beyond a single account/team → [org rollout notes](03-org-rollout.md)
- One fleet enough, or do you need several? → [runner strategies](04-runner-strategies.md)
