# Operations — keeping it running

## Contents

- [Capacity and limits](#capacity-and-limits)
- [Rebuilding / updating the AMI](#rebuilding--updating-the-ami)
- [Cost notes](#cost-notes)
- [Troubleshooting](#troubleshooting)
- [Teardown](#teardown)

## Capacity and limits

| Setting | Where | What it does |
|---|---|---|
| `runners_maximum_count` | `terraform/variables.tf` (default 8) | Hard cap on concurrent runner instances. Runners are ephemeral, so this is also the cap on concurrent jobs. Jobs over the cap wait in the queue and show as **Queued** in GitHub; nothing fails. `-1` removes the cap. |
| `scale_up_reserved_concurrent_executions` | `terraform/variables.tf` (default 1) | Serialises the scale-up Lambda so the cap is checked against an accurate count. `-1` removes the reservation (needed on fresh accounts with a low Lambda concurrency quota). |
| `scale_down_schedule_expression` | `terraform/variables.tf` | How often the scale-down Lambda sweeps (default every 5 minutes). |
| `minimum_running_time_in_minutes` | `terraform/variables.tf` (default 15) | An instance must have been running this long before scale-down may terminate it, and only if it is not busy. It is **not** a limit on job length. |

What actually bounds a job: GitHub's job timeout (360 minutes by default, set per job with `timeout-minutes`) and Spot interruption.

Other ceilings to check before raising the cap:

- **Spot vCPU quota**, per region: "All Standard (A, C, D, H, I, M, R, T, Z) Spot Instance Requests" (quota code `L-34B43A08`).
- **Free IPs** in the subnets the runners launch into.

```bash
aws service-quotas get-service-quota --service-code ec2 --quota-code L-34B43A08 --region <REGION> \
  --query 'Quota.[QuotaName,Value]' --output text
```

## Rebuilding / updating the AMI

This is a manual, on-demand step, not something that belongs in your nightly CI, since AMI builds are infrequent (weeks or months) rather than per-commit. Rebuild when:

- A CVE lands in a baked-in tool version
- You need a new runtime or tool pre-installed
- The base Ubuntu image gets an LTS point release you want to pick up

```bash
cd terraform-aws-github-runner/images/ubuntu-jammy
packer build -var "region=<REGION>" github_agent.ubuntu.pkr.hcl

cd -   # back to this repo
terraform -chdir=terraform apply   # picks up the new AMI automatically via the name filter
```

### Housekeeping

Old AMIs and their backing EBS snapshots are **not** cleaned up automatically. Deregister old AMIs and delete the associated snapshots periodically, or you'll accumulate storage cost indefinitely. A simple lifecycle script (keep last N, or older than X days) run manually or on a schedule is worth adding once you've rebuilt a handful of times. Don't build it before you have a real backlog of stale AMIs.

## Cost notes

| Component | Typical cost driver |
|---|---|
| EC2 Spot instances | Pay only while jobs run; Spot is ~70% cheaper than on-demand |
| Lambda functions | Negligible: milliseconds per invocation |
| API Gateway | Negligible: pennies per webhook call |
| S3 (runner binary cache) | Minimal |
| NAT Gateway | Fixed hourly cost if runners launch into private subnets; usually the largest fixed line item |

For moderate usage (50-100 CI jobs/day), expect low tens of dollars per month for the runner infrastructure itself, excluding any NAT Gateway you'd already be paying for regardless.

Running [multiple fleets](04-runner-strategies.md)? Each fleet's Lambda/API Gateway cost is still negligible, but tag each fleet's resources (`prefix`, AWS cost allocation tags) so Spot spend is attributable per team. See the [org rollout checklist](03-org-rollout.md#rollout-checklist).

## Troubleshooting

| Symptom | Likely cause | Where to look / fix |
|---|---|---|
| Job stays "Waiting for a runner" and no instance appears | Webhook not reaching the Lambda, or the scale-up Lambda failing | App settings → **Advanced → Recent deliveries** (should be `200`); then `/aws/lambda/<PROJECT_NAME>-gh-runner-scale-up` |
| Same, on a personal-account setup | `enable_organization_runners = true` on a personal account; the org registration API doesn't exist there and scale-up fails on every job | Set `enable_organization_runners = false` |
| Scale-up log shows a 403 from GitHub | The app is missing a permission, or isn't installed on that repo | Recheck [step 1](02-setup-guide.md#step-1--create-a-github-app) permissions and installation scope |
| Instance launches but never registers | Boot problem or registration failure | `/github-self-hosted-runners/<PROJECT_NAME>-gh-runner/*` log groups, or a Session Manager shell ([how](02-setup-guide.md#open-a-shell-on-a-runner)) |
| Webhook deliveries show errors in GitHub | The endpoint is rejecting or failing the request | Status codes per request in `/aws/apigateway/<PROJECT_NAME>-gh-runner-webhook-access`; a signature failure is the next row |
| Webhook deliveries fail signature validation | Webhook secret in Secrets Manager differs from the one set on the app | Make them match, then `terraform apply` |
| `terraform plan` fails to find the AMI | No AMI matching `github-runner-ubuntu-jammy-amd64-*` in this account | Build it ([step 3](02-setup-guide.md#step-3--build-the-custom-ami)) |
| Lambda deploy fails after a module version bump | Lambda zips don't match the pinned module version | Re-run `scripts/download-lambda-packages.sh` (it reads the pinned version from `main.tf`) |
| Scale-up Lambda logs a service-linked-role error | The account has no `AWSServiceRoleForEC2Spot` yet and it couldn't be created | Create it once: `aws iam create-service-linked-role --aws-service-name spot.amazonaws.com` |
| Apply fails: "decreases account's UnreservedConcurrentExecution below its minimum value of [10]" | Low account-wide Lambda concurrency quota | Set `scale_up_reserved_concurrent_executions = -1`, or request a quota increase |

## Teardown

1. Make sure no jobs are running. Running instances are terminated by `destroy`.
2. Remove the infrastructure:

   ```bash
   terraform -chdir=terraform destroy
   ```

3. Deregister the AMIs and delete their snapshots (not managed by Terraform):

   ```bash
   aws ec2 describe-images --owners self --region <REGION> \
     --filters "Name=name,Values=github-runner-ubuntu-jammy-amd64-*" \
     --query 'Images[].[ImageId,Name]' --output table
   aws ec2 deregister-image --image-id <AMI_ID> --region <REGION>
   aws ec2 delete-snapshot --snapshot-id <SNAPSHOT_ID> --region <REGION>
   ```

4. Delete the `<PROJECT_NAME>-github-app-secrets` secret, and delete or uninstall the GitHub App.
