# aws-github-runners

> Terraform + Packer blueprint for self-hosted, ephemeral GitHub Actions runners on EC2 Spot with a custom AMI.

A generic, portable blueprint for self-hosted ephemeral GitHub Actions runners on AWS: EC2 Spot instances booting from a custom Packer AMI, autoscaled by the community [`github-aws-runners/terraform-aws-github-runner`](https://github.com/github-aws-runners/terraform-aws-github-runner) module.

Terraform in [`terraform/`](terraform) is driven entirely by `terraform.tfvars` (region, account ID, project name, VPC/subnets), so this applies to any repo or stack without editing source.

Scope is deliberately just the compute/pipeline layer — how jobs get a runner, not what those jobs do once they're on it. Any workflow you'd normally run can run on top of this.

---

## Why this exists

- **Cheaper than GitHub-hosted minutes** once you're running more than a trivial amount of CI, and it sidesteps GitHub's runner queue during traffic spikes.
- **Ephemeral** — each runner is launched fresh for one job, registers, runs, deregisters, and terminates. No idle fleet, no state surviving between jobs.
- **Spot** — ephemeral runners are the ideal Spot workload (short-lived, retry-safe), routinely ~70% cheaper than on-demand.
- **Custom AMI** — Docker, the runner binary, and your tools are pre-baked, so there's no install-at-boot step. How much that actually saves for your setup: [docs/01-concepts.md](docs/01-concepts.md#how-fast-is-boot-really).

## Architecture

```mermaid
flowchart TD
    A[Developer pushes / opens PR] --> B[GitHub detects workflow trigger]
    B --> C[GitHub App webhook fires]
    C --> D[API Gateway]
    D --> E[Webhook Lambda<br/>validates signature]
    E --> F[Scale-up Lambda]
    F --> G[EC2 Spot instance launched<br/>from custom AMI]
    G --> H[Runner boots & registers with GitHub]
    H --> I[Job executes on runner]
    I --> P[Job finishes<br/>runner deregisters & terminates]

    style G fill:#2b6cb0,color:#fff
    style P fill:#2f855a,color:#fff
```

Full breakdown of each component (webhook Lambda, scale-up Lambda, binary syncer, etc.) is in [docs/01-concepts.md](docs/01-concepts.md).

## Docs

| Doc | What's in it |
|---|---|
| [docs/01-concepts.md](docs/01-concepts.md) | Why ephemeral + Spot + custom AMI, and what each infra component does |
| [docs/02-setup-guide.md](docs/02-setup-guide.md) | Step-by-step: GitHub App → secrets → build the AMI → deploy Terraform → wire it up |
| [docs/03-org-rollout.md](docs/03-org-rollout.md) | What changes going from a personal/single-team setup to an org-wide rollout |
| [docs/04-runner-strategies.md](docs/04-runner-strategies.md) | Ephemeral vs. persistent, one fleet vs. several ("multi-cluster") — when to use which |
| [docs/05-operations.md](docs/05-operations.md) | Capacity limits, AMI rebuilds, cost notes, troubleshooting, teardown |

## Quick start

Prerequisites: an AWS account with a VPC, org or repo admin on GitHub, Terraform, Packer and the AWS CLI ([full list](docs/02-setup-guide.md#prerequisites)).

1. [Create a GitHub App](docs/02-setup-guide.md#step-1--create-a-github-app)
2. [Store its credentials in Secrets Manager](docs/02-setup-guide.md#step-2--store-the-github-app-credentials-in-aws-secrets-manager)
3. [Build the custom AMI](docs/02-setup-guide.md#step-3--build-the-custom-ami)
4. [Deploy the Terraform](docs/02-setup-guide.md#step-4--deploy-the-terraform-module)
5. [Point the app at the webhook](docs/02-setup-guide.md#step-5--point-the-github-app-at-the-deployed-webhook)
6. [Use it in a workflow](docs/02-setup-guide.md#step-6--use-it-in-workflows)

Only after that works: read [runner strategies](docs/04-runner-strategies.md) to decide whether you need more than one fleet, and [org rollout](docs/03-org-rollout.md) if this is going beyond your own account. Capacity limits, troubleshooting and teardown are in [operations](docs/05-operations.md).

## Repo layout

```
.
├── README.md                   — you are here
├── .github/workflows/
│   ├── ci.yml                  — smoke-test workflow that runs on the fleet (manual trigger)
│   └── terraform-checks.yml    — terraform fmt + validate on PRs
├── docs/
│   ├── 01-concepts.md
│   ├── 02-setup-guide.md
│   ├── 03-org-rollout.md
│   ├── 04-runner-strategies.md
│   └── 05-operations.md
├── terraform/                  — the runner fleet (github_runner module wrapper)
│   ├── versions.tf
│   ├── variables.tf
│   ├── main.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example   — copy to terraform.tfvars (gitignored)
└── scripts/
    └── download-lambda-packages.sh
```
