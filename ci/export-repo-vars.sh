#!/usr/bin/env bash
# Shared implementation of terraform-checks.yml's/terraform-apply.yml's own
# "Export and verify extra repository variables" step -- both files had a
# byte-identical inline shell loop (extracted 2026-09-22, ponytail-audit).
#
# Usage (as a workflow step):
#   env:
#     ALL_VARS_JSON: ${{ toJSON(vars) }}
#   run: gha-common/ci/export-repo-vars.sh ${{ inputs.extra_repo_vars }}
#
# $ALL_VARS_JSON has to stay a real GitHub Actions expression in the
# calling step's own env: -- that's the one part no external script can
# produce -- everything after is plain shell, arguments are the
# space-separated repository-variable names to require and export.

set -euo pipefail

for name in "$@"; do
  value="$(echo "${ALL_VARS_JSON}" | jq -r --arg k "${name}" '.[$k] // empty')"
  if [ -z "${value}" ]; then
    echo "::error::Missing repository variable ${name}"
    exit 1
  fi
  lower="$(echo "${name}" | tr '[:upper:]' '[:lower:]')"
  echo "TF_VAR_${lower}=${value}" >> "${GITHUB_ENV}"
done
