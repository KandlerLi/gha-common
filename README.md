# gha-common

Shared CI Dockerfile and four `workflow_call` reusable GitHub Actions
workflows, used by every Terraform-based repo in this workspace that used
to carry its own near-identical `checks.yml`/`apply.yml`/`.github/ci/Dockerfile`
(`dyndns`, `website`, `aws-budget`, `homeserver-health-check`, `ses-relay`).
`home-infra` is a fundamentally different, Ansible-based pipeline and isn't
a consumer of the Terraform-specific workflows below (though it can still
call `trivy-config.yml`/`trivy-image.yml`, neither of which has a Terraform
dependency).

`trivy-config.yml` is additionally called by `repo-infra`, `terraform-state`,
and `k3s-bootstrap` -- the three repos that otherwise have no CI/self-hosted
runner at all -- with `runs_on` overridden to a GitHub-hosted runner, so
adopting it doesn't require provisioning a self-hosted runner for them. See
that workflow's own inline comments and the workspace-level `PARKED.md`
"Security audit" entry for the reasoning.

`trivy-image.yml` is only called by the repos that actually have pinned
container images to scan (`home-infra`, `k3s-apps`) -- most repos in this
workspace are pure Terraform with no image to scan at all.

This repo has no build/apply CI of its own (no `runner: true`/
`action_variables`/`required_status_check_contexts` entry in
`github/repo-infra/config.yml`) — a caller's `uses:` job runs under that
caller's own repository context (its own self-hosted runner
registration, its own `vars.*`/`secrets.*`), the reusable workflow file
just supplies the shared YAML. It does still call its own `gitleaks.yml`
on itself (`.github/workflows/security-scan.yml`) -- that reasoning
doesn't apply to a secrets scan, which needs no build/apply pipeline to
make sense, and this repo is public like every other repo in the audit.

## Why this repo is public

GitHub only allows cross-repository reusable workflows from a personal
(non-Enterprise) account when the repository holding the workflow is
public. All five current callers are public already.

## Versioning

Callers pin a specific semver tag (`@v0.0.7`), never `@main` — matches this
workspace's existing discipline of pinning third-party GitHub Actions by
exact version (`sha_pinning_required = true` in every managed repo's
`github_actions_repository_permissions`), applied here to a first-party
repo too. A bad edit to `gha-common` can't silently break every caller's CI
at once; each repo adopts a new tag deliberately, in its own commit.

To cut a new tag after a change here (never amend or force-push an
existing one, even a very recent or still-unadopted tag — always a new,
additive tag):

```bash
git tag v0.0.8
git push origin v0.0.8
```

Then bump the `@v0.0.7` → `@v0.0.8` reference in whichever caller repo(s)
should pick it up, one repo/commit at a time.

## `ci/Dockerfile`

Terraform plus the handful of extra tools every caller's workflows need
(`awscli`, `git`, `python3`, `unzip`). Built and pushed fresh on every
workflow run (`ghcr.io/kandlerli/<calling-repo-name>-ci:latest`) by the
`build-image` job in either reusable workflow below — that job checks out
both the calling repo (for everything else) and this repo (just for the
Dockerfile, at a hardcoded `ref:` bumped by hand alongside any new tag).

## `.github/workflows/terraform-checks.yml`

PR-time checks: build the CI image, `terraform fmt`/`validate` (+ an
optional extra command), then a speculative `terraform plan` using
read-only, short-lived AWS credentials — only for PRs from the repo itself,
never forks. Mirrors `dyndns`'s original `checks.yml` almost exactly; see
that workflow's own inline comments for the reasoning behind each step
(the OIDC `action-timeout-s` mitigation in particular).

Inputs:

