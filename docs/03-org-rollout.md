# From personal setup to org-level rollout

The [setup guide](02-setup-guide.md) gets you one fleet, in one AWS account, for one GitHub account/org. This doc covers what actually changes when the consumer is an organization with multiple teams and repos instead of just you — it's notes and a checklist, not a separate step-by-step (the deploy mechanics are identical, only the *scope* of things changes).

## What changes

| Concern | Personal / single-team | Org-level |
|---|---|---|
| **GitHub App install** | Installed on your personal account or one repo | Installed at the org level, scoped to "All repositories" or a curated repo list |
| **`enable_organization_runners`** | Either works | `true` — runners register at the org, not a single repo, so any repo in-scope can use them |
| **Runner groups** | Not needed | Use [GitHub runner groups](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/managing-access-to-self-hosted-runners-using-groups) to restrict which repos/teams can target which fleet — otherwise every repo in the org can burn your Spot budget |
| **Who holds the GitHub App private key** | You | A team/service account with rotation policy — this key is org-wide runner-registration authority, treat it like a production credential |
| **AWS account boundary** | Any account you control | Usually its own AWS account (or a dedicated OU) so runner IAM roles and Spot spend are isolated from other workloads — makes cost allocation and blast-radius containment much simpler |
| **IAM for the runner itself** | Whatever the job needs | Scoped per fleet/team (see [runner strategies](04-runner-strategies.md)) — a runner used by the payments team shouldn't have the same AWS permissions as one used by the marketing site |
| **AMI ownership** | You build and rebuild it | A platform/infra team owns the base AMI; individual teams either use it as-is or layer their own image on top (see below) |
| **Branch protection** | Optional | Required — an org rollout only pays off if PRs actually can't merge without passing on your runners, so `runs-on: [self-hosted, ...]` jobs need to be marked required checks |
| **Cost tagging** | Not necessary | Tag the fleet (`prefix`, plus AWS cost allocation tags) per team/project so Spot spend is attributable |

## AMI ownership models at org scale

Two reasonable patterns, pick one instead of letting it happen by accident:

1. **One shared base AMI.** Platform team maintains a single Packer template with the common toolchain (Docker, runner binary, AWS CLI, common linters). Teams that need more either `apt install` it in the job (fine for rarely-used tools) or fork the template.
2. **One base AMI + per-team overlay AMIs.** Platform team publishes a base AMI; teams with heavy/unusual tooling (e.g. a team building GPU workloads, or one needing a huge dependency cache) run their own Packer build `FROM` the base, producing `<TEAM>-runner-*` AMIs. More AMIs to keep patched, but keeps the shared base lean.

Start with (1). Move to (2) only when a specific team's build times or image bloat actually justify it — don't pre-build the overlay system speculatively.

## Multiple fleets, not one bigger fleet

At org scale, the temptation is to raise `runners_maximum_count` on a single fleet and call it done. Usually wrong once you have more than one team with meaningfully different requirements (different IAM, different instance sizes, different AMI, security-sensitive workloads). See [runner strategies](04-runner-strategies.md) for when to split into multiple `module "github_runner"` instances instead.

## Rollout checklist

- [ ] GitHub App installed at the org, permissions scoped as in the [setup guide](02-setup-guide.md#step-1--create-a-github-app)
- [ ] `enable_organization_runners = true`
- [ ] Runner groups configured, repos assigned to the right group
- [ ] GitHub App private key stored in Secrets Manager, access restricted to the Terraform deploy role — not a laptop
- [ ] Dedicated AWS account/OU for runner infra (or clear tagging if shared)
- [ ] Base AMI ownership assigned to a team, rebuild cadence documented (see [operations](05-operations.md))
- [ ] Branch protection rules require the self-hosted-runner checks
- [ ] Cost allocation tags on the fleet(s)
