# Runner strategies — one fleet vs. several, ephemeral vs. persistent

Two independent axes get conflated a lot when people say "should we go multi-cluster." This doc separates them and gives a decision table for each.

## Axis 1 — Ephemeral vs. persistent runners

| | **Ephemeral** (this repo's default) | **Persistent** |
|---|---|---|
| Lifecycle | One instance per job, terminates after | Long-running instance, polls for jobs repeatedly |
| Security | Clean environment every job, nothing to leak between jobs | State (caches, credentials used by a prior job) can leak across jobs unless carefully cleaned |
| Cost | Pay only for job runtime | Pay for idle time too, unless you build your own scale-to-zero |
| Cold start | ~30s with a custom AMI | ~0s — already running |
| Best for | PR checks, test suites, scans, builds — anything that should be reproducible and stateless | Workloads with expensive warm state that's expensive to rebuild per job: huge dependency caches, GPU driver/model warmup, license-server-bound tooling with slow handshake |

**Default to ephemeral.** It's what the [setup guide](02-setup-guide.md) deploys, and it's the right choice for the overwhelming majority of CI (build/test/scan on every push or PR). Only reach for persistent runners when a specific, measured cold-start or state-rebuild cost justifies the security and cost tradeoffs — don't build a persistent fleet speculatively "in case we need the caching later."

If you do need persistent, it's usually cheaper to first try: (a) S3/cache-action-backed dependency caching from an ephemeral runner, or (b) a bigger instance type with more local NVMe for cache locality, before standing up a whole separate persistent fleet.

## Axis 2 — Single fleet vs. multiple fleets ("multi-cluster")

A "fleet" here means one deployment of the `github_runner` module — one `prefix`, one AMI, one IAM role, one set of instance types, one scale-down policy. "Multi-cluster" just means running that module more than once with different config, targeting different runner labels/groups.

### Single fleet — when it's enough

- One team, one repo or a handful of similar repos
- Jobs have roughly uniform resource needs (similar instance size, same OS/arch, same tool baseline)
- No hard security boundary between the workloads running on it (a compromised job on repo A shouldn't be a meaningfully different blast radius than one on repo B)
- This is the [setup guide](02-setup-guide.md)'s default and should be your starting point regardless of eventual scale — split later, when a concrete need shows up.

### Multiple fleets — when one isn't enough

Split into separate `module "github_runner"` instances (different `prefix`, and usually different `github_app`/runner-group scoping) when any of these is true:

| Trigger | Why a single fleet breaks down |
|---|---|
| **Different IAM needs** | A fleet running deploy jobs needs prod-write AWS credentials; a fleet running PR checks should never have them. One fleet means one IAM role for every job that lands on it — don't give PR-check jobs prod access just because they share a fleet with deploy jobs. |
| **Different architecture/OS** | `arm64` vs `x64`, or Windows vs Linux runners, can't share an AMI or often even an instance-type list. |
| **Very different resource shape** | A fleet mostly running lightweight lint jobs vs. one running large integration-test suites or GPU jobs — sizing one fleet for the biggest job wastes money on every small one. |
| **Different security/compliance boundary** | A team handling regulated workloads wants its own AMI provenance, its own logging retention, its own network path — auditable in isolation from the general-purpose fleet. |
| **Blast-radius isolation between teams** | You don't want team A's runaway job (queue flood, malicious dependency) exhausting the Spot capacity or `runners_maximum_count` budget team B depends on. |
| **Independent rebuild/rollout cadence** | Team A wants to bump their AMI weekly for a fast-moving toolchain; team B wants theirs to change monthly. Coupled into one fleet, every rebuild is a negotiation. |

### What "multiple fleets" costs you

- More Terraform to maintain (though it's the same module, parameterized differently — not more *design*)
- More AMIs to patch and rebuild (unless fleets share a [base AMI](03-org-rollout.md#ami-ownership-models-at-org-scale))
- More runner groups to keep straight on the GitHub side
- Slightly more Lambda/API Gateway surface (each fleet gets its own webhook stack, unless you invest in sharing it — usually not worth the complexity)

None of this is free, so the trigger table above is a checklist, not a suggestion to default to multiple fleets. If nothing in it applies to you, one fleet is correct.

## Decision summary

```
Do you have a workload with expensive state that's costly to rebuild every job
(large caches, GPU warmup, slow license handshake)?
  └── Yes → consider a persistent fleet for THAT workload only, ephemeral for everything else
  └── No  → ephemeral (default)

Does any trigger in the "multiple fleets" table apply?
  └── No  → one fleet
  └── Yes → one fleet per distinct IAM/arch/security/cadence boundary,
            sharing a base AMI where practical
```

Start with one ephemeral fleet ([setup guide](02-setup-guide.md)). Split only when a concrete trigger from the table above shows up — see [org rollout](03-org-rollout.md) for the operational changes that come with going multi-team/multi-fleet.