| Input | Required | Description |
|---|---|---|
| `aws_region` | yes | Region for the read-only plan credentials. |
| `extra_repo_vars` | no | Space-separated repository variable names (e.g. `"ROUTE53_ZONE_ID ALERT_EMAIL"`) that must be set and get exported as `TF_VAR_<lowercased_name>`. Covers whatever named variables that repo's own Terraform needs, without ever having to edit this shared workflow. |
| `extra_validate_command` | no | Extra shell command run in the validate job (e.g. a repo's own unit test suite). |

Caller shape:

```yaml
name: Checks
on:
  pull_request:
  workflow_dispatch:
jobs:
  terraform:
    uses: KandlerLi/gha-common/.github/workflows/terraform-checks.yml@v0.0.7
    with:
      aws_region: eu-central-1
      extra_repo_vars: "ROUTE53_ZONE_ID"
    secrets: inherit
    permissions:
      contents: read
      id-token: write
      # A caller's job-level permissions cap every nested job inside the
      # reusable workflow -- must cover the union of what any of them
      # ask for. build-image needs write (it pushes to GHCR); the
      # narrower validate/plan jobs still only get what they themselves
      # request internally. packages: read here fails with "requesting
      # 'packages: write', but is only allowed 'packages: read'".
      packages: write
```

## `.github/workflows/terraform-apply.yml`

Same shape, triggered on `main`: build the image, real `terraform apply`
with short-lived deploy credentials from the `production` environment, then
an optional post-apply command.

Inputs: same `aws_region`/`extra_repo_vars`/`extra_validate_command` as
above, plus:

| Input | Required | Description |
|---|---|---|
| `post_apply_command` | no | Shell command run after a successful `terraform apply`, with the same AWS credentials (e.g. `website`'s S3 sync + CloudFront invalidation). |

Caller shape:

```yaml
name: Apply
on:
  push:
    branches: [main]
  workflow_dispatch:
permissions:
  contents: read
  id-token: write
  packages: write # see terraform-checks.yml's caller shape for why
concurrency:
  group: <repo-name>-terraform
  cancel-in-progress: false
jobs:
  terraform:
    uses: KandlerLi/gha-common/.github/workflows/terraform-apply.yml@v0.0.7
    with:
      aws_region: eu-central-1
      extra_repo_vars: "ROUTE53_ZONE_ID"
    secrets: inherit
```

`concurrency` stays declared in the caller — `workflow_call` doesn't carry
concurrency settings through from the reusable workflow itself.

## `.github/workflows/trivy-config.yml`

`trivy config` IaC misconfiguration scan — no Docker image build, no AWS
credentials, findings land in the job summary. Fails the job on any
finding, including Low severity (`exit-code: "1"`). Its own workflow
rather than a job folded into the two above, specifically so that failure
stays structurally incapable of blocking a plan/apply — it's a visible red
check on the commit, not a gate; making it an actual gate would need a
`needs:` dependency from apply's own job or a branch-protection required
status check, neither of which this does.

Inputs:

| Input | Required | Description |
| --- | --- | --- |
| `runs_on` | no | JSON array of runner labels, e.g. `'["ubuntu-latest"]'`. Defaults to this workspace's usual self-hosted runner (`'["self-hosted", "home", "debian"]'`). |

Caller shape (typical — self-hosted runner, one of the repos that already
has one registered):

```yaml
name: Security scan
on:
  push:
    branches: [main]
  workflow_dispatch:
jobs:
  trivy-config:
    uses: KandlerLi/gha-common/.github/workflows/trivy-config.yml@v0.0.9
    permissions:
      contents: read
```

Caller shape (`repo-infra`/`terraform-state`/`k3s-bootstrap` — no
self-hosted runner registered for these, deliberately not provisioning one
just for a read-only scan):

```yaml
name: Security scan
on:
  push:
    branches: [main]
  workflow_dispatch:
jobs:
  trivy-config:
    uses: KandlerLi/gha-common/.github/workflows/trivy-config.yml@v0.0.9
    with:
      runs_on: '["ubuntu-latest"]'
    permissions:
      contents: read
```

## `.github/workflows/trivy-image.yml`

`trivy image` container CVE scan, one caller-side matrix entry per pinned
image -- no Docker image build of its own, no AWS credentials. Unlike
`trivy-config.yml`, this one is deliberately informational only
(`exit-code: "0"`): real per-image finding counts run into the hundreds or
thousands (almost entirely upstream OS/library CVEs in third-party base
images this workspace doesn't build, not something a required check could
ever reasonably drive to zero). Findings still land in the job summary, so
drift over time stays visible even though nothing blocks on it. See the
workspace-level `PARKED.md` "Security audit" entry for the real counts
that drove this choice.

Logs in to GHCR with the caller's own `GITHUB_TOKEN` before scanning
(harmless for a non-GHCR `image_ref`) -- needed for a private package like
this account's own `home-agent`/`sankey-export` images, since trivy has no
separate registry-auth input and instead reads the runner's own Docker
config the same way `checks.yml`/`build-home-agent.yml` already do to
push. Requires the caller to grant `packages: read`, not just
`contents: read`.

Inputs:

| Input | Required | Description |
| --- | --- | --- |
| `image_name` | yes | Short label for the image, shown in the job name and job summary. |
| `image_ref` | yes | Full image reference, digest-pinned where the caller pins it. |
| `runs_on` | no | JSON array of runner labels, e.g. `'["ubuntu-latest"]'`. Defaults to this workspace's usual self-hosted runner (`'["self-hosted", "home", "debian"]'`). |

Caller shape (one job per image, via a matrix):

```yaml
jobs:
  trivy-image:
    strategy:
      fail-fast: false
      matrix:
        include:
          - name: some-image
            ref: docker.io/some/image:1.2.3@sha256:...
          - name: another-image
            ref: ghcr.io/some/other-image:4.5.6@sha256:...
    uses: KandlerLi/gha-common/.github/workflows/trivy-image.yml@v0.0.10
    with:
      image_name: ${{ matrix.name }}
      image_ref: ${{ matrix.ref }}
    permissions:
      contents: read
      packages: read
```
