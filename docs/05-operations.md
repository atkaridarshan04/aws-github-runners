# Operations — keeping it running

## Rebuilding / updating the AMI

This is a manual, on-demand step — not something that belongs in your nightly CI, since AMI builds are infrequent (weeks/months) rather than per-commit. Rebuild when:

- A CVE lands in a baked-in tool version
- You need a new runtime/tool pre-installed
- The base Ubuntu image gets an LTS point release you want to pick up

```bash
cd terraform-aws-github-runner/images/ubuntu-jammy
packer build -var "region=<REGION>" github_agent.ubuntu.pkr.hcl
terraform apply   # picks up the new AMI automatically via the name filter
```

### Housekeeping

Old AMIs and their backing EBS snapshots are **not** cleaned up automatically. Deregister old AMIs and delete the associated snapshots periodically, or you'll accumulate storage cost indefinitely. A simple lifecycle script (keep last N, or older than X days) run manually or on a schedule is worth adding once you've rebuilt a handful of times — don't build it before you have a real backlog of stale AMIs.

## Cost notes

| Component | Typical cost driver |
|---|---|
| EC2 Spot instances | Pay only while jobs run; Spot is ~70% cheaper than on-demand |
| Lambda functions | Negligible — milliseconds per invocation |
| API Gateway | Negligible — pennies per webhook call |
| S3 (runner binary cache) | Minimal |
| NAT Gateway | Fixed hourly cost if runners launch into private subnets — usually the largest fixed line item |

For moderate usage (50-100 CI jobs/day), expect low tens of dollars per month for the runner infrastructure itself, excluding any NAT Gateway you'd already be paying for regardless.

Running [multiple fleets](04-runner-strategies.md)? Each fleet's Lambda/API Gateway cost is still negligible, but tag each fleet's resources (`prefix`, AWS cost allocation tags) so Spot spend is attributable per team — see the [org rollout checklist](03-org-rollout.md#rollout-checklist).
