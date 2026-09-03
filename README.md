# gha-common

Shared CI Dockerfile and two `workflow_call` reusable GitHub Actions
workflows, used by every Terraform-based repo in this workspace that used
to carry its own near-identical `checks.yml`/`apply.yml`/`.github/ci/Dockerfile`
(`dyndns`, `website`, `aws-budget`, `homeserver-health-check`, `ses-relay`).
`home-infra` is a fundamentally different, Ansible-based pipeline and isn't
a consumer of this repo.

This repo has no CI of its own (no `runner: true`/`action_variables`/
`required_status_check_contexts` entry in `bootstrap/repo-infra/config.yml`)
— nothing ever runs *in* `gha-common` itself. A caller's `uses:` job runs
under that caller's own repository context (its own self-hosted runner
registration, its own `vars.*`/`secrets.*`), the reusable workflow file
just supplies the shared YAML.

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
